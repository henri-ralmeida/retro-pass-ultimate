extends RefCounted
## Run only after confirmed local processing, preferably on the owning worker.
## Produces a new catalog snapshot; never writes catalogs or source files and
## never creates textures. Hash + bounded decode validates format, not edition.
const Inventory = preload("res://cosmic/catalog_import.gd")
const Artwork = preload("res://cosmic/library_artwork_cache.gd")
const Pdf = preload("res://cosmic/manual_pdf_service.gd")
const Config = preload("res://cosmic/media_optin_config.gd")
const SURFACES := {
 "cover_front":"cover_front", "boxart":"cover_front", "cover_back":"cover_back", "boxback":"cover_back",
 "cover_spine":"cover_spine", "boxspine":"cover_spine", "spine":"cover_spine", "cover_edge":"cover_edge",
 "cartridge_label":"cartridge_label", "cartridge_top":"cartridge_top", "wheel":"wheel", "marquee":"wheel",
 "image":"media_image", "thumbnail":"media_thumbnail", "fanart":"media_fanart",
 "cartridge":"media_cartridge", "titleshot":"media_titleshot", "screenshot":"media_screenshot",
 "map":"media_map", "bezel":"media_bezel", "manual":"manual_pages"}

static func canonical_system(item: Dictionary) -> String:
 # Only these explicit aliases are equivalent. Never infer a system from a path.
 var system := str(item.get("system", item.get("system_id", "")))
 var canonical := "atari_2600" if system == "atari2600" else system
 if item.has("system") and item.has("system_id"):
  var other := str(item.system_id)
  if other == "atari2600": other = "atari_2600"
  if canonical != other: return ""
 return canonical

static func category_for(tag: String) -> String:
 if tag == "manual": return "manual"
 var field := str(SURFACES.get(tag, ""))
 if field == "wheel": return "wheel"
 if field.begins_with("media_"): return "images"
 return "covers" if not field.is_empty() else ""

static func identity_signature(item: Dictionary) -> String:
 # Includes edition hints without interpreting them, plus exact source path.
 var values: Array = []
 for field in ["id", "system", "relative_path", "source_group", "source_game_id", "region_hint", "language_hint", "filename_variant_hints", "variant", "edition", "region", "system_id", "media_metadata"]:
  values.append(item.get(field, null))
 return JSON.stringify(values).sha256_text()

