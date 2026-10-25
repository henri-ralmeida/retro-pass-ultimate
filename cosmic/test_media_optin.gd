extends SceneTree
const Config = preload("res://cosmic/media_optin_config.gd")
const Planner = preload("res://cosmic/media_optin_plan.gd")
const Queue = preload("res://cosmic/media_local_queue.gd")
var failures := 0
var assertions := 0
var fixture_root := ""
var journal := ""

func check(condition: bool, label: String) -> void:
 assertions += 1
 if not condition:
  failures += 1
  push_error(label)

func write(path: String, bytes: PackedByteArray) -> void:
 var f := FileAccess.open(path, FileAccess.WRITE)
 f.store_buffer(bytes)
 f.close()

func entry(id: String, media: Dictionary, system: String = "master_system") -> Dictionary:
 return {"id":id, "system":system, "media_metadata":media}

func media(path: String, status: String = "present") -> Dictionary:
 return {"relative_path":path, "status":status}

func _initialize() -> void:
 run.call_deferred()

func run() -> void:
 var token := str(Time.get_ticks_usec())
 fixture_root = ProjectSettings.globalize_path("user://media_optin_fixture_" + token)
 journal = "user://media_optin_journal_" + token + ".json"
 DirAccess.make_dir_recursive_absolute(fixture_root)
 var data := PackedByteArray()
 data.resize(Queue.CHUNK_BYTES + 19)
 data.fill(123)
 write(fixture_root.path_join("front.png"), data)
 var before := FileAccess.get_sha256(fixture_root.path_join("front.png"))
 var records := [entry("edition_a", {"cover_front":media("front.png"), "wheel":media("OFF.png"), "manual":media("OFF.pdf")}),
  entry("edition_b", {"cover_front":media("front.png"), "cover_back":media("missing.png")}),
  entry("other_system", {"cover_front":media("other.png")}, "atari_2600")]
 var config := Config.choose("master_system", fixture_root, ["covers"])
 check(config.ok, "Explicit local configuration accepted")
 check(not Config.choose("master_system", "https://invalid.test", ["covers"]).ok, "Network rejected")
 check(not Config.choose("master_system", fixture_root, ["unknown"]).ok, "Unknown categories rejected")
 check(Config.choose("master_system", "C:/", []).root == "C:/", "Drive fixture_root remains absolute")
 check(Planner.build(Config.defer_setup(), records).files.is_empty(), "Later does not schedule")
 check(Planner.build(Config.defer_setup(true), records).files.is_empty(), "Skip does not schedule")
 var plan := Planner.build(config, records)
 check(plan.files_total == 2 and plan.games_total == 2, "Two files, two games; disabled categories and other system excluded")
 check(plan.files[0].links.size() == 2, "Shared file preserves both edition links")
 var tampered: Dictionary = plan.duplicate(true)
 tampered.files[0].links[0].tag = "manual"
 check(Queue.new().start(tampered, journal) == ERR_INVALID_PARAMETER, "Queue independently rejects disabled-category link")
 check(Planner.build(config, records + records).files[0].links.size() == 2, "Repeated records dedupe links")
 var unsafe := Planner.build(config, [entry("bad", {"cover_front":media("../escape.png")})])
 check(unsafe.files.is_empty() and unsafe.issues.size() == 1, "Traversal rejected without opening")
 var queue := Queue.new()
 check(queue.start(plan, journal) == OK, "Journal created")
 var p := queue.tick()
 check(p.bytes_read == Queue.CHUNK_BYTES and p.files_done == 0, "Actual first chunk progress, not games-as-files")
 check(queue.cancel() == OK and queue.progress().status == "cancelled", "Cancellation persisted")
 var resumed := Queue.new()
 check(resumed.restore(plan, journal) == OK, "Resume same approved plan")
 check(resumed.progress().bytes_read == 0, "Incomplete hash restarts honestly at zero")
 for i in range(8): resumed.tick()
 p = resumed.progress()
 check(p.status == "completed_with_errors" and p.files_done == 1 and p.files_error == 1, "Missing file explicit, no synthetic success")
 check(p.games_done == 1 and p.games_total == 2, "Shared file resolves both links but missing back keeps second game incomplete")
 check(resumed.state.files[0].sha256 == before, "Full source bytes processed")
 check(FileAccess.get_sha256(fixture_root.path_join("front.png")) == before, "Original preserved")
 var broken_storage := Queue.new()
 check(broken_storage.start(plan, "user://missing_parent_" + token + "/queue.json") != OK and broken_storage.progress().status == "storage_error", "Storage failure blocks processing explicitly")
 var repeat := Queue.new()
 check(repeat.restore(plan, journal) == OK and repeat.progress().files_done == 0, "Completed sources revalidated on retry")
 var changed := Planner.build(Config.choose("master_system", fixture_root, ["manual"]), records)
 check(Queue.new().restore(changed, journal) == ERR_INVALID_DATA, "Changed consent requires new plan, never broadens old journal")
 # Missing file can be supplied later; retry only it, preserving completed link.
 write(fixture_root.path_join("missing.png"), "synthetic-back".to_utf8_buffer())
 for i in range(5): repeat.tick()
 check(repeat.progress().status == "done" and repeat.progress().games_done == 2, "Recoverable missing source succeeds after explicit retry")
 var link := fixture_root.path_join("linked.png")
 var link_error := DirAccess.open(fixture_root).create_link(fixture_root.path_join("front.png"), link)
 if link_error == OK:
  var linked_plan := Planner.build(config, [entry("linked", {"cover_front":media("linked.png")})])
  var linked := Queue.new()
  linked.start(linked_plan, journal + "_link")
  linked.tick()
  check(linked.progress().files_error == 1 and linked.progress().bytes_read == 0, "Symlink denied before media read")
  DirAccess.remove_absolute(link)
 else: check(false, "Symlink fixture creation required")
 for suffix in ["", ".tmp", ".bak", "_link", "_link.tmp", "_link.bak"]:
  if FileAccess.file_exists(journal + suffix): DirAccess.remove_absolute(journal + suffix)
 DirAccess.remove_absolute(fixture_root.path_join("front.png"))
 DirAccess.remove_absolute(fixture_root.path_join("missing.png"))
 DirAccess.remove_absolute(fixture_root)
 print("MEDIA_OPTIN: ", assertions, " assertions; ", failures, " failures")
 quit(0 if failures == 0 else 1)
