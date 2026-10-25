extends RefCounted
## Gameplay-only immutable JSON journal; never touches frontend/device identity.
## config_path is the optional legacy snapshot and naming base, NOT overwritten.
## Atomic visibility comes from same-directory rename to a fresh nonce filename.
## A directory lock serializes cooperating writers; a stale lock fails closed.
## Never reclaim a lock automatically: verify no writer is alive before recovery.
## Restart selects the highest valid committed generation; temporary files are
## never promoted. Keep eight valid generations, preserving invalid evidence.
## No guarantee of power-loss/fsync durability. Run one store on the main thread.
const Profile = preload("res://cosmic/sms_mapping_profile.gd")
const DEFAULT_PATH := "user://input/gameplay/master_system/profiles.json"
const SCHEMA_VERSION := 1
const MAX_DOCUMENT_BYTES := 65536
const RETAIN_VALID_GENERATIONS := 8
const MAX_GENERATION := 999999999999999

var config_path: String
var last_error: Error = OK
var notice := ""
var _profiles: Array = []
var _shared_keys: Array = []
var _loaded := false
var _edit_baselines: Array = []
var _has_valid_file := false
var _source_signature := ""
var _highest_generation := 0
var _temporary_serial := 0
var _owns_writer_lock := false

func _init(path: String = DEFAULT_PATH) -> void:
 config_path = path
 _profiles = [Profile.new(0).snapshot(), Profile.new(1).snapshot()]

func load_profiles() -> Dictionary:
 var result: Dictionary = _refresh_profiles()
 if result.error == OK:
  # Explicit reload/reopen establishes the version the editor is based on.
  _edit_baselines = _profiles.duplicate(true)
 return result

func _refresh_profiles() -> Dictionary:
 var source: Dictionary = _read_committed_state()
 if source.error != OK:
  _set_status(source.error, "Não foi possível ler uma geração válida dos perfis. O último estado válido foi preservado.")
  return _result()
 if source.envelope.is_empty() and _has_valid_file:
  _set_status(ERR_FILE_NOT_FOUND, "Os perfis salvos desapareceram; o último estado válido foi preservado.")
  return _result()
 if not source.envelope.is_empty():
  _profiles = source.envelope.profiles.duplicate(true)
  _shared_keys = source.envelope.shared_keys.duplicate(true)
  _has_valid_file = true
 _loaded = true
 _source_signature = source.signature
 _highest_generation = source.highest_generation
 var message := "Perfis do Master System carregados." if _has_valid_file else "Perfis padrão em uso; nenhum arquivo foi criado."
 if source.rejected > 0:
  message = "Uma geração válida foi recuperada; %d arquivo(s) inválido(s) foram ignorados e preservados." % source.rejected
 _set_status(OK, message)
 return _result()

## Only NEW, unapproved collisions. Exact grants survive unrelated edits.
## Empty output is not a load-success signal: inspect last_error.
func keyboard_conflicts(snapshot: Dictionary) -> Array:
 var candidate = Profile.new()
 if not candidate.load_snapshot(snapshot):
  _set_status(ERR_INVALID_DATA, "Perfil inválido; nenhuma atribuição foi alterada.")
  return []
 if not _loaded and load_profiles().error != OK:
  return []
 var proposed: Array = _profiles.duplicate(true)
 proposed[candidate.port] = candidate.snapshot()
 return _unapproved_conflicts(proposed, candidate.port)

func _unapproved_conflicts(proposed: Array, port: int) -> Array:
 var result: Array = []
 for pair in _all_shared_keys(proposed):
  if _contains_pair(_shared_keys, pair):
   continue
  result.append({
   "action": pair.p1_action if port == 0 else pair.p2_action,
   "other_action": pair.p2_action if port == 0 else pair.p1_action,
   "other_port": 1 - port,
   "code": int(pair.code),
  })
 return result

