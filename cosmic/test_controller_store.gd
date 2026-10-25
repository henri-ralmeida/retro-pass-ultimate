extends SceneTree
## Synthetic IO only. Running this suite never creates real user profile files.
const Profile = preload("res://cosmic/sms_mapping_profile.gd")
const Store = preload("res://cosmic/controller_profile_store.gd")
var assertions := 0
var failures: Array[String] = []

class MemoryStore:
 extends "res://cosmic/controller_profile_store.gd"
 var files: Dictionary = {}
 var removed: Array[String] = []
 var writes := 0
 var renames := 0
 var writer_locked := false
 var unlock_error: Error = OK
 var list_error: Error = OK
 var overwritten_destination := false
 var read_error: Error = OK
 var temp_read_error: Error = OK
 var write_error: Error = OK
 var directory_error: Error = OK
 var rename_error: Error = OK
 var cleanup_error: Error = OK
 var broken_temporary := false
 var different_valid_temporary := false
 var source_change_during_roundtrip := ""

 func _read_file(path: String) -> Dictionary:
  var temporary := path.begins_with(config_path + ".tmp.")
  var failure: Error = temp_read_error if temporary else read_error
  if failure != OK:
   return {"error": failure, "exists": files.has(path), "text": ""}
  if not files.has(path):
   return {"error": ERR_FILE_NOT_FOUND, "exists": false, "text": ""}
  if temporary and not source_change_during_roundtrip.is_empty():
   var candidates: Array = _list_generation_files().files
   candidates.sort()
   files[candidates[-1] if not candidates.is_empty() else config_path] = source_change_during_roundtrip
  if temporary and broken_temporary:
   return {"error": OK, "exists": true, "text": "{truncated"}
  if temporary and different_valid_temporary:
   var parsed: Dictionary = JSON.parse_string(files[path])
   parsed.profiles[0].family_override = "generic"
   return {"error": OK, "exists": true, "text": JSON.stringify(parsed)}
  return {"error": OK, "exists": true, "text": files[path]}

 func _ensure_parent() -> Error:
  return directory_error

 func _write_file(path: String, contents: String) -> Error:
  writes += 1
  files[path] = contents if write_error == OK else "{partial"
  return write_error

 func _list_generation_files() -> Dictionary:
  var result: Array = []
  for path in files:
   if str(path).get_file().begins_with(_generation_prefix()) and str(path).ends_with(".json"):
    result.append(path)
  return {"error": list_error, "files": result}

 func _make_writer_lock() -> Error:
  if writer_locked:
   return ERR_ALREADY_EXISTS
  writer_locked = true
  return OK

 func _remove_writer_lock() -> Error:
  if unlock_error != OK:
   return unlock_error
  writer_locked = false
  return OK

 func _rename_file(source: String, destination: String) -> Error:
  renames += 1
  if rename_error != OK:
   return rename_error
  overwritten_destination = overwritten_destination or files.has(destination)
  files[destination] = files[source]
  files.erase(source)
  return OK

 func _remove_file(path: String) -> Error:
  removed.append(path)
  if cleanup_error != OK:
   return cleanup_error
  files.erase(path)
  return OK

func check(value: bool, description: String) -> void:
 assertions += 1
 if not value:
  failures.append(description)
  push_error(description)

func changed_profile(port := 0, action := "button_1", code: int = KEY_C) -> Dictionary:
 var profile = Profile.new(port)
 check(profile.rebind(action, "keyboard", {"kind": "key", "code": code}), "Fixture binding is valid")
 return profile.snapshot()

func latest_path(store) -> String:
 var paths: Array = []
 for path in store._list_generation_files().files:
  if store._generation_number(path) > 0:
   paths.append(path)
 paths.sort()
 return paths[-1] if not paths.is_empty() else store.config_path

func persisted(store) -> Dictionary:
 return store._validate_envelope(JSON.parse_string(store.files[latest_path(store)]))

func seed_store():
 var store = MemoryStore.new()
 check(store.save_profile(changed_profile()) == OK, "Fixture creates a valid saved document")
 return store

