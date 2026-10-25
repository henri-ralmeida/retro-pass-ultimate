extends RefCounted
## Read-only, explicitly invoked Master System folder inventory. Never opens ROMs
## or archives, follows links, downloads art, or infers a release from a filename.
const CATALOG_PATH := "user://collection_catalog.json"
const EXTENSIONS := ["sms", "zip", "7z"]
const MEDIA_FIELDS := {
 "boxart": "cover_front", "cover": "cover_front",
 "cover_front": "cover_front", "boxfront": "cover_front",
 "cover_back": "cover_back", "boxback": "cover_back", "back": "cover_back",
 "cover_spine": "cover_spine", "boxspine": "cover_spine", "spine": "cover_spine"
}

func scan_folder(folder: String, options: Dictionary = {}) -> Dictionary:
 var root := ProjectSettings.globalize_path(folder).simplify_path().trim_suffix("/")
 var result := {"status":"ok", "root":root, "items":[], "warnings":[], "visited_files":0, "visited_entries":0, "provider_status":"not_configured", "schema_version":1}
 if root.is_empty() or not root.is_absolute_path() or not DirAccess.dir_exists_absolute(root) or _has_link(root):
  result.status = "error"
  result.warnings.append("Choose an existing, non-symlink collection folder.")
  return result
 var limit := clampi(int(options.get("max_files", 10000)), 1, 100000)
 var depth_limit := clampi(int(options.get("max_depth", 12)), 0, 64)
 var pending: Array[Dictionary] = [{"path":root, "depth":0}]
 var manifests: Array[String] = []
 var by_path := {}
 while not pending.is_empty():
  if _cancelled(options):
   result.status = "cancelled"
   break
  var current: Dictionary = pending.pop_back()
  var dir := DirAccess.open(current.path)
  if dir == null:
   result.warnings.append("Cannot read folder: " + str(current.path))
   continue
  if dir.list_dir_begin() != OK:
   result.warnings.append("Cannot list folder: " + str(current.path))
   continue
  var name := dir.get_next()
  while not name.is_empty():
   if _cancelled(options):
    result.status = "cancelled"
    break
   result.visited_entries += 1
   if result.visited_entries > limit:
    result.status = "limited"
    result.warnings.append("Entry limit reached; select a narrower folder.")
    break
   var path: String = str(current.path).path_join(name)
   if not dir.is_link(name):
    if dir.current_is_dir():
     if int(current.depth) < depth_limit:
      pending.append({"path":path, "depth":int(current.depth)+1})
     else:
      result.status = "limited"
      result.warnings.append("Depth limit skipped folder: " + path)
    else:
     result.visited_files += 1
     if name.to_lower() == "gamelist.xml": manifests.append(path)
     if name.get_extension().to_lower() in EXTENSIONS:
      var file := FileAccess.open(path, FileAccess.READ)
      if file != null:
       var relative := path.trim_prefix(root + "/")
       var item := {"id":("master_system:"+relative).sha256_text(), "title":name.get_basename(), "path":path, "relative_path":relative, "size_bytes":file.get_length(), "system":"master_system", "subtitle":"MASTER SYSTEM · ACERVO LOCAL", "description":"Arquivo local. Identidade e edição não verificadas online.", "cover_front":"", "cover_back":"", "cover_spine":"", "metadata_source":"filename", "identity_status":"unverified", "container":name.get_extension().to_lower()}
       file.close()
       result.items.append(item)
       by_path[path] = item
   var progress: Callable = options.get("progress", Callable())
   if progress.is_valid() and result.visited_entries % 64 == 0: progress.call(result.visited_files, result.items.size())
   name = dir.get_next()
  dir.list_dir_end()
  if result.status != "ok": break
 if result.status == "ok":
  manifests.sort()
  for manifest in manifests:
   if _cancelled(options):
    result.status = "cancelled"
    break
   _read_gamelist(manifest, root, by_path, result.warnings, options)
 result.items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.relative_path) < str(b.relative_path))
 return result

func _cancelled(options: Dictionary) -> bool:
 var callback: Callable = options.get("cancelled", Callable())
 return callback.is_valid() and bool(callback.call())