## allow_shared_keys is a ONE-SAVE explicit user choice, not a permanent bypass.
## approved_conflicts must be the exact list displayed before that user choice.
## The caller must not promote its live profile until this method returns OK.
func save_profile(snapshot: Dictionary, allow_shared_keys := false, approved_conflicts: Array = []) -> Error:
 var candidate = Profile.new()
 if not candidate.load_snapshot(snapshot):
  return _set_status(ERR_INVALID_DATA, "Perfil inválido; nada foi gravado.")
 var loaded: Dictionary = _refresh_profiles()
 if loaded.error != OK:
  return loaded.error
 if _edit_baselines.is_empty():
  _edit_baselines = _profiles.duplicate(true)
 elif _edit_baselines[candidate.port] != _profiles[candidate.port]:
  return _set_status(ERR_BUSY, "Este jogador foi alterado por outro gravador. Reabra os perfis para revisar e reconciliar o rascunho.")
 var proposed: Array = _profiles.duplicate(true)
 proposed[candidate.port] = candidate.snapshot()
 var proposed_shared: Array = _all_shared_keys(proposed)
 var pending: Array = _unapproved_conflicts(proposed, candidate.port)
 if not pending.is_empty() and not allow_shared_keys:
  return _set_status(ERR_ALREADY_EXISTS, "Tecla usada pelo outro jogador. Escolha compartilhar explicitamente ou volte para alterar.")
 if allow_shared_keys and not _same_conflicts(pending, approved_conflicts):
  return _set_status(ERR_BUSY, "Os conflitos não correspondem à escolha exibida. Revise as teclas e confirme novamente.")
 var envelope: Dictionary = _make_envelope(proposed, proposed_shared)
 if _validate_envelope(envelope).is_empty():
  return _set_status(ERR_INVALID_DATA, "Os perfis não passaram pela validação; nada foi gravado.")
 var directory_error: Error = _ensure_parent()
 if directory_error != OK:
  return _set_status(directory_error, "Não foi possível criar a pasta dos perfis; o rascunho foi preservado.")
 var lock_error: Error = _make_writer_lock()
 if lock_error != OK:
  if lock_error == ERR_ALREADY_EXISTS:
   return _set_status(ERR_BUSY, "Há outro gravador ou um bloqueio de gravação pendente. Nenhum perfil foi alterado.")
  return _set_status(lock_error, "Não foi possível obter exclusividade de gravação. Nenhum perfil foi alterado.")
 _owns_writer_lock = true
 var result: Error = _save_locked(envelope)
 if result == OK:
  _edit_baselines[candidate.port] = _profiles[candidate.port].duplicate(true)
 var unlock_error: Error = _remove_writer_lock()
 _owns_writer_lock = unlock_error != OK
 if unlock_error != OK:
  notice += " O bloqueio de gravação não pôde ser liberado; verifique-o antes de salvar novamente."
 return result

func _same_conflicts(expected: Array, supplied: Array) -> bool:
 if expected.size() != supplied.size():
  return false
 var seen: Array[String] = []
 for value in supplied:
  if not value is Dictionary or value.size() != 4 or not value.has_all(["action", "other_action", "other_port", "code"]):
   return false
  if not value.action is String or not value.other_action is String or not Profile.is_integer(value.other_port) or not Profile.is_integer(value.code):
   return false
  var normalized := {"action": value.action, "other_action": value.other_action, "other_port": int(value.other_port), "code": int(value.code)}
  if normalized not in expected:
   return false
  var token := "%s:%s:%d:%d" % [value.action, value.other_action, int(value.other_port), int(value.code)]
  if token in seen:
   return false
  seen.append(token)
 return true