static func build(result: Dictionary, items: Array, cancelled: Callable = Callable()) -> Dictionary:
 var output := {"items":items.duplicate(true), "applied":0, "issues":[], "validated_files":0, "bytes_revalidated":0, "changed_paths":[], "status":"done", "bindings":[], "remove_bindings":[]}
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
  var key := canonical_system(items[index]) + ":" + str(items[index].get("id", ""))
  if not indices.has(key): indices[key] = []
  indices[key].append(index)
 var candidates := {}
 for job in result.files:
  if not job is Dictionary or job.get("status", "") not in ["done", "error"] or not job.get("links") is Array: continue
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
   var category := category_for(tag)
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
   if tag == "manual":
    if not relative.get_extension().to_lower() in ["png", "jpg", "jpeg", "pdf"] or str(item.get("manual_item_id", item.get("id", ""))) != str(item.get("id", "")) or str(item.get("manual_game_id", item.get("id", ""))) != str(item.get("id", "")):
     issue.status = "manual_identity_or_format_unsupported"
     output.issues.append(issue)
     continue
   var candidate_key := str(index) + ":" + field
   if not candidates.has(candidate_key): candidates[candidate_key] = []
   candidates[candidate_key].append({"index":index, "field":field, "path":path, "tag":tag, "job":job, "issue":issue})
 # Refuse conflicting aliases for one surface rather than picking a plausible art.
 var validation := {}
 for key in candidates:
  var entries: Array = candidates[key]
  # Revalidation is transactional: a failed current source must not leave the
  # previous overlay visible in this session. Original metadata remains intact.
  var first: Dictionary = entries[0]
  var rollback: Dictionary = output.items[first.index]
  output.remove_bindings.append(JSON.stringify([canonical_system(rollback),str(rollback.get("id", "")),first.field]))
  if rollback.get("local_media_validation", {}).has(first.field):
   var old_paths: Array = rollback.get(first.field, []) if first.field == "manual_pages" else [rollback.get(first.field, "")]
   for old_path in old_paths:
    if not str(old_path).is_empty() and not old_path in output.changed_paths: output.changed_paths.append(old_path)
   rollback[first.field] = rollback.get("local_media_previous", {}).get(first.field, [] if first.field == "manual_pages" else "")
   rollback.local_media_validation.erase(first.field)
   if first.field == "manual_pages":
    var old_id: Variant = rollback.get("local_media_previous", {}).get("manual_item_id")
    if old_id == null: rollback.erase("manual_item_id")
    else: rollback.manual_item_id = old_id
  var paths := {}
  for candidate in entries: paths[JSON.stringify([candidate.path,candidate.job.get("sha256", "")])] = true
  if paths.size() != 1:
   output.issues.append({"status":"ambiguous_surface", "surface":entries[0].field})
   continue
  var candidate: Dictionary = entries[0]
  if candidate.tag == "manual" and str(candidate.path).get_extension().to_lower() == "pdf":
   var pdf_issue: Dictionary = candidate.issue.duplicate()
   pdf_issue.status = Pdf.capability().status
   output.issues.append(pdf_issue)
   continue
  if candidate.job.get("status", "") != "done":
   var failed_issue: Dictionary = candidate.issue.duplicate()
   failed_issue.status = "source_processing_failed"
   output.issues.append(failed_issue)
   continue
  if _cancelled(cancelled):
   return {"items":items.duplicate(true), "applied":0, "issues":[{"status":"cancelled"}], "validated_files":output.validated_files, "bytes_revalidated":output.bytes_revalidated, "changed_paths":[], "status":"cancelled"}
  var validation_key := JSON.stringify([candidate.path,candidate.job.get("sha256", "")])
  if not validation.has(validation_key):
   validation[validation_key] = _validate_image(candidate.path, str(candidate.job.get("sha256", "")))
   output.bytes_revalidated += int(validation[validation_key].get("bytes", 0))
   if validation[validation_key].status == "valid": output.validated_files += 1
  var checked: Dictionary = validation[validation_key]
  if candidate.field == "manual_pages" and checked.status == "valid" and (checked.get("bytes", 0) > 8 * 1024 * 1024 or checked.get("width", 0) > 4096 or checked.get("height", 0) > 4096):
   checked = {"status":"manual_page_limit"}
  if checked.status != "valid":
   var issue: Dictionary = candidate.issue.duplicate()
   issue.status = checked.status
   output.issues.append(issue)
   continue
  var updated: Dictionary = output.items[candidate.index]
  # Retain the prior surface and provenance; no edition claim and no destructive rewrite.
  if not updated.get("local_media_previous") is Dictionary: updated.local_media_previous = {}
  if not updated.local_media_previous.has(candidate.field): updated.local_media_previous[candidate.field] = updated.get(candidate.field, "")
  if candidate.field == "manual_pages":
   if not updated.local_media_previous.has("manual_item_id"): updated.local_media_previous.manual_item_id = updated.get("manual_item_id", null)
   updated.manual_item_id = str(updated.get("id", ""))
  updated[candidate.field] = [candidate.path] if candidate.field == "manual_pages" else candidate.path
  if not updated.get("local_media_validation") is Dictionary: updated.local_media_validation = {}
  updated.local_media_validation[candidate.field] = {"tag":candidate.tag, "sha256":candidate.job.sha256, "status":"decoded_current", "identity_status":"unverified", "source":"explicit_local_processing"}
  output.bindings.append({"config":config.duplicate(true), "game_id":str(updated.get("id", "")),
   "tag":candidate.tag, "relative_path":candidate.job.relative_path, "sha256":candidate.job.sha256,
   "catalog_identity":identity_signature(updated)})
  output.applied += 1
  if not candidate.path in output.changed_paths: output.changed_paths.append(candidate.path)
 if _cancelled(cancelled):
  return {"items":items.duplicate(true), "applied":0, "issues":[{"status":"cancelled"}], "validated_files":output.validated_files, "bytes_revalidated":output.bytes_revalidated, "changed_paths":[], "status":"cancelled"}
 return output

static func _cancelled(callback: Callable) -> bool:
 return callback.is_valid() and bool(callback.call())

static func _validate_image(path: String, expected_hash: String) -> Dictionary:
 if expected_hash.length() != 64 or not expected_hash.is_valid_hex_number(false): return {"status":"missing_current_hash"}
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
 return {"status":"valid", "bytes":length, "width":image.get_width(), "height":image.get_height()}
