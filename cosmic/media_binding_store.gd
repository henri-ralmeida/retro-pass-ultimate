extends "res://cosmic/media_optin_store.gd"
## Private overlay: exact validated references only, never a source catalog.
## No directory scan, media read, or inferred match occurs in this store.
const Association = preload("res://cosmic/media_result_association.gd")
const Inventory = preload("res://cosmic/catalog_import.gd")
const MAX_BINDINGS := 4096
const RECORD_KEYS := ["catalog_identity", "config", "game_id", "relative_path", "sha256", "tag"]

func _init() -> void:
 path = "user://retropass_media_bindings.json"

func save_bindings(bindings: Array, remove_keys: Array = []) -> Error:
 if not _valid_bindings(bindings): return ERR_INVALID_PARAMETER
 var merged: Dictionary = {}
 for record in load_state().get("bindings", []):
  if not _key(record) in remove_keys: merged[_key(record)] = record
 for record in bindings: merged[_key(record)] = record.duplicate(true)
 var records := merged.values()
 if not _valid_bindings(records): return ERR_INVALID_PARAMETER
 return _save({"version":1, "bindings":records})

func _key(record: Dictionary) -> String:
 # Serialize components, never concatenate ambiguous IDs with delimiters.
 return JSON.stringify([record.config.system, record.game_id, Association.SURFACES[record.tag]])

func _valid_bindings(bindings: Array) -> bool:
 if bindings.size() > MAX_BINDINGS: return false
 var keys := {}
 var path_hashes := {}
 for record in bindings:
  if not record is Dictionary: return false
  var fields: Array = record.keys()
  fields.sort()
  if fields != RECORD_KEYS: return false
  if not record.config is Dictionary or not _valid_decision(record.config): return false
  if record.config.decision != "configured": return false
  for field in ["game_id", "relative_path", "sha256", "catalog_identity", "tag"]:
   if not record[field] is String: return false
  if record.game_id.is_empty() or record.game_id.length() > 4096: return false
  if not Association.SURFACES.has(record.tag): return false
  if not Association.category_for(record.tag) in record.config.categories: return false
  if record.relative_path.is_empty() or record.relative_path != Inventory.safe_relative_path(record.relative_path): return false
  if not record.relative_path.get_extension().to_lower() in Inventory.IMAGE_EXTENSIONS: return false
  for hash_field in ["sha256", "catalog_identity"]:
   if record[hash_field].length() != 64 or not record[hash_field].is_valid_hex_number(false): return false
  var source_path: String = str(record.config.root).path_join(record.relative_path)
  if path_hashes.has(source_path) and path_hashes[source_path] != record.sha256: return false
  path_hashes[source_path] = record.sha256
  var key := _key(record)
  if keys.has(key): return false
  keys[key] = true
 return true

func _read(file_path: String) -> Dictionary:
 var file := FileAccess.open(file_path, FileAccess.READ)
 if file == null: return {}
 if file.get_length() > MAX_BYTES:
  file.close()
  return {}
 var parser := JSON.new()
 var error := parser.parse(file.get_as_text())
 file.close()
 if error != OK or not parser.data is Dictionary: return {}
 var state: Dictionary = _restore_integer_fields(parser.data)
 if state.size() != 2 or state.get("version") != 1 or not state.get("bindings") is Array: return {}
 return state if _valid_bindings(state.bindings) else {}

static func restore(bindings: Array, items: Array, cancelled: Callable = Callable()) -> Dictionary:
 # Called on a worker. Group by exact config so aliases are checked together.
 var validator = load("res://cosmic/media_binding_store.gd").new()
 if not validator._valid_bindings(bindings):
  return {"items":items.duplicate(true), "applied":0, "issues":[{"status":"invalid_overlay"}], "changed_paths":[], "status":"done", "bindings":[]}
 var groups := {}
 for record in bindings:
  var key := JSON.stringify(record.config)
  if not groups.has(key): groups[key] = {"config":record.config, "status":"done", "files":[]}
  groups[key].files.append({"id":str(record.config.root).path_join(record.relative_path).sha256_text(),
   "relative_path":record.relative_path, "status":"done", "sha256":record.sha256,
   "links":[{"game_id":record.game_id,"tag":record.tag,"identity_status":"unverified","catalog_identity":record.catalog_identity}]})
 var output := {"items":items.duplicate(true), "applied":0, "issues":[], "changed_paths":[], "status":"done", "bindings":[], "bytes_revalidated":0}
 for group in groups.values():
  var result := Association.build(group, output.items, cancelled)
  if result.status == "cancelled":
   return {"items":items.duplicate(true), "applied":0, "issues":[{"status":"cancelled"}], "changed_paths":[], "status":"cancelled", "bindings":[]}
  output.items = result.items
  output.applied += result.applied
  output.issues.append_array(result.issues)
  output.changed_paths.append_array(result.changed_paths)
  output.bindings.append_array(result.bindings)
  output.bytes_revalidated += result.bytes_revalidated
 return output
