extends SceneTree
const Store = preload("res://cosmic/media_optin_store.gd")
const Config = preload("res://cosmic/media_optin_config.gd")
const Queue = preload("res://cosmic/media_local_queue.gd")
const Planner = preload("res://cosmic/media_optin_plan.gd")
var failures := 0
var assertions := 0
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void:
 var store := Store.new()
 store.path = "user://media_host_store_test_%s.json" % Time.get_ticks_usec()
 check(store.load_state().is_empty(), "Missing metadata remains empty")
 check(store.save_decision(Config.defer_setup(true)) == OK, "Skip persists")
 check(store.load_state().decision.decision == "skipped", "Skip restored")
 var config := Config.choose("master_system", "/never-probe-this-synthetic-root", ["covers"])
 var plan := Planner.build(config, [{"id":"exact-edition", "system":"master_system", "media_metadata":{"cover_front":{"relative_path":"front.png", "status":"present"}}}])
 check(store.save_plan(plan) == OK, "Plan saves with nonexistent media root, no probing")
 var loaded := store.load_state()
 check(loaded.plan == plan and loaded.decision == config, "Exact plan/config roundtrip")
 check(JSON.stringify(loaded.plan).sha256_text() == JSON.stringify(plan).sha256_text(), "Canonical queue signature preserved across JSON")
 var journal := store.path + "_queue"
 check(Queue.new().start(plan, journal) == OK, "Queue metadata initialized without source reads")
 check(Queue.new().restore(loaded.plan, journal) == OK, "Reloaded consent plan resumes exact queue signature")
 for suffix in ["", ".tmp", ".bak"]:
  if FileAccess.file_exists(journal + suffix): DirAccess.remove_absolute(journal + suffix)
 loaded.plan.files.clear()
 check(store.load_state().plan.files.size() == 1, "Load data is detached")
 check(store.save_decision(Config.defer_setup()) == OK, "Later persists independently")
 check(store.load_state().plan == plan, "Later preserves explicit resume offer")
 var corrupt := FileAccess.open(store.path, FileAccess.WRITE)
 corrupt.store_string("not json")
 corrupt.close()
 check(store.load_state().plan == plan, "Corrupt primary recovers valid backup")
 check(store.save_decision(Config.defer_setup(true)) == OK, "Save replaces corrupt primary safely")
 check(store.load_state().decision.decision == "skipped", "New primary readable")
 var invalid := plan.duplicate(true)
 invalid.files[0].relative_path = "../outside.png"
 check(store.save_plan(invalid) == ERR_INVALID_PARAMETER, "Traversal plan rejected")
 invalid = plan.duplicate(true)
 invalid.files_total = 42
 check(store.save_plan(invalid) == ERR_INVALID_PARAMETER, "False counts rejected")
 invalid = plan.duplicate(true)
 invalid.files[0].links[0].identity_status = "verified"
 check(store.save_plan(invalid) == ERR_INVALID_PARAMETER, "Hash cannot create verified identity")
 invalid = plan.duplicate(true)
 invalid.extra = "x".repeat(Store.MAX_BYTES)
 check(store.save_plan(invalid) == ERR_OUT_OF_MEMORY, "Oversized state rejected before write")
 check(store.load_state().decision.decision == "skipped", "Oversize preserves previous state")
 corrupt = FileAccess.open(store.path, FileAccess.WRITE)
 corrupt.store_string(JSON.stringify({"version":1,"decision":{},"plan":{}}))
 corrupt.close()
 if FileAccess.file_exists(store.path + ".bak"): DirAccess.remove_absolute(store.path + ".bak")
 check(store.load_state().is_empty(), "Malformed structure cannot offer resume")
 for suffix in ["", ".tmp", ".bak"]:
  if FileAccess.file_exists(store.path + suffix): DirAccess.remove_absolute(store.path + suffix)
 store.path = "/tmp/not-private.json"
 check(store.save_decision(Config.defer_setup()) == ERR_INVALID_PARAMETER and store.load_state().is_empty(), "Only private user paths accepted")
 print("MEDIA_HOST_STORE: %d assertions; %d failures" % [assertions, failures])
 quit(0 if failures == 0 else 1)