func test_defaults_and_roundtrip() -> void:
 var store = MemoryStore.new()
 check(store.config_path == Store.DEFAULT_PATH, "Gameplay path is separate from frontend controls")
 var loaded: Dictionary = store.load_profiles()
 check(loaded.error == OK and loaded.profiles.size() == 2, "Missing file gives two valid defaults")
 check(loaded.profiles[0].player_port == 0 and loaded.profiles[1].player_port == 1, "Profiles are returned in port order")
 check(store.files.is_empty() and store.writes == 0, "Reading defaults creates no files")
 loaded.profiles[0].bindings.keyboard.button_1.code = KEY_Q
 check(store.load_profiles().profiles[0].bindings.keyboard.button_1.code == KEY_Z, "Returned snapshots cannot mutate cached profiles")
 var snapshot: Dictionary = changed_profile()
 check(store.save_profile(snapshot) == OK, "First save succeeds on supported backend")
 check(store.files.size() == 1 and store.renames == 1, "Commit leaves exactly the destination, not a temporary")
 var document: Dictionary = persisted(store)
 check(document.size() == 4 and document.shared_keys.is_empty(), "Envelope contains only version, system, profiles and precise sharing grants")
 check(store.load_profiles().profiles[0] == snapshot, "JSON roundtrip preserves canonical P1 snapshot")
 check(store.load_profiles().profiles[1] == Profile.new(1).snapshot(), "Saving P1 preserves P2")
 var restarted = MemoryStore.new()
 restarted.files = store.files.duplicate(true)
 check(restarted.load_profiles().profiles[0] == snapshot, "Fresh store recovers saved profiles")
 check(restarted.save_profile(changed_profile(1, "button_1", KEY_V)) == OK, "P2 can save separately")
 check(restarted.load_profiles().profiles[0] == snapshot, "Saving P2 preserves P1")
 check(not store.files.has("user://controls.cfg"), "Frontend settings are never a store target")

func test_precise_sharing_grants() -> void:
 var store = MemoryStore.new()
 var shared: Dictionary = changed_profile(0, "button_1", KEY_G)
 var conflicts: Array = store.keyboard_conflicts(shared)
 check(conflicts == [{"action": "button_1", "other_action": "button_1", "other_port": 1, "code": KEY_G}], "Cross-player collision identifies both actions and the physical key")
 check(store.save_profile(shared) == ERR_ALREADY_EXISTS, "New sharing requires explicit choice")
 check(store.files.is_empty() and store.writes == 0, "Rejected sharing does not touch disk")
 check(store.save_profile(shared, true) == ERR_BUSY, "A bare boolean cannot authorize unseen conflicts")
 check(store.save_profile(shared, true, conflicts) == OK, "Explicit one-save sharing accepts precisely the displayed conflicts")
 check(store.keyboard_conflicts(shared).is_empty(), "Previously authorized exact pair is not asked again")
 check(persisted(store).shared_keys == [{"p1_action": "button_1", "p2_action": "button_1", "code": KEY_G}], "Authorization records an exact action/action/key tuple")
 shared.family_override = "playstation"
 check(store.save_profile(shared) == OK, "Unrelated presentation changes preserve prior authorization")
 var restarted = MemoryStore.new()
 restarted.files = store.files.duplicate(true)
 restarted.load_profiles()
 check(restarted.keyboard_conflicts(shared).is_empty(), "Exact authorization survives restart")
 var p2: Dictionary = Profile.new(1).snapshot()
 p2.family_override = "xbox"
 check(restarted.save_profile(p2) == OK, "P2 unrelated edits also preserve P1/P2 authorization")
 var changed_pair = Profile.new()
 check(changed_pair.load_snapshot(shared), "Shared fixture validates")
 check(changed_pair.rebind("button_2", "keyboard", {"kind": "key", "code": KEY_G}, true), "Local swap moves shared key to a different action")
 check(restarted.save_profile(changed_pair.snapshot()) == ERR_ALREADY_EXISTS, "Same key on a different action is a new sharing decision")
 check(restarted.save_profile(changed_profile()) == OK, "Removing sharing needs no new confirmation")
 check(persisted(restarted).shared_keys.is_empty(), "Obsolete authorization is pruned")
 check(restarted.save_profile(shared) == ERR_ALREADY_EXISTS, "Reintroduced sharing cannot reuse a revoked stale grant")
 var p2_shared: Dictionary = changed_profile(1, "button_2", KEY_C)
 check(restarted.keyboard_conflicts(p2_shared) == [{"action": "button_2", "other_action": "button_1", "other_port": 0, "code": KEY_C}], "P2 conflict labels are reversed correctly")

