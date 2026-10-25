extends SceneTree
const Library = preload("res://cosmic/atari_library_view.gd")
var failures: Array[String] = []
var exits := 0
func _initialize() -> void: _run.call_deferred()
func _expect(ok: bool, message: String) -> void:
 if not ok: failures.append(message)
func _run() -> void:
 var view := Library.new()
 root.add_child(view)
 view.configure(root)
 view.exit_requested.connect(func(): exits += 1)
 view.begin_catalog_visit()
 view.open()
 _expect(view.state == "collection", "Library opens in collection")
 _expect(view.ITEMS.size() == 1, "No invented additional titles")
 var path := OS.get_environment("RETROPASS_ATARI_MEDIA_MANIFEST")
 if path.is_empty():
  _expect(not view.inspect("box"), "No-media inspection cannot create replacement")
  _expect(view.exhibit.asset_roots.is_empty(), "No-media state has no models")
 else:
  _expect(view.exhibit.asset_roots.size() == 5, "All original private roles loaded")
  var cartridge_id: int = view.exhibit.canonical_cartridge.get_instance_id()
  for repeat in 3:
   for role in ["box", "cartridge", "manual"]:
    _expect(view.inspect(role), "Inspection opens original " + role)
    _expect(view.state == "inspection", "Inspection state active")
    _expect(view.exhibit.canonical_cartridge.get_instance_id() == cartridge_id,"Canonical cartridge never duplicated")
    if role == "manual":
     _expect(view.manual_leaves.size() == 4,"Original four 3D leaves")
     for i in 8: view.turn_manual(1)
     _expect(view.manual_turns == 4,"Manual turn upper bound")
     for i in 8: view.turn_manual(-1)
     _expect(view.manual_turns == 0,"Manual turn lower bound")
     for i in 4: _expect(view.manual_leaves[i].transform.is_equal_approx(view.manual_rest[i]),"Manual restores native leaf pose")
    view.go_back()
    _expect(view.state == "collection", "Back returns from inspection to collection")
    _expect(view.inspection_role.is_empty(), "No stale inspection role")
  _expect(exits == 0,"Inspection Back does not exit library")
 view.dragging = true
 view.cancel_drag()
 _expect(not view.dragging, "Focus interruption cancels drag")
 var key := InputEventKey.new()
 key.pressed = true
 key.keycode = KEY_UP
 view.state = "inspection"
 for i in 100: view.handle_event(key)
 _expect(is_equal_approx(view.pivot.rotation.x,-1.3),"Keyboard extreme rotation bounded")
 view.reset_inspection()
 _expect(view.pivot.rotation.is_zero_approx(),"Reset clears rotation")
 view.state = "collection"
 view.go_back()
 _expect(exits == 1,"Collection Back requests one exit")
 view.close()
 _expect(view.state == "closed" and not view.visible,"Close hides library")
 _expect(view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"Close stops private viewport")
 for repeat in 3:
  view.open()
  view.close()
 _expect(not view.handle_event(key),"Hidden library ignores inputs")
 view.free()
 for failure in failures: push_error(failure)
 print("ATARI LIBRARY TEST FAILURES: ", failures.size())
 quit(0 if failures.is_empty() else 1)
