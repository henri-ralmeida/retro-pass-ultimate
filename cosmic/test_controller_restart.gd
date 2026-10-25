extends SceneTree
## Execute twice in separate processes with the same isolated XDG_DATA_HOME.
const Profile = preload("res://cosmic/sms_mapping_profile.gd")
const Store = preload("res://cosmic/controller_profile_store.gd")
func _initialize() -> void:
 var mode := "read"
 if "--write" in OS.get_cmdline_user_args(): mode = "write"
 var store = Store.new("user://restart_fixture/profiles.json")
 var ok := not FileAccess.file_exists("user://controls.cfg")
 if mode == "write":
  var profile = Profile.new(0)
  ok = ok and profile.rebind("button_1", "keyboard", {"kind":"key", "code":KEY_C})
  ok = ok and store.save_profile(profile.snapshot()) == OK
 else:
  var loaded: Dictionary = store.load_profiles()
  ok = ok and loaded.error == OK
  ok = ok and loaded.profiles[0].bindings.keyboard.button_1.code == KEY_C
  ok = ok and loaded.profiles[1] == Profile.new(1).snapshot()
  ok = ok and not store._list_generation_files().files.is_empty()
 ok = ok and not FileAccess.file_exists("user://controls.cfg")
 var report := {"suite":"controller_restart", "mode":mode, "passed":ok, "process_id":OS.get_process_id(), "platform":OS.get_name(), "hardware":false}
 var output := FileAccess.open("res://evidence/controller_restart_%s.json" % mode, FileAccess.WRITE)
 output.store_string(JSON.stringify(report,"  "))
 output.close()
 print(JSON.stringify(report))
 quit(0 if ok else 1)