func test_io_failures_and_retry() -> void:
 for fault in ["directory_error", "write_error", "temp_read_error", "rename_error"]:
  var store = seed_store()
  var before: String = store.files[latest_path(store)]
  store.set(fault, ERR_CANT_CREATE)
  check(store.save_profile(changed_profile(0, "button_1", KEY_V)) == ERR_CANT_CREATE, "Injected %s is reported" % fault)
  check(store.files[latest_path(store)] == before, "%s preserves exact previous destination bytes" % fault)
  check(store.last_error == ERR_CANT_CREATE and not store.notice.is_empty(), "Failure supplies status and user-facing notice")
  check(store.config_path not in store.removed, "Cleanup never removes the destination")
  check(store.files.size() == 1, "Failed save cleans only its temporary")
  store.set(fault, OK)
  check(store.save_profile(changed_profile(0, "button_1", KEY_V)) == OK, "Same draft can retry after %s clears" % fault)
 for fault in ["broken_temporary", "different_valid_temporary"]:
  var store = seed_store()
  var before: String = store.files[latest_path(store)]
  store.set(fault, true)
  check(store.save_profile(changed_profile(0, "button_1", KEY_V)) == ERR_FILE_CORRUPT, "Roundtrip rejects %s" % fault)
  check(store.files[latest_path(store)] == before and store.files.size() == 1, "Bad roundtrip preserves destination and clears temporary")
 var read_failed = seed_store()
 var saved: String = read_failed.files[latest_path(read_failed)]
 read_failed.read_error = ERR_FILE_CANT_READ
 var failed_load: Dictionary = read_failed.load_profiles()
 check(failed_load.error == ERR_FILE_CANT_READ and failed_load.profiles[0].bindings.keyboard.button_1.code == KEY_C, "Unreadable file preserves last valid cached profile")
 check(read_failed.save_profile(changed_profile()) == ERR_FILE_CANT_READ and read_failed.files[latest_path(read_failed)] == saved, "Unreadable source cannot be overwritten")
 read_failed.read_error = OK
 check(read_failed.load_profiles().error == OK, "Reading can retry after access returns")
 var cleanup_failed = seed_store()
 cleanup_failed.rename_error = ERR_CANT_CREATE
 cleanup_failed.cleanup_error = ERR_FILE_CANT_WRITE
 check(cleanup_failed.save_profile(changed_profile()) == ERR_CANT_CREATE, "Cleanup failure cannot disguise the original error")
 check(cleanup_failed.notice.contains("temporário não pôde ser removido"), "Orphan temporary is disclosed honestly")

func test_corruption_and_validation() -> void:
 var store = seed_store()
 var good: String = store.files[latest_path(store)]
 var variants: Array = ["{", "null", "[]", " ".repeat(Store.MAX_DOCUMENT_BYTES + 1)]
 for field in ["schema_version", "system_id", "profiles", "shared_keys"]:
  var missing: Dictionary = JSON.parse_string(good)
  missing.erase(field)
  variants.append(JSON.stringify(missing))
 var bad: Dictionary = JSON.parse_string(good)
 bad.schema_version = 99
 variants.append(JSON.stringify(bad))
 bad = JSON.parse_string(good)
 bad.hardware_guid = "not-allowed"
 variants.append(JSON.stringify(bad))
 bad = JSON.parse_string(good)
 bad.profiles[1] = bad.profiles[0].duplicate(true)
 variants.append(JSON.stringify(bad))
 bad = JSON.parse_string(good)
 bad.profiles[0].bindings.gamepad.button_1.device = 42
 variants.append(JSON.stringify(bad))
 bad = JSON.parse_string(good)
 bad.profiles[0].bindings.keyboard.button_1.code = KEY_G
 variants.append(JSON.stringify(bad))
 bad = JSON.parse_string(good)
 bad.shared_keys = [{"p1_action": "button_1", "p2_action": "button_1", "code": KEY_G}]
 variants.append(JSON.stringify(bad))
 for invalid in variants:
  store.files[latest_path(store)] = invalid
  var result: Dictionary = store.load_profiles()
  check(result.error != OK and result.profiles[0].bindings.keyboard.button_1.code == KEY_C, "Corrupt load rejects the whole envelope and preserves valid cache")
  check(store.save_profile(changed_profile()) != OK and store.files[latest_path(store)] == invalid, "Corrupt source is never auto-overwritten with defaults")
  store.files[latest_path(store)] = good
  check(store.load_profiles().error == OK, "Restored valid source clears corruption error")
 store.files.erase(latest_path(store))
 check(store.load_profiles().error == ERR_FILE_NOT_FOUND, "Disappearing previously valid file is reported, not silently reset")
 check(store.load_profiles().profiles[0].bindings.keyboard.button_1.code == KEY_C, "Disappearing file retains cached bindings")
 var fresh = MemoryStore.new()
 var invalid_snapshot: Dictionary = Profile.new().snapshot()
 invalid_snapshot.player_port = 2
 check(fresh.save_profile(invalid_snapshot) == ERR_INVALID_DATA and fresh.writes == 0, "Invalid caller snapshot never writes")