func _save_locked(envelope: Dictionary) -> Error:
 # Recheck after locking: never commit a proposal prepared against stale players.
 var source_error: Error = _check_source_unchanged()
 if source_error != OK:
  return _set_status(source_error, "Os perfis mudaram durante a preparação. Releia e confirme as alterações novamente.")
 if _highest_generation >= MAX_GENERATION:
  return _set_status(ERR_OUT_OF_MEMORY, "O limite de gerações foi atingido; nenhum perfil foi alterado.")
 var committed_path := _new_generation_path(_highest_generation + 1)
 var temporary_path := _new_temporary_path()
 var contents := JSON.stringify(envelope, " ", true) + "\n"
 var write_error: Error = _write_file(temporary_path, contents)
 if write_error != OK:
  return _temporary_failure(temporary_path, write_error, "Falha ao gravar o temporário; as gerações anteriores foram preservadas.")
 var temporary: Dictionary = _read_file(temporary_path)
 if temporary.error != OK:
  return _temporary_failure(temporary_path, temporary.error, "Falha ao reler o temporário; as gerações anteriores foram preservadas.")
 var verified: Dictionary = _parse_document(temporary.text)
 if verified.error != OK or verified.envelope != envelope:
  return _temporary_failure(temporary_path, ERR_FILE_CORRUPT, "O temporário não passou pelo roundtrip; as gerações anteriores foram preservadas.")
 source_error = _check_source_unchanged()
 if source_error != OK:
  return _temporary_failure(temporary_path, source_error, "Os arquivos mudaram durante a gravação. Releia e tente novamente.")
 var commit_error: Error = _commit_new_file(temporary_path, committed_path)
 if commit_error != OK:
  return _temporary_failure(temporary_path, commit_error, "A gravação da nova geração falhou. As gerações anteriores e o rascunho foram preservados.")
 # Once committed, never return a failure that would leave the UI's live state old.
 _profiles = envelope.profiles.duplicate(true)
 _shared_keys = envelope.shared_keys.duplicate(true)
 _has_valid_file = true
 _loaded = true
 _highest_generation += 1
 _set_status(OK, "Perfis do Master System salvos.")
 if _prune_old_generations() != OK:
  notice += " A limpeza das gerações antigas ficou pendente; o perfil foi salvo."
 return OK

func _result() -> Dictionary:
 return {"profiles": _profiles.duplicate(true), "error": last_error, "notice": notice}

func _set_status(code: Error, message: String) -> Error:
 last_error = code
 notice = message
 return code

func _make_envelope(profiles: Array, shared: Array) -> Dictionary:
 return {"schema_version": SCHEMA_VERSION, "system_id": Profile.SYSTEM_ID, "profiles": profiles.duplicate(true), "shared_keys": shared.duplicate(true)}

func _parse_document(contents: String) -> Dictionary:
 if contents.to_utf8_buffer().size() > MAX_DOCUMENT_BYTES:
  return {"error": ERR_FILE_CORRUPT, "envelope": {}}
 var parser := JSON.new()
 if parser.parse(contents) != OK:
  return {"error": ERR_PARSE_ERROR, "envelope": {}}
 var envelope: Dictionary = _validate_envelope(parser.data)
 return {"error": OK if not envelope.is_empty() else ERR_INVALID_DATA, "envelope": envelope}

func _validate_envelope(data: Variant) -> Dictionary:
 if not data is Dictionary or data.size() != 4:
  return {}
 for field in ["schema_version", "system_id", "profiles", "shared_keys"]:
  if not data.has(field):
   return {}
 if not Profile.is_integer(data.schema_version) or int(data.schema_version) != SCHEMA_VERSION:
  return {}
 if data.system_id != Profile.SYSTEM_ID or not data.profiles is Array or data.profiles.size() != 2 or not data.shared_keys is Array:
  return {}
 var canonical: Array = [{}, {}]
 for value in data.profiles:
  var profile = Profile.new()
  if not profile.load_snapshot(value) or not canonical[profile.port].is_empty():
   return {}
  canonical[profile.port] = profile.snapshot()
 if canonical[0].is_empty() or canonical[1].is_empty():
  return {}
 var actual: Array = _all_shared_keys(canonical)
 if data.shared_keys.size() != actual.size():
  return {}
 var seen: Array[String] = []
 for pair in data.shared_keys:
  if not pair is Dictionary or pair.size() != 3:
   return {}
  if not pair.has_all(["p1_action", "p2_action", "code"]):
   return {}
  if not pair.p1_action is String or not pair.p2_action is String or not Profile.is_integer(pair.code):
   return {}
  if not _contains_pair(actual, pair):
   return {}
  var token := _pair_token(pair)
  if token in seen:
   return {}
  seen.append(token)
 return _make_envelope(canonical, actual)

