extends RefCounted
## Bounded local reads only. Does not decode, copy, modify or publish media.
## One owner per journal. Call tick() from a future worker, NOT the rendering UI.
const Config = preload("res://cosmic/media_optin_config.gd")
const Planner = preload("res://cosmic/media_optin_plan.gd")
const CHUNK_BYTES := 256 * 1024
const MAX_JOURNAL_BYTES := 16 * 1024 * 1024
var state: Dictionary = {}
var journal := ""
var last_error := ""
var _file: FileAccess
var _hash: HashingContext
var _active := -1

func start(plan: Dictionary, journal_path: String) -> Error:
 _close()
 if not _valid_plan(plan) or not journal_path.begins_with("user://") or ".." in journal_path:
  return ERR_INVALID_PARAMETER
 journal = journal_path
 state = {"version": 1, "signature": JSON.stringify(plan).sha256_text(),
  "config": plan.config.duplicate(true), "operation": "local_processing", "status": "pending", "files": [], "issues": plan.get("issues", []).duplicate(true)}
 for entry in plan.files:
  var job: Dictionary = entry.duplicate(true)
  job.merge({"status":"pending", "bytes_read":0, "bytes_total":0, "sha256":"", "previous_sha256":"", "source_changed":false, "error":""})
  state.files.append(job)
 if not _preflight_capacity(): return ERR_OUT_OF_MEMORY
 return _save()

func restore(plan: Dictionary, journal_path: String) -> Error:
 _close()
 if not _valid_plan(plan) or not journal_path.begins_with("user://") or ".." in journal_path: return ERR_INVALID_PARAMETER
 var previous := _read(journal_path)
 if previous.is_empty(): previous = _read(journal_path + ".bak")
 if previous.get("version", 0) != 1 or previous.get("signature", "") != JSON.stringify(plan).sha256_text():
  return ERR_INVALID_DATA
 # Reconstruct paths/links from caller's exact approved plan, never saved paths.
 var jobs: Array = []
 for entry in plan.files:
  var job: Dictionary = entry.duplicate(true)
  job.merge({"status":"pending", "bytes_read":0, "bytes_total":0, "sha256":"", "previous_sha256":"", "source_changed":false, "error":""})
  for saved in previous.get("files", []):
   if saved is Dictionary and saved.get("id", "") == job.id:
    job.previous_sha256 = str(saved.get("sha256", "")) if saved.get("status", "") == "done" else str(saved.get("previous_sha256", ""))
    break
  jobs.append(job)
 journal = journal_path
 state = {"version":1, "signature":JSON.stringify(plan).sha256_text(), "config":plan.config.duplicate(true),
  "operation":"local_processing", "status":"pending", "files":jobs, "issues":plan.get("issues", []).duplicate(true)}
 # Every selected file is revalidated. Historical hashes never imply current success.
 if not _preflight_capacity(): return ERR_OUT_OF_MEMORY
 return _save()

func cancel() -> Error:
 _close()
 for job in state.get("files", []):
  if job.status in ["pending", "running"]: job.status = "cancelled"
 state.status = "cancelled"
 return _save()

func tick() -> Dictionary:
 if state.is_empty() or state.status in ["cancelled", "done", "completed_with_errors", "storage_error"]:
  return progress()
 if _active < 0:
  for i in range(state.files.size()):
   if state.files[i].status == "pending":
    _active = i
    break
  if _active < 0:
   state.status = "completed_with_errors" if progress().files_error > 0 or progress().associations_omitted > 0 else "done"
   _save()
   return progress()
  var job: Dictionary = state.files[_active]
  var path: String = str(state.config.root).path_join(job.relative_path)
  if not _safe_path(path):
   _fail("unsafe_or_linked_path")
   return progress()
  _file = FileAccess.open(path, FileAccess.READ)
  if _file == null:
   _fail("unreadable_or_missing")
   return progress()
  job.bytes_total = _file.get_length()
  job.bytes_read = 0
  job.status = "running"
  state.status = "running"
  _hash = HashingContext.new()
  _hash.start(HashingContext.HASH_SHA256)
 var current: Dictionary = state.files[_active]
 var remaining: int = current.bytes_total - current.bytes_read
 var chunk := _file.get_buffer(mini(CHUNK_BYTES, remaining))
 if chunk.size() != mini(CHUNK_BYTES, remaining):
  _fail("read_interrupted_or_source_changed")
  return progress()
 _hash.update(chunk)
 current.bytes_read += chunk.size()
 if current.bytes_read == current.bytes_total:
  if _file.get_length() != current.bytes_total:
   _fail("source_changed")
   return progress()
  current.sha256 = _hash.finish().hex_encode()
  current.source_changed = not str(current.previous_sha256).is_empty() and current.previous_sha256 != current.sha256
  current.status = "done"
  _close()
 _save()
 return progress()