func _has_link(path: String) -> bool:
 var cursor := path.simplify_path().trim_suffix("/")
 while not cursor.is_empty() and cursor != cursor.get_base_dir():
  var parent := DirAccess.open(cursor.get_base_dir())
  if parent == null or parent.is_link(cursor.get_file()): return true
  cursor = cursor.get_base_dir()
 return false

func _local_file(value: String, base: String, root: String) -> String:
 if value.is_empty(): return ""
 var path := value if value.is_absolute_path() else base.path_join(value)
 path = path.simplify_path()
 if not path.begins_with(root + "/") or _has_link(path) or not FileAccess.file_exists(path): return ""
 return path

func _read_gamelist(path: String, root: String, by_path: Dictionary, warnings: Array, options: Dictionary) -> void:
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null: return
 if file.get_length() > 8 * 1024 * 1024:
  warnings.append("Skipped oversized gamelist: " + path)
  file.close()
  return
 var xml := file.get_as_text()
 file.close()
 # Never interpret DTDs/entities or treat a generic screenshot as a box face.
 if "<!DOCTYPE" in xml.to_upper() or "<!ENTITY" in xml.to_upper():
  warnings.append("Ignored unsupported XML declarations: " + path)
  return
 var parser := XMLParser.new()
 if parser.open_buffer(xml.to_utf8_buffer()) != OK:
  warnings.append("Cannot parse gamelist: " + path)
  return
 var game := {}
 var active := false
 var field := ""
 var staged: Array[Dictionary] = []
 var elements: Array[String] = []
 var malformed := false
 var status := parser.read()
 while status == OK:
  if _cancelled(options): return
  match parser.get_node_type():
   XMLParser.NODE_ELEMENT:
    var tag := parser.get_node_name().to_lower()
    if not parser.is_empty(): elements.append(tag)
    if tag == "game":
     game = {}
     active = true
    elif active:
     field = tag
     game[field] = ""
    if parser.is_empty(): field = ""
   XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
    if active and not field.is_empty(): game[field] = str(game.get(field, "")) + parser.get_node_data()
   XMLParser.NODE_ELEMENT_END:
    if elements.is_empty() or elements.pop_back() != parser.get_node_name().to_lower():
     malformed = true
     break
    if parser.get_node_name().to_lower() == "game" and active:
     staged.append(game)
     active = false
    field = ""
  status = parser.read()
 if status != ERR_FILE_EOF or active or malformed or not elements.is_empty():
  warnings.append("Ignored malformed gamelist: " + path)
  return
 for entry in staged:
  var rom := _local_file(str(entry.get("path", "")).strip_edges(), path.get_base_dir(), root)
  if not by_path.has(rom): continue
  var item: Dictionary = by_path[rom]
  var title := str(entry.get("name", "")).strip_edges()
  if not title.is_empty(): item.title = title
  if not str(entry.get("desc", "")).strip_edges().is_empty(): item.description = str(entry.desc).strip_edges()
  item.metadata_source = "gamelist.xml"
  item["media_image"] = _local_file(str(entry.get("image", "")).strip_edges(), path.get_base_dir(), root)
  for tag in MEDIA_FIELDS:
   var media := _local_file(str(entry.get(tag, "")).strip_edges(), path.get_base_dir(), root)
   if not media.is_empty() and media.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]:
    item[MEDIA_FIELDS[tag]] = media

func save_catalog(result: Dictionary) -> Error:
 ## Host calls ONLY after an explicit scan. Incomplete/cancelled results never replace catalog.
 if result.get("status", "error") != "ok": return ERR_INVALID_DATA
 var temporary_path := CATALOG_PATH + ".tmp"
 var file := FileAccess.open(temporary_path, FileAccess.WRITE)
 if file == null: return FileAccess.get_open_error()
 file.store_string(JSON.stringify(result, "  "))
 file.flush()
 var error := file.get_error()
 file.close()
 if error != OK:
  DirAccess.remove_absolute(temporary_path)
  return error
 return DirAccess.rename_absolute(temporary_path, CATALOG_PATH)