func test_locks_and_concurrent_change() -> void:
 var store = seed_store()
 var previous_path: String = latest_path(store)
 var before: String = store.files[previous_path]
 var concurrent: Dictionary = JSON.parse_string(before)
 concurrent.profiles[1].family_override = "generic"
 var concurrent_text := JSON.stringify(concurrent)
 store.source_change_during_roundtrip = concurrent_text
 check(store.save_profile(changed_profile(0, "button_1", KEY_V)) == ERR_BUSY, "Source change detected before commit")
 check(store.files[previous_path] == concurrent_text, "Concurrent contents are not overwritten")
 check(not store.writer_locked, "Failed transaction releases its own writer lock")
 store.source_change_during_roundtrip = ""
 check(store.save_profile(changed_profile(0, "button_1", KEY_V)) == OK, "Retry refreshes the other player from latest source")
 check(store.load_profiles().profiles[1].family_override == "generic", "Retry preserves concurrent P2 update")
 check(store.files[previous_path] == concurrent_text and not store.overwritten_destination, "Immutable commits never overwrite an existing destination")
 var blocked = MemoryStore.new()
 blocked.writer_locked = true
 check(blocked.save_profile(Profile.new().snapshot()) == ERR_BUSY and blocked.writes == 0, "Another writer or stale lock fails closed before writing")
 check(blocked.writer_locked, "Store never removes another writer's lock")
 var unlock_failed = MemoryStore.new()
 unlock_failed.unlock_error = ERR_FILE_CANT_WRITE
 check(unlock_failed.save_profile(Profile.new().snapshot()) == OK, "Successful commit remains successful if unlock cleanup fails")
 check(unlock_failed.notice.contains("bloqueio") and unlock_failed.writer_locked, "Unlock failure is disclosed without claiming saved profile failed")
 check(unlock_failed.save_profile(Profile.new().snapshot()) == ERR_BUSY, "Unresolved lock prevents a subsequent writer")
 var duplicate = seed_store()
 var path: String = latest_path(duplicate)
 var duplicate_path := path.get_base_dir().path_join("profiles.generation-000000000000001-" + "f".repeat(32) + ".json")
 if duplicate_path == path:
  duplicate_path = path.get_base_dir().path_join("profiles.generation-000000000000001-" + "e".repeat(32) + ".json")
 duplicate.files[duplicate_path] = duplicate.files[path]
 check(duplicate.load_profiles().error == ERR_BUSY, "Duplicate generation sequence is an ambiguous concurrent commit, not an arbitrary last-writer choice")
 check(duplicate.save_profile(changed_profile()) == ERR_BUSY, "Ambiguous generation blocks saving")

