extends SceneTree
const Config = preload("res://cosmic/media_optin_config.gd")
const Planner = preload("res://cosmic/media_optin_plan.gd")
const Queue = preload("res://cosmic/media_local_queue.gd")
const JOURNAL := "user://optin_cross_process.json"
func _initialize() -> void:
 var phase := OS.get_cmdline_user_args()[0]
 var fixture := ProjectSettings.globalize_path("user://optin_cross_process_fixture")
 var file_path := fixture.path_join("explicit.png")
 var plan := Planner.build(Config.choose("master_system", fixture, ["covers"]), [
  {"id":"synthetic", "system":"master_system", "media_metadata":{"cover_front":{"relative_path":"explicit.png", "status":"present"}}}])
 var queue := Queue.new()
 var passed := false
 if phase == "write":
  DirAccess.make_dir_recursive_absolute(fixture)
  var bytes := PackedByteArray()
  bytes.resize(Queue.CHUNK_BYTES + 7)
  bytes.fill(12)
  var file := FileAccess.open(file_path, FileAccess.WRITE)
  file.store_buffer(bytes)
  file.close()
  passed = queue.start(plan, JOURNAL) == OK
  passed = queue.tick().bytes_read == Queue.CHUNK_BYTES and passed
 elif phase == "resume":
  passed = queue.restore(plan, JOURNAL) == OK
  passed = queue.progress().bytes_read == 0 and passed
  for i in range(4): queue.tick()
  passed = queue.progress().status == "done" and passed
 elif phase == "recover":
  # Simulate loss/corruption of latest snapshot; previous valid snapshot recovers.
  var file := FileAccess.open(JOURNAL, FileAccess.WRITE)
  file.store_string("{interrupted")
  file.close()
  passed = queue.restore(plan, JOURNAL) == OK
  for i in range(4): queue.tick()
  passed = queue.progress().status == "done" and passed
  for suffix in ["", ".tmp", ".bak"]:
   if FileAccess.file_exists(JOURNAL + suffix): DirAccess.remove_absolute(JOURNAL + suffix)
  DirAccess.remove_absolute(file_path)
  DirAccess.remove_absolute(fixture)
 print("MEDIA_OPTIN_PERSISTENCE ", phase, ": ", "PASS" if passed else "FAIL")
 quit(0 if passed else 1)
