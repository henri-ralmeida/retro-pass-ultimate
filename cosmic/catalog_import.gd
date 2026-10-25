extends RefCounted
## Metadata-only adapter for an explicitly supplied inventory JSON. Reads only
## that JSON, never ROMs, archives, images, manuals, directories or the network.
## Source "present" means present in the inventory's source environment, NOT
## present on this computer. No local existence/identity/edition is verified.
## Default scope is Master System. Mark III requires its own explicit call.
## Without local_root, runtime media fields stay empty; safe source paths are
## retained in media_metadata. A root only resolves paths, it never reads them.

const MAX_JSON_BYTES := 32 * 1024 * 1024
const MAX_RECORDS := 100000
const SOURCE_GROUPS := ["Master System", "Mark III"]
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const MEDIA_TAGS := ["image", "thumbnail", "video", "marquee", "wheel", "fanart", "boxart", "boxback", "cartridge", "titleshot", "screenshot", "manual", "map", "bezel", "cover_front", "cover_back", "cover_spine", "boxspine", "spine", "cover_edge", "cartridge_label", "cartridge_top"]
# Only explicit surface tags can populate those surfaces. A cartridge photo,
# screenshot, thumbnail or generic image is not a cropped label or a spine.
const SURFACE_TAGS := {
 "cover_front": ["boxart", "cover_front"],
 "cover_back": ["boxback", "cover_back"],
 "cover_spine": ["cover_spine", "boxspine", "spine"],
 "cover_edge": ["cover_edge"],
 "cartridge_label": ["cartridge_label"],
 "cartridge_top": ["cartridge_top"],
 "wheel": ["wheel", "marquee"],
 "manual_pdf": ["manual"]
}

static func read_catalog(path: String, source_group: String = "Master System", local_root: String = "") -> Dictionary:
 if path.get_extension().to_lower() != "json" or not _is_local_path(path):
  return _error("invalid_json_path")
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null: return _error("json_unreadable")
 if file.get_length() > MAX_JSON_BYTES:
  file.close()
  return _error("json_too_large")
 var text := file.get_as_text()
 file.close()
 var parser := JSON.new()
 if parser.parse(text) != OK: return _error("invalid_json")
 return adapt(parser.data, source_group, local_root)

static func adapt(document: Variant, source_group: String = "Master System", local_root: String = "") -> Dictionary:
 if not source_group in SOURCE_GROUPS: return _error("unsupported_source_group")
 if not local_root.is_empty() and not _is_local_root(local_root): return _error("invalid_local_root")
 if not document is Dictionary or not document.get("games") is Array: return _error("invalid_catalog_schema")
 var records: Array = document.games
 if records.size() > MAX_RECORDS: return _error("too_many_records")
 var root := local_root.replace("\\", "/").trim_suffix("/")
 if local_root == "/": root = "/"
 if local_root in ["res://", "user://"]: root = local_root
 if root.length() == 2 and root.ends_with(":"): root += "/"
 var result := {
  "ok": true, "error": "", "schema_version": 1, "source_group": source_group,
  "metadata_only": true, "local_presence_verified": false,
  "media_bytes_provided": false, "media_root_configured": not root.is_empty(),
  "items": [], "counts": _empty_counts()
 }
 result.counts.input_records = records.size()
 var seen := {}
 for raw in records:
  if not raw is Dictionary:
   result.counts.invalid_entries += 1
   continue
  if raw.get("source_group", "") != source_group:
   result.counts.filtered_groups += 1
   continue
  var relative := safe_relative_path(raw.get("path", ""))
  if relative.is_empty():
   result.counts.invalid_entries += 1
   continue
  var system := "master_system" if source_group == "Master System" else "mark_iii"
  var id := (system + ":" + relative).sha256_text()
  if seen.has(id):
   result.counts.duplicate_entries += 1
   continue
  seen[id] = true
  var status := _inventory_status(raw.get("file_status", "unknown"))
  var title := _text(raw.get("name", raw.get("title", ""))).strip_edges()
  if title.is_empty(): title = relative.get_file().get_basename()
  var item := {
   "id": id, "title": title, "relative_path": relative, "system": system,
   "source_group": source_group, "source_game_id": _text(raw.get("game_id", "")),
   "file_status": status, "available_for_random": status == "present",
   "eligible_for_random": status == "present", "availability_basis": "source_inventory",
   "local_file_status": "not_checked", "local_presence_verified": false,
   "metadata_source": "inventory_json", "identity_status": "unverified",
   "region_hint": _text(raw.get("region_hint", "")),
   "language_hint": _text(raw.get("language_hint", "")),
   "filename_variant_hints": _string_array(raw.get("filename_variant_hints", [])),
   "subtitle": source_group.to_upper() + " · INVENTÁRIO",
   "description": "Metadados do inventário de origem. Arquivo e mídia não verificados neste computador.",
   "accent": "9dd8f2", "media_metadata": {}, "media_mapping": {},
   "media_bytes_provided": false, "media_root_configured": not root.is_empty(),
   "manual_pages": []
  }
  var source_media: Variant = raw.get("media", {})
  if source_media is Dictionary:
   for tag in MEDIA_TAGS:
    if not source_media.has(tag): continue
    var descriptor := _media_descriptor(source_media[tag])
    if descriptor.status == "invalid_path": result.counts.invalid_media_paths += 1
    item.media_metadata[tag] = descriptor
  for field in SURFACE_TAGS:
   item[field] = ""
   var chosen := _choose_media(item.media_metadata, SURFACE_TAGS[field], field == "manual_pdf")
   if chosen.is_empty(): continue
   item.media_mapping[field] = chosen
   if not root.is_empty(): item[field] = root.path_join(str(item.media_metadata[chosen].relative_path))
  result.items.append(item)
  result.counts.items += 1
  result.counts[status] += 1
  if item.available_for_random: result.counts.available_for_random += 1
 return result