func progress() -> Dictionary:
 var p := {"operation":"local_processing", "status":state.get("status", "idle"),
  "files_total":0, "files_done":0, "files_error":0, "bytes_read":0,
  "bytes_total_discovered":0, "games_total":0, "games_done":0, "associations_omitted":0, "files_changed":0, "issues":state.get("issues", []).duplicate(true), "file_failures":[]}
 var games := {}
 for job in state.get("files", []):
  p.files_total += 1
  p.files_done += int(job.status == "done")
  p.files_error += int(job.status == "error")
  if job.status == "error": p.file_failures.append({"file_id":job.id, "error":job.error, "links":job.links.duplicate(true)})
  p.files_changed += int(job.get("source_changed", false))
  p.bytes_read += job.bytes_read
  p.bytes_total_discovered += job.bytes_total
  for link in job.links:
   games[link.game_id] = games.get(link.game_id, true) and job.status == "done"
 for issue in state.get("issues", []):
  games[issue.game_id] = false
  p.associations_omitted += 1
 p.games_total = games.size()
 for done in games.values(): p.games_done += int(done)
 return p

func _fail(reason: String) -> void:
 state.files[_active].status = "error"
 state.files[_active].error = reason
 _close()
 _save()

func _close() -> void:
 if _file != null: _file.close()
 _file = null
 _hash = null
 _active = -1

func _safe_path(path: String) -> bool:
 if not Config.valid_root(str(state.config.root)): return false
 # Inspect only selected path's ancestors, never enumerate a collection.
 var current := path
 while current != current.get_base_dir():
  var parent := current.get_base_dir()
  var directory := DirAccess.open(parent)
  if directory == null or directory.is_link(current.get_file()): return false
  current = parent
 return true

func _valid_plan(plan: Dictionary) -> bool:
 if not plan.get("ok", false) or not plan.get("config") is Dictionary or not plan.get("files") is Array: return false
 if not plan.get("issues", []) is Array: return false
 for issue in plan.get("issues", []):
  if not issue is Dictionary or str(issue.get("game_id", "")).is_empty(): return false
 var config: Dictionary = plan.config
 if config.get("decision", "") in ["skipped", "later"]: return plan.files.is_empty()
 if config.get("decision", "") != "configured" or not config.get("categories") is Array: return false
 if not Config.choose(str(config.get("system", "")), str(config.get("root", "")), config.categories).ok: return false
 var seen := {}
 for job in plan.files:
  if not job is Dictionary or not job.get("links") is Array or job.links.is_empty(): return false
  var relative := Planner.Inventory.safe_relative_path(job.get("relative_path", ""))
  if relative.is_empty() or relative != job.relative_path: return false
  var id := str(config.root).path_join(relative).sha256_text()
  if job.get("id", "") != id or seen.has(id): return false
  seen[id] = true
  for link in job.links:
   if not link is Dictionary or str(link.get("game_id", "")).is_empty(): return false
   var tag := str(link.get("tag", ""))
   if not Planner.TAG_CATEGORY.has(tag) or not Planner.TAG_CATEGORY[tag] in config.categories: return false
   var extension := relative.get_extension().to_lower()
   if not extension in Planner.Inventory.IMAGE_EXTENSIONS and not (tag == "manual" and extension == "pdf"): return false
 return true

func _read(path: String) -> Dictionary:
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null: return {}
 if file.get_length() > MAX_JOURNAL_BYTES:
  file.close()
  return {}
 var parser := JSON.new()
 var error := parser.parse(file.get_as_text())
 file.close()
 return parser.data if error == OK and parser.data is Dictionary else {}

func _save() -> Error:
 if journal.is_empty(): return ERR_INVALID_PARAMETER
 var payload := JSON.stringify(state).to_utf8_buffer()
 if payload.size() > MAX_JOURNAL_BYTES:
  var error := _storage_failure(ERR_OUT_OF_MEMORY)
  last_error = "journal_too_large"
  return error
 var temp := journal + ".tmp"
 var backup := journal + ".bak"
 var file := FileAccess.open(temp, FileAccess.WRITE)
 if file == null: return _storage_failure(FileAccess.get_open_error())
 file.store_buffer(payload)
 file.flush()
 var error := file.get_error()
 file.close()
 if error != OK: return _storage_failure(error)
 if FileAccess.file_exists(journal):
  if FileAccess.file_exists(backup):
   error = DirAccess.remove_absolute(backup)
   if error != OK: return _storage_failure(error)
  error = DirAccess.rename_absolute(journal, backup)
  if error != OK: return _storage_failure(error)
 error = DirAccess.rename_absolute(temp, journal)
 if error != OK: return _storage_failure(error)
 return OK

func _preflight_capacity() -> bool:
 # Reserve 512 bytes/job for two 64-char hashes, 64-bit byte counters, errors,
 # terminal status and future boolean values, before any source file is opened.
 # These are the ONLY fields changed by the worker; links/issues stay immutable.
 var reserved_size: int = JSON.stringify(state).to_utf8_buffer().size() + state.files.size() * 512 + 128
 if reserved_size <= MAX_JOURNAL_BYTES: return true
 _storage_failure(ERR_OUT_OF_MEMORY)
 last_error = "journal_capacity_exceeded"
 return false

func _storage_failure(error: Error) -> Error:
 _close()
 state.status = "storage_error"
 last_error = "journal_write_failed"
 return error