func test_journal_recovery_and_retention() -> void:
 var store = MemoryStore.new()
 # The legacy file is readable, but is never overwritten by a new generation.
 var legacy: Dictionary = store._make_envelope([Profile.new(0).snapshot(), Profile.new(1).snapshot()], [])
 var legacy_text := JSON.stringify(legacy)
 store.files[store.config_path] = legacy_text
 check(store.load_profiles().error == OK, "Existing canonical legacy envelope loads")
 for index in Store.RETAIN_VALID_GENERATIONS + 5:
  check(store.save_profile(changed_profile(0, "button_1", KEY_C if index % 2 == 0 else KEY_V)) == OK, "New immutable generation commits")
 var paths: Array = store._list_generation_files().files
 paths.sort()
 check(paths.size() == Store.RETAIN_VALID_GENERATIONS, "Journal retention bounds valid generations at eight")
 check(store.files[store.config_path] == legacy_text, "Legacy source survives saves and retention unchanged")
 check(store.config_path not in store.removed and paths[-1] not in store.removed and paths[-2] not in store.removed, "Retention never removes legacy, newest or previous committed generation")
 check(not store.overwritten_destination, "Every rename target was a fresh filename, including after pruning")
 var newest: String = paths[-1]
 var previous: Dictionary = store._validate_envelope(JSON.parse_string(store.files[paths[-2]]))
 store.files[newest] = "{broken"
 var recovered: Dictionary = store.load_profiles()
 check(recovered.error == OK and recovered.profiles == previous.profiles, "Corrupt newest generation falls back to highest valid predecessor")
 check(recovered.notice.contains("recuperada") and store.files[newest] == "{broken", "Recovery warning preserves corrupt evidence")
 check(store.save_profile(changed_profile()) == OK, "Recovery can commit a new sequence without replacing corrupt evidence")
 check(store._generation_number(latest_path(store)) > store._generation_number(newest), "Recovery allocates above even the invalid highest generation")
 var orphan: String = store.config_path + ".tmp.orphan"
 var unrelated: String = store.config_path.get_base_dir().path_join("profiles.generation-not-a-store-snapshot.json")
 store.files[orphan] = "do not adopt an uncommitted temporary"
 store.files[unrelated] = "user document"
 check(store.load_profiles().error == OK, "Uncommitted temporaries and unrelated names are not treated as committed snapshots")
 check(store.save_profile(changed_profile()) == OK and store.files.has(orphan) and store.files.has(unrelated), "Retention ignores unknown filenames and other writes' temporary files")
 var prune_failed = MemoryStore.new()
 for index in Store.RETAIN_VALID_GENERATIONS:
  check(prune_failed.save_profile(Profile.new().snapshot()) == OK, "Retention fixture fills journal")
 prune_failed.cleanup_error = ERR_FILE_CANT_WRITE
 check(prune_failed.save_profile(changed_profile()) == OK, "Best-effort retention cannot turn successful commit into failure")
 check(prune_failed.notice.contains("limpeza") and prune_failed.load_profiles().profiles[0].bindings.keyboard.button_1.code == KEY_C, "Cleanup limitation is disclosed while latest valid generation remains active")
 var restarted = MemoryStore.new()
 restarted.files = store.files.duplicate(true)
 check(restarted.load_profiles().error == OK and restarted.load_profiles().profiles[0].bindings.keyboard.button_1.code == KEY_C, "Fresh process selects highest valid committed generation")

func test_stale_drafts_and_sharing_consent() -> void:
 var owner = seed_store()
 var writer = MemoryStore.new()
 writer.files = owner.files # Separate writer, same simulated filesystem.
 check(writer.save_profile(changed_profile(0, "button_1", KEY_V)) == OK, "Second writer commits a new P1 version")
 var stale_draft: Dictionary = changed_profile(0, "button_1", KEY_Q)
 var saved: String = owner.files[latest_path(owner)]
 check(owner.save_profile(stale_draft) == ERR_BUSY, "Stale editor cannot silently overwrite the same player")
 check(owner.save_profile(stale_draft) == ERR_BUSY and owner.files[latest_path(owner)] == saved, "Retry alone does not bless a stale draft")
 owner.load_profiles()
 check(owner.save_profile(stale_draft) == OK, "Explicit reload permits the caller to reconcile and save")
 var sharing_owner = seed_store()
 var proposal: Dictionary = changed_profile(0, "button_1", KEY_G)
 var shown: Array = sharing_owner.keyboard_conflicts(proposal)
 var sharing_writer = MemoryStore.new()
 sharing_writer.files = sharing_owner.files
 var changed_p2 = Profile.new(1)
 check(changed_p2.rebind("button_2", "keyboard", {"kind": "key", "code": KEY_G}, true), "Fixture moves P2 shared key to another action")
 check(sharing_writer.save_profile(changed_p2.snapshot()) == OK, "Other player changes after consent dialog opens")
 saved = sharing_owner.files[latest_path(sharing_owner)]
 check(sharing_owner.save_profile(proposal, true, shown) == ERR_BUSY, "Approval for a displayed pair cannot authorize a different concurrent pair")
 check(sharing_owner.files[latest_path(sharing_owner)] == saved, "Stale consent does not commit a new generation")
 var revised: Array = sharing_owner.keyboard_conflicts(proposal)
 check(revised[0].other_action == "button_2", "Refreshed collision can be displayed for a new explicit decision")
 check(sharing_owner.save_profile(proposal, true, revised) == OK, "New exact consent accepts the revised pair")

func _initialize() -> void:
 run.call_deferred()

func run() -> void:
 test_defaults_and_roundtrip()
 test_precise_sharing_grants()
 test_io_failures_and_retry()
 test_corruption_and_validation()
 test_locks_and_concurrent_change()
 test_journal_recovery_and_retention()
 test_stale_drafts_and_sharing_consent()
 print(JSON.stringify({"suite": "controller_store_synthetic", "assertions": assertions, "failures": failures, "ok": failures.is_empty()}))
 quit(0 if failures.is_empty() else 1)
