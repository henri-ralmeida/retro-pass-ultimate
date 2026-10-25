extends SceneTree
## Each stage is a DISTINCT process with the same isolated synthetic user://.
const Store = preload("res://cosmic/media_binding_store.gd")
const Association = preload("res://cosmic/media_result_association.gd")
const Planner = preload("res://cosmic/media_optin_plan.gd")
const Config = preload("res://cosmic/media_optin_config.gd")
const Queue = preload("res://cosmic/media_local_queue.gd")
const Tour = preload("res://cosmic/media_tour_store.gd")
func _initialize() -> void:
 var phase := OS.get_cmdline_user_args()[0]
 var store := Store.new()
 var tour := Tour.new()
 var folder := ProjectSettings.globalize_path("user://restart_fixture")
 var item := {"id":"exact-restart-game", "system":"master_system", "edition":"synthetic-EU", "cover_front":"original", "media_metadata":{"cover_front":{"relative_path":"front.png","status":"present"}}}
 var ok := true
 if phase == "write":
  DirAccess.make_dir_recursive_absolute(folder)
  var png := Image.create(16,16,false,Image.FORMAT_RGBA8)
  png.fill(Color.BLUE)
  png.save_png(folder.path_join("front.png"))
  var queue := Queue.new()
  var plan := Planner.build(Config.choose("master_system",folder,["covers"]),[item])
  ok = queue.start(plan,"user://restart_queue.json") == OK
  for n in 100:
   if queue.tick().status in ["done","completed_with_errors"]: break
  var result := Association.build(queue.state,[item])
  ok = ok and result.applied == 1 and store.save_bindings(result.bindings) == OK
  ok = ok and store.save_bindings(result.bindings) == OK and tour.save_tour("later") == OK
 elif phase == "restore":
  var result := Store.restore(store.load_state().get("bindings",[]),[item])
  ok = result.applied == 1 and result.items[0].cover_front == folder.path_join("front.png") and result.items[0].local_media_previous.cover_front == "original"
  ok = ok and tour.state() == "later"
  # Simulate a process interrupted with corrupt primary and unfinished temp.
  for path in [store.path,store.path+".tmp"]:
   var file := FileAccess.open(path,FileAccess.WRITE)
   file.store_string("partial")
   file.close()
 elif phase == "recover":
  var result := Store.restore(store.load_state().get("bindings",[]),[item])
  ok = result.applied == 1 and tour.state() == "later"
  var png := Image.create(16,16,false,Image.FORMAT_RGBA8)
  png.fill(Color.RED)
  png.save_png(folder.path_join("front.png"))
 elif phase == "reject_changed":
  var result := Store.restore(store.load_state().get("bindings",[]),[item])
  ok = result.applied == 0 and result.items == [item] and not result.issues.is_empty()
 else: ok = false
 print("MEDIA_BINDING_RESTART ",phase,": ","PASS" if ok else "FAIL")
 quit(0 if ok else 1)
