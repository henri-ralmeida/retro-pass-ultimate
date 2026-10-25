extends RefCounted
## Run only after confirmed local processing, preferably on the owning worker.
## Produces a new catalog snapshot; never writes catalogs or source files and
## never creates textures. Hash + bounded decode validates format, not edition.
const Inventory = preload("res://cosmic/catalog_import.gd")
const Artwork = preload("res://cosmic/library_artwork_cache.gd")
const Config = preload("res://cosmic/media_optin_config.gd")
const SURFACES := {
 "cover_front":"cover_front", "boxart":"cover_front", "cover_back":"cover_back", "boxback":"cover_back",
 "cover_spine":"cover_spine", "boxspine":"cover_spine", "spine":"cover_spine", "cover_edge":"cover_edge",
 "cartridge_label":"cartridge_label", "cartridge_top":"cartridge_top", "wheel":"wheel", "marquee":"wheel"}

static func identity_signature(item: Dictionary) -> String:
 # Includes edition hints without interpreting them, plus exact source path.
 var values: Array = []
 for field in ["id", "system", "relative_path", "source_group", "source_game_id", "region_hint", "language_hint", "filename_variant_hints", "variant", "edition", "region"]:
  values.append(item.get(field, null))
 return JSON.stringify(values).sha256_text()

static func build(result: Dictionary, items: Array, cancelled: Callable = Callable()) -> Dictionary:
 var output := {"items":items.duplicate(true), "applied":0, "issues":[], "validated_files":0, "bytes_revalidated":0, "changed_paths":[], "status":"done"}
 var config: Variant = result.get("config", {})
 if not config is Dictionary or not result.get("files") is Array or result.get("status", "") not in ["done", "completed_with_errors"]:
  output.issues.append({"status":"not_completed"})
  return output
 if not Config.choose(str(config.get("system", "")), str(config.get("root", "")), config.get("categories", [])).ok:
  output.issues.append({"status":"invalid_config"})
  return output
 var indices := {}
 for index in items.size():
  if not items[index] is Dictionary: continue
  var key := str(items[index].get("system", "")) + ":" + str(items[index].get("id", ""))
  if not indices.has(key): indices[key] = []
  indices[key].append(index)
 var candidates := {}
 for job in result.files:
  if not job is Dictionary or job.get("status", "") != "done" or not job.get("links") is Array: continue
  var relative := Inventory.safe_relative_path(job.get("relative_path", ""))
  var path := str(config.root).path_join(relative)
  if relative.is_empty() or job.get("id", "") != path.sha256_text():
   output.issues.append({"status":"invalid_path"})
   continue
  for link in job.links:
   if not link is Dictionary: continue
   var tag := str(link.get("tag", ""))
   var field := str(SURFACES.get(tag, ""))
   var key := str(config.system) + ":" + str(link.get("game_id", ""))
   var issue := {"game_id":link.get("game_id", ""), "tag":tag}
   if field.is_empty():
    issue.status = "not_applied_unsupported_surface"
    output.issues.append(issue)
    continue
   var category := "wheel" if field == "wheel" else "covers"
   if not category in config.categories or not indices.has(key) or indices[key].size() != 1:
    issue.status = "missing_or_ambiguous_exact_identity"
    output.issues.append(issue)
    continue
   var index: int = indices[key][0]
   var item: Dictionary = items[index]
   var metadata: Variant = item.get("media_metadata", {})
   var descriptor: Variant = metadata.get(tag, {}) if metadata is Dictionary else {}
   if not descriptor is Dictionary or descriptor.get("status", "") != "present" or descriptor.get("relative_path", "") != relative or link.get("catalog_identity", "") != identity_signature(item):
    issue.status = "catalog_reference_changed"
    output.issues.append(issue)
    continue
   var candidate_key := str(index) + ":" + field
   if not candidates.has(candidate_key): candidates[candidate_key] = []
   candidates[candidate_key].append({"index":index, "field":field, "path":path, "tag":tag, "job":job, "issue":issue})
 # Refuse conflicting aliases for one surface rather than picking a plausible art.
 var validation := {}
 for key in candidates:
  var entries: Array = candidates[key]
  var paths := {}
  for candidate in entries: paths[candidate.path] = true
  if paths.size() != 1:
   output.issues.append({"status":"ambiguous_surface", "surface":entries[0].field})
   continue
  var candidate: Dictionary = entries[0]
  if _cancelled(cancelled):
   return {"items":items.duplicate(true), "applied":0, "issues":[{"status":"cancelled"}], "validated_files":output.validated_files, "bytes_revalidated":output.bytes_revalidated, "changed_paths":[], "status":"cancelled"}
  if not validation.has(candidate.path):
   validation[candidate.path] = _validate_image(candidate.path, str(candidate.job.get("sha256", "")))
   output.bytes_revalidated += int(validation[candidate.path].get("bytes", 0))
   if validation[candidate.path].status == "valid": output.validated_files += 1
  var checked: Dictionary = validation[candidate.path]
  if checked.status != "valid":
   var issue: Dictionary = candidate.issue.duplicate()
   issue.status = checked.status
   output.issues.append(issue)
   continue
  var updated: Dictionary = output.items[candidate.index]
  # Retain the prior surface and provenance; no edition claim and no destructive rewrite.
  if not updated.get("local_media_previous") is Dictionary: updated.local_media_previous = {}
  if not updated.local_media_previous.has(candidate.field): updated.local_media_previous[candidate.field] = updated.get(candidate.field, "")
  updated[candidate.field] = candidate.path
  if not updated.get("local_media_validation") is Dictionary: updated.local_media_validation = {}
  updated.local_media_validation[candidate.field] = {"tag":candidate.tag, "sha256":candidate.job.sha256, "status":"decoded_current", "identity_status":"unverified", "source":"explicit_local_processing"}
  output.applied += 1
  if not candidate.path in output.changed_paths: output.changed_paths.append(candidate.path)
 if _cancelled(cancelled):
  return {"items":items.duplicate(true), "applied":0, "issues":[{"status":"cancelled"}], "validated_files":output.validated_files, "bytes_revalidated":output.bytes_revalidated, "changed_paths":[], "status":"cancelled"}
 return output