func _all_shared_keys(profiles: Array) -> Array:
 var result: Array = []
 # Action order is deterministic, independent of dictionary/JSON field order.
 for p1_action in Profile.new(0).actions():
  var code: int = profiles[0].bindings.keyboard[p1_action].code
  for p2_action in Profile.new(1).actions():
   if code == int(profiles[1].bindings.keyboard[p2_action].code):
    result.append({"p1_action": p1_action, "p2_action": p2_action, "code": code})
 return result

func _pair_token(pair: Dictionary) -> String:
 return "%s:%s:%d" % [pair.p1_action, pair.p2_action, int(pair.code)]

func _contains_pair(pairs: Array, wanted: Dictionary) -> bool:
 for pair in pairs:
  if _pair_token(pair) == _pair_token(wanted):
   return true
 return false

func _generation_prefix() -> String:
 return config_path.get_file().get_basename() + ".generation-"

func _generation_number(path: String) -> int:
 var filename := path.get_file()
 if not filename.begins_with(_generation_prefix()) or not filename.ends_with(".json"):
  return -1
 var parts := filename.trim_prefix(_generation_prefix()).trim_suffix(".json").split("-")
 if parts.size() != 2 or parts[0].length() != 15 or parts[1].length() != 32:
  return -1
 for character in parts[0]:
  if character not in "0123456789":
   return -1
 for character in parts[1]:
  if character not in "0123456789abcdef":
   return -1
 var number := int(parts[0])
 return number if number > 0 and number <= MAX_GENERATION else -1

func _read_committed_state() -> Dictionary:
 var listed: Dictionary = _list_generation_files()
 if listed.error != OK:
  return {"error": listed.error}
 var paths: Array = listed.files.duplicate()
 paths.sort()
 # Include legacy in the signature, but a valid committed generation takes priority.
 paths.push_front(config_path)
 var signature_parts: Array = []
 var selected: Dictionary = {}
 var highest_valid := -1
 var highest := 0
 var seen_generations: Dictionary = {}
 var rejected := 0
 var found := false
 for path in paths:
  var generation: int = 0 if path == config_path else _generation_number(path)
  if generation < 0:
   # Ignore unrelated/unrecognized filenames, not arbitrary user documents.
   continue
  if generation > 0:
   if seen_generations.has(generation):
    return {"error": ERR_BUSY} # Two writers emitted the same sequence; do not guess.
   seen_generations[generation] = true
   highest = maxi(highest, generation)
  var source: Dictionary = _read_file(path)
  if path == config_path and source.error == ERR_FILE_NOT_FOUND and not source.exists:
   signature_parts.append([path, "missing"])
   continue
  found = true
  if source.error == ERR_FILE_CORRUPT:
   rejected += 1
   signature_parts.append([path, "oversized-or-corrupt"])
   continue
  if source.error != OK:
   return {"error": source.error}
  signature_parts.append([path, str(source.text).sha256_text()])
  var parsed: Dictionary = _parse_document(source.text)
  if parsed.error != OK:
   rejected += 1
   continue
  if generation > highest_valid:
   selected = parsed.envelope
   highest_valid = generation
 if selected.is_empty() and found:
  return {"error": ERR_FILE_CORRUPT}
 return {"error": OK, "envelope": selected, "signature": JSON.stringify(signature_parts), "highest_generation": highest, "rejected": rejected}

func _check_source_unchanged() -> Error:
 var current: Dictionary = _read_committed_state()
 if current.error != OK:
  return current.error
 return OK if current.signature == _source_signature else ERR_BUSY

func _new_generation_path(generation: int) -> String:
 var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
 return config_path.get_base_dir().path_join("%s%015d-%s.json" % [_generation_prefix(), generation, nonce])

func _new_temporary_path() -> String:
 _temporary_serial += 1
 return "%s.tmp.%d.%d.%d.%d" % [config_path, OS.get_process_id(), get_instance_id(), Time.get_ticks_usec(), _temporary_serial]

func _temporary_failure(path: String, code: Error, message: String) -> Error:
 if path.begins_with(config_path + ".tmp.") and _remove_file(path) != OK:
  message += " O temporário não pôde ser removido."
 return _set_status(code, message)