static func safe_relative_path(raw: Variant) -> String:
 if not raw is String: return ""
 var path: String = raw.replace("\\", "/")
 # Colons also reject URI schemes, Windows drives and NTFS alternate streams.
 if path.is_empty() or path.begins_with("/") or path.begins_with("~") or ":" in path or _has_controls(path): return ""
 var parts := path.split("/", true)
 var clean: Array[String] = []
 for part in parts:
  if part == ".." or part.is_empty(): return ""
  if part == ".": continue
  # Windows trims trailing spaces/dots; reject aliases and forbidden metachars.
  if part.ends_with(".") or part.ends_with(" ") or part.strip_edges().is_empty(): return ""
  for forbidden in ["<", ">", "\"", "|", "?", "*"]:
   if forbidden in part: return ""
  var base := part.get_slice(".", 0).to_upper()
  if base in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]: return ""
  clean.append(part)
 return "/".join(clean)

static func _media_descriptor(raw: Variant) -> Dictionary:
 var data: Dictionary = raw if raw is Dictionary else {}
 var original: Variant = data.get("path", raw if raw is String else "")
 var relative := safe_relative_path(original)
 var status := _inventory_status(data.get("status", "unknown"))
 if original == null or original == "": status = "not_associated"
 elif relative.is_empty(): status = "invalid_path"
 return {
  "relative_path": relative, "status": status,
  "extension": relative.get_extension().to_lower(),
  "local_status": "not_checked", "bytes_provided": false
 }

static func _choose_media(metadata: Dictionary, tags: Array, is_pdf: bool) -> String:
 for tag in tags:
  if not metadata.has(tag): continue
  var descriptor: Dictionary = metadata[tag]
  if descriptor.status != "present" or str(descriptor.relative_path).is_empty(): continue
  var extension := str(descriptor.extension)
  if (is_pdf and extension == "pdf") or (not is_pdf and extension in IMAGE_EXTENSIONS): return tag
 return ""

static func _inventory_status(raw: Variant) -> String:
 return str(raw) if raw is String and raw in ["present", "missing"] else "unknown"

static func _text(raw: Variant) -> String:
 return raw if raw is String else ""

static func _string_array(raw: Variant) -> Array[String]:
 var output: Array[String] = []
 if raw is Array:
  for value in raw:
   if value is String: output.append(value)
 return output

static func _has_controls(path: String) -> bool:
 for character in path.length():
  if path.unicode_at(character) < 32 or path.unicode_at(character) == 127: return true
 return false

static func _is_local_path(path: String) -> bool:
 var normalized := path.replace("\\", "/")
 if normalized.is_empty() or normalized.begins_with("//") or _has_controls(normalized): return false
 if normalized.begins_with("res://") or normalized.begins_with("user://"):
  return not safe_relative_path(normalized.substr(normalized.find("://") + 3)).is_empty()
 if ":" in normalized:
  if normalized.length() < 4 or normalized.substr(1, 2) != ":/" or not normalized.substr(0, 1).to_lower() in "abcdefghijklmnopqrstuvwxyz": return false
  return not safe_relative_path(normalized.substr(3)).is_empty()
 return not safe_relative_path(normalized.trim_prefix("/")).is_empty()

static func _is_local_root(path: String) -> bool:
 var normalized := path.replace("\\", "/")
 if normalized in ["/", "res://", "user://"]: return true
 if not normalized.is_absolute_path(): return false
 # Drive root requires its own case; all other paths use the same strict parser.
 if normalized.length() == 3 and normalized.substr(1, 2) == ":/":
  return normalized.substr(0, 1).to_lower() in "abcdefghijklmnopqrstuvwxyz"
 return _is_local_path(normalized.trim_suffix("/"))

static func _empty_counts() -> Dictionary:
 return {"input_records": 0, "items": 0, "present": 0, "missing": 0, "unknown": 0, "available_for_random": 0, "filtered_groups": 0, "invalid_entries": 0, "duplicate_entries": 0, "invalid_media_paths": 0}

static func _error(code: String) -> Dictionary:
 return {"ok": false, "error": code, "items": [], "counts": _empty_counts()}