static func _cancelled(callback: Callable) -> bool:
 return callback.is_valid() and bool(callback.call())

static func _validate_image(path: String, expected_hash: String) -> Dictionary:
 if expected_hash.length() != 64: return {"status":"missing_current_hash"}
 var cursor := path
 while cursor != cursor.get_base_dir():
  var parent := DirAccess.open(cursor.get_base_dir())
  if parent == null or parent.is_link(cursor.get_file()): return {"status":"unsafe_or_missing_path"}
  cursor = cursor.get_base_dir()
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null: return {"status":"unreadable"}
 var length := file.get_length()
 if length <= 0 or length > Artwork.MAX_SOURCE_BYTES:
  file.close()
  return {"status":"source_file_limit"}
 var header := file.get_buffer(mini(length, 512 * 1024))
 var dimensions := Artwork._header_dimensions(header)
 if dimensions.x <= 0 or dimensions.y <= 0 or int(dimensions.x) * int(dimensions.y) > Artwork.MAX_SOURCE_PIXELS:
  file.close()
  return {"status":"unsupported_or_oversized_header"}
 file.seek(0)
 var bytes := file.get_buffer(length)
 file.close()
 if bytes.size() != length: return {"status":"short_read", "bytes":bytes.size()}
 var hash := HashingContext.new()
 hash.start(HashingContext.HASH_SHA256)
 hash.update(bytes)
 if hash.finish().hex_encode() != expected_hash: return {"status":"source_changed_after_processing", "bytes":length}
 # Decode the SAME validated bytes, not a second Image.load(path) susceptible
 # to a replacement between hash and decode. Runtime cache still owns textures.
 var image := Image.new()
 var error := ERR_FILE_UNRECOGNIZED
 match path.get_extension().to_lower():
  "png": error = image.load_png_from_buffer(bytes)
  "jpg", "jpeg": error = image.load_jpg_from_buffer(bytes)
  "webp": error = image.load_webp_from_buffer(bytes)
 if error != OK or image.is_empty(): return {"status":"decode_failed", "bytes":length}
 if image.get_size() != dimensions or int(image.get_width()) * int(image.get_height()) > Artwork.MAX_SOURCE_PIXELS:
  return {"status":"decoded_dimension_mismatch", "bytes":length}
 return {"status":"valid", "bytes":length}
