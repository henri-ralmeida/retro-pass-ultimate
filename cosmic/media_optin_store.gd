extends RefCounted
## Private consent/plan metadata only; never probes or opens media sources.
## Main-thread host is sole writer. Loading is an offer, NOT consent to resume.
const Config = preload("res://cosmic/media_optin_config.gd")
const Queue = preload("res://cosmic/media_local_queue.gd")
const MAX_BYTES := 16 * 1024 * 1024
var path := "user://retropass_local_media_settings.json"

func save_decision(decision: Dictionary) -> Error:
 if not _valid_decision(decision): return ERR_INVALID_PARAMETER
 var previous := load_state()
 return _save({"version":1, "decision":decision.duplicate(true), "plan":previous.get("plan", {})})

func save_plan(plan: Dictionary) -> Error:
 if not _valid_plan(plan): return ERR_INVALID_PARAMETER
 return _save({"version":1, "decision":plan.config.duplicate(true), "plan":plan.duplicate(true)})

func load_state() -> Dictionary:
 if not _valid_path(): return {}
 var state := _read(path)
 if state.is_empty(): state = _read(path + ".bak")
 return state

func _valid_path() -> bool:
 return path.begins_with("user://") and path.length() > 7 and not ".." in path and not path.ends_with("/")

func _valid_decision(value: Dictionary) -> bool:
 if value.get("version") != 1 or value.get("ok") != true: return false
 var kind: Variant = value.get("decision")
 if kind in ["skipped", "later"]: return value == Config.defer_setup(kind == "skipped")
 if kind != "configured" or not value.get("categories") is Array: return false
 if not value.get("system") is String or not value.get("root") is String: return false
 return value == Config.choose(value.system, value.root, value.categories)

func _valid_plan(value: Dictionary) -> bool:
 if not value.get("config") is Dictionary or not _valid_decision(value.config): return false
 if value.config.decision != "configured" or value.get("operation") != "local_processing": return false
 if not value.get("files") is Array or not value.get("issues") is Array: return false
 # Structural validation is pure: queue construction/_valid_plan perform no I/O.
 if not Queue.new()._valid_plan(value): return false
 var games := {}
 for job in value.files:
  if not job.get("relative_path") is String: return false
  for link in job.links:
   if not link.get("game_id") is String or link.get("identity_status") != "unverified": return false
   games[link.game_id] = true
 for issue in value.issues:
  if not issue.get("game_id") is String or not issue.get("status") is String: return false
  games[issue.game_id] = true
 return value.get("files_total") == value.files.size() and value.get("games_total") == games.size()

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
 if state.get("version") != 1 or not state.get("decision") is Dictionary or not state.get("plan") is Dictionary: return {}
 if not _valid_decision(state.decision): return {}
 if not state.plan.is_empty() and not _valid_plan(state.plan): return {}
 return state

func _save(state: Dictionary) -> Error:
 if not _valid_path(): return ERR_INVALID_PARAMETER
 var bytes := JSON.stringify(state).to_utf8_buffer()
 if bytes.size() > MAX_BYTES: return ERR_OUT_OF_MEMORY
 var temporary := path + ".tmp"
 var backup := path + ".bak"
 var file := FileAccess.open(temporary, FileAccess.WRITE)
 if file == null: return FileAccess.get_open_error()
 file.store_buffer(bytes)
 file.flush()
 var error := file.get_error()
 file.close()
 if error != OK: return error
 # Do not replace the last valid backup with a malformed primary.
 if not _read(path).is_empty():
  if FileAccess.file_exists(backup):
   error = DirAccess.remove_absolute(backup)
   if error != OK: return error
  error = DirAccess.rename_absolute(path, backup)
  if error != OK: return error
 elif FileAccess.file_exists(path):
  error = DirAccess.remove_absolute(path)
  if error != OK: return error
 return DirAccess.rename_absolute(temporary, path)

func _restore_integer_fields(value: Variant) -> Variant:
 # Godot JSON parses integral counts/version as floats. Restore their canonical
 # representation so the queue's exact JSON plan signature survives restart.
 if value is float and is_finite(value) and value == floor(value) and abs(value) < 9007199254740992.0:
  return int(value)
 if value is Array:
  var result: Array = []
  for entry in value: result.append(_restore_integer_fields(entry))
  return result
 if value is Dictionary:
  var result: Dictionary = {}
  for key in value: result[key] = _restore_integer_fields(value[key])
  return result
 return value