func _prune_old_generations() -> Error:
 # Best effort only AFTER commit. Keep newest eight known-valid snapshots;
 # never touch legacy, unknown schemas/names, corrupt evidence or writer locks.
 var listed: Dictionary = _list_generation_files()
 if listed.error != OK:
  return listed.error
 var valid: Array = []
 var cleanup_error: Error = OK
 for path in listed.files:
  var generation: int = _generation_number(path)
  if generation < 1:
   continue
  var source: Dictionary = _read_file(path)
  if source.error != OK:
   cleanup_error = source.error
   continue
  if _parse_document(source.text).error == OK:
   valid.append(path)
 valid.sort()
 for index in maxi(0, valid.size() - RETAIN_VALID_GENERATIONS):
  var removal_error: Error = _remove_file(valid[index])
  if removal_error != OK:
   cleanup_error = removal_error
 return cleanup_error

## Small overridable IO boundary for deterministic fault-injection tests.
func _list_generation_files() -> Dictionary:
 var directory_path := config_path.get_base_dir()
 if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory_path)):
  return {"error": OK, "files": []}
 var directory := DirAccess.open(directory_path)
 if directory == null:
  return {"error": DirAccess.get_open_error(), "files": []}
 var list_error: Error = directory.list_dir_begin()
 if list_error != OK:
  return {"error": list_error, "files": []}
 var files: Array = []
 var filename := directory.get_next()
 while not filename.is_empty():
  if not directory.current_is_dir() and filename.begins_with(_generation_prefix()) and filename.ends_with(".json"):
   files.append(directory_path.path_join(filename))
  filename = directory.get_next()
 directory.list_dir_end()
 return {"error": OK, "files": files}

func _read_file(path: String) -> Dictionary:
 var absolute := ProjectSettings.globalize_path(path)
 if DirAccess.dir_exists_absolute(absolute):
  return {"error": ERR_FILE_CANT_OPEN, "exists": true, "text": ""}
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null:
  var open_error: Error = FileAccess.get_open_error()
  return {"error": open_error, "exists": FileAccess.file_exists(path), "text": ""}
 if file.get_length() > MAX_DOCUMENT_BYTES:
  file.close()
  return {"error": ERR_FILE_CORRUPT, "exists": true, "text": ""}
 var contents := file.get_as_text()
 var read_error: Error = file.get_error()
 file.close()
 if read_error == ERR_FILE_EOF:
  read_error = OK
 return {"error": read_error, "exists": true, "text": contents}

func _ensure_parent() -> Error:
 return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(config_path.get_base_dir()))

func _make_writer_lock() -> Error:
 # Nonrecursive mkdir must FAIL if the lock exists. Never steal/reclaim a stale lock.
 return DirAccess.make_dir_absolute(ProjectSettings.globalize_path(config_path + ".writer-lock"))

func _remove_writer_lock() -> Error:
 if not _owns_writer_lock:
  return ERR_UNAUTHORIZED
 return DirAccess.remove_absolute(ProjectSettings.globalize_path(config_path + ".writer-lock"))

func _write_file(path: String, contents: String) -> Error:
 var file := FileAccess.open(path, FileAccess.WRITE)
 if file == null:
  return FileAccess.get_open_error()
 file.store_string(contents)
 file.flush()
 var write_error: Error = file.get_error()
 file.close()
 return write_error

func _commit_new_file(source: String, destination: String) -> Error:
 if not _owns_writer_lock or source.get_base_dir() != destination.get_base_dir() or _generation_number(destination) < 1:
  return ERR_INVALID_PARAMETER
 var existing: Dictionary = _read_file(destination)
 if existing.error != ERR_FILE_NOT_FOUND or existing.exists:
  return ERR_ALREADY_EXISTS if existing.error == OK else existing.error
 # In Godot 4.6 Windows rename deletes an EXISTING destination before MoveFileW.
 # Never overwrite: the exclusive writer lock + random immutable name avoid it.
 # Another writer ignoring this protocol is detected by signatures/duplicate seq.
 # Same directory avoids Unix's cross-device copy/remove fallback.
 return _rename_file(source, destination)

func _rename_file(source: String, destination: String) -> Error:
 return DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination))

func _remove_file(path: String) -> Error:
 if not FileAccess.file_exists(path):
  return OK
 return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
