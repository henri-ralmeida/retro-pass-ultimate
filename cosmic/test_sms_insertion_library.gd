extends SceneTree
const Library = preload("res://cosmic/library_view.gd")
const Profile = preload("res://cosmic/input_profile.gd")
class Host extends Node:
 var application_focused := true
 var scene_active := true
 var reduced_motion := false
 var input_profile = Profile.new()
 var input_device := "keyboard"
 var active_pad_name := ""
var checks := 0
var failures: Array[String] = []
var exits := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
 checks += 1
 if not value: failures.append(label)
func run() -> void:
 var host := Host.new()
 root.add_child(host)
 var view := Library.new()
 root.add_child(view)
 view.configure(host)
 view.set_process(false)
 view.exit_requested.connect(func(): exits += 1)
 view.open()
 var id: String = str(view.ITEMS[view.current_index].id)
 view.begin_catalog_visit()
 var selection: String = view.catalog_choice.get_selected_id()
 view.arm_entry_autostart()
 var token: int = view.arm_entry_autostart()
 check(view.catalog_choice.get_selected_id()==selection,"Repeated entry-token arming retains the console visit selected ID")
 view.cancel_pending_autostart()
 check(not view.complete_entry_autostart(token),"Canceled intention cannot start")
 view.close()
 view.open()
 var current_token: int = view.arm_entry_autostart()
 check(not view.complete_entry_autostart(token) and view.autostart_intent.pending,"Old visit callback leaves newer intention intact")
 host.application_focused = false
 check(not view.complete_entry_autostart(current_token) and not view.autostart_intent.pending,"Pending intention loses focus without surprise restart")
 host.application_focused = true
 check(not view.insertion_active,"Refocus alone never starts")
 var original_patch := OS.get_environment("RETROPASS_SMS_MECHANICAL_PATCH")
 OS.set_environment("RETROPASS_SMS_MECHANICAL_PATCH","")
 id = str(view.ITEMS[view.current_index].id)
 check(not view.start_insertion(),"Missing private geometry never animates")
 check(str(view.ITEMS[view.current_index].id)==id,"Missing geometry does not reroll selected entry")
 check(not view.insertion_active and not view.insertion_failed,"Unavailable setup preserves collection navigation")
 check(not view.insertion_status.is_empty(),"Unavailable setup explains limitation")
 OS.set_environment("RETROPASS_SMS_MECHANICAL_PATCH",original_patch)
 var private_expected := not original_patch.is_empty() and not OS.get_environment("RETROPASS_SMS_MEDIA_BINDING").is_empty()
 var private_started: bool = view.start_insertion() if private_expected else false
 if private_expected: check(private_started,"Explicit private fixture must actually prepare: " + view.insertion_status)
 if private_started:
  var cart: Node3D = view.box.cartridge
  var identity := cart.get_instance_id()
  var cart_parent := cart.get_parent()
  var physical_manual: Variant = view.box.manual_book
  var manual_id: int = physical_manual.root.get_instance_id() if physical_manual != null else 0
  var manual_rest: Transform3D = physical_manual.root.transform if physical_manual != null else Transform3D.IDENTITY
  check(physical_manual != null and physical_manual.configured,"Supplied private manual exists physically under native lid clips")
  view.go_back()
  view.advance_insertion(100.0)
  var rest := cart.transform
  var camera_rest := view.camera.transform
  for phase in [0.1,0.8,1.7,2.7,3.7,4.4,5.0,6.0]:
   check(view.start_insertion(),"Starts from restored collection")
   check(not view.start_insertion(),"Repeated start is idempotent")
   view.advance_insertion(phase)
   check(physical_manual.root.get_instance_id()==manual_id and physical_manual.root.get_parent()==view.box.lid and physical_manual.root.transform==manual_rest,"Insertion keeps the same physical booklet attached under the original lid")
   check(physical_manual.root.is_visible_in_tree() and physical_manual.paper.is_visible_in_tree(),"Physical manual remains visible; no hidden substitute during insertion")
   var pose := cart.transform
   var time: float = view.insertion_session.time
   var echo := InputEventKey.new()
   echo.keycode = KEY_X
   echo.physical_keycode = KEY_X
   echo.pressed = true
   echo.echo = true
   view.handle_event(echo)
   check(view.insertion_session.time==time and view.insertion_session.target>0.0,"Held confirm echo cannot activate focused Back")
   host.application_focused = false
   view._process(20.0)
   check(cart.transform==pose and view.insertion_session.time==time,"Focus pause consumes no time")
   host.application_focused = true
   view.reset_inspection()
   view.rotate_inspection(Vector2(80,80))
   view.zoom_inspection(0.5)
   view.confirm_selected()
   view._open_manual()
   view.navigate(1)
   check(cart.transform==pose and view.insertion_active,"Other writers cannot alter active rig")
   view.go_back()
   check(cart.transform==pose,"Cancel request itself never teleports")
   view.go_back()
   check(exits==0,"Repeated Back cannot skip reversal")
   view.advance_insertion(100.0)
   check(not view.insertion_active and cart.transform==rest,"Reverse restores exact inside pose")
   check(cart.get_instance_id()==identity and cart.get_parent()==cart_parent,"Canonical identity and parent preserved")
   check(view.camera.transform.is_equal_approx(camera_rest),"Reverse restores departure camera")
   check(not view.autostart_intent.pending,"Return to box does not rearm")
  check(view.start_insertion(),"Mid-motion reduced fixture begins")
  view.advance_insertion(0.3)
  host.reduced_motion = true
  view.advance_insertion(0.0)
  check(view.insertion_session.state=="seated","Changing to reduced motion completes the owned path coherently")
  view.go_back()
  check(not view.insertion_active and cart.transform==rest,"Reduced return restores exact pose")
  check(view.start_insertion() and view.insertion_session.state=="seated","Reduced motion reaches coherent seated endpoint")
  view.go_back()
  check(not view.insertion_active and cart.transform==rest,"Reduced motion returns atomically to original box")
  host.reduced_motion = false
  check(view.start_insertion(),"Failure fixture begins")
  view.advance_insertion(0.4)
  cart.free()
  view.advance_insertion(0.1)
  var notice: String = view.insertion_status
  view.refresh_controls()
  view.advance_insertion(1.0)
  check(view.insertion_failed and view.insertion_status==notice,"Lost canonical latches failure and preserves notice")
  view.go_back()
  check(exits==1 and not view.visible,"Failure Back hides and exits instead of fake reverse")
  view.close()
  view.close()
  view.open()
  check(is_instance_valid(view.box) and not view.insertion_failed,"Repeated close and reopen rebuilds clean box")
  for role in ["box","console","camera","cartridge_parent","pivot_translation"]:
   check(view.start_insertion(),"Freed-root fixture begins")
   view.advance_insertion(0.4)
   match role:
    "box": view.box.free()
    "console": view.insertion_session.console.free()
    "camera": view.camera.free()
    "cartridge_parent": view.box.cartridge.get_parent().free()
    "pivot_translation": view.pivot.position += Vector3(0.2,0,0)
   view.advance_insertion(0.1)
   check(view.insertion_failed,"Removed root fails closed rather than running stale rig")
   view.go_back()
   view.close()
   view.close()
   view.open()
   check(is_instance_valid(view.box) and not view.insertion_failed and view.pivot.position==Vector3.ZERO,"Removed/moved root rebuilds clean layout after idempotent close")
  check(view.start_insertion(),"Force-close fixture begins")
  view.advance_insertion(2.1)
  view.close()
  check(not view.visible and not view.insertion_active,"Force close hides before teardown")
  view.open()
  check(not view.insertion_active and view.box.cartridge.transform==view.box.inside_pose,"Interrupted close reopens without surprise animation")
 else:
  check(not view.insertion_active,"Absent matching media remains honest")
 view.close()
 view.close()
 view.open()
 check(view.catalog_choice.get_selected_id()==selection,"Close/open alone preserves the console catalog visit")
 view.close()
 view.free()
 host.free()
 await process_frame
 await test_main_dispatch()
 print("SMS insertion library checks=",checks," failures=",failures)
 quit(0 if failures.is_empty() else 1)

func dispatch_key(code: int, echo: bool = false) -> void:
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = true
 event.echo = echo
 root.push_input(event,true)
 event = InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = false
 root.push_input(event,true)

func dispatch_click(position: Vector2) -> void:
 var motion := InputEventMouseMotion.new()
 motion.position = position
 motion.global_position = position
 root.push_input(motion,true)
 await process_frame
 var event := InputEventMouseButton.new()
 event.position = position
 event.global_position = position
 event.button_index = MOUSE_BUTTON_LEFT
 event.pressed = true
 root.push_input(event,true)
 await process_frame
 event = InputEventMouseButton.new()
 event.position = position
 event.global_position = position
 event.button_index = MOUSE_BUTTON_LEFT
 event.pressed = false
 root.push_input(event,true)
 await process_frame

func test_main_dispatch() -> void:
 # Synthetic viewport events, but real main._input -> library -> native GUI route.
 # This is not a claim of physical keyboard/mouse or Windows validation.
 root.size = Vector2i(1152,648)
 var main = load("res://cosmic/main.tscn").instantiate()
 root.add_child(main)
 await process_frame
 main.set_process(false)
 main.reduced_motion = true
 main.enter_library()
 var view = main.library_view
 view.set_process(false)
 await process_frame
 await process_frame
 var action_label: Label = view.insert_button.find_child("ActionLabel",true,false)
 check(action_label != null and action_label.text=="Inserir" and view.insert_button.accessibility_name=="Inserir cartucho no console","Short visible insertion label retains full accessible action")
 if view.insertion_active:
  for window_size in [Vector2i(1024,768),Vector2i(1152,648)]:
   root.size=window_size
   await process_frame
   main._layout()
   await process_frame
   check(action_label.get_parent().get_combined_minimum_size().x<=view.insert_button.size.x+0.5,"Insertion keycap and label fit their footer cell")
   var stage_rect := Rect2(Vector2.ZERO,Vector2(view.viewport.size))
   var all_inside := true
   for stage_root in [view.box,view.insertion_session.console]:
    for mesh in stage_root.find_children("*","MeshInstance3D",true,false):
     if not mesh.mesh or not mesh.is_visible_in_tree(): continue
     for corner in range(8):
      var point: Vector3 = mesh.global_transform*mesh.get_aabb().get_endpoint(corner)
      if view.camera.is_position_behind(point) or not stage_rect.has_point(view.camera.unproject_position(point)): all_inside=false
   check(all_inside,"Seated box/manual/console/cartridge remain within 3D viewport after live aspect change")
  main.reduced_motion = false
  var cart: Node3D = view.box.cartridge
  var pose := cart.transform
  var before: float = view.insertion_session.time
  await dispatch_click(Vector2(2,2))
  check(cart.transform==pose and view.insertion_session.time==before and view.insertion_session.target>0.0,"Outside pointer cannot manipulate or cancel model")
  dispatch_key(KEY_X,true)
  check(view.insertion_session.target>0.0,"Real main routing blocks held confirm echo")
  check(root.get_visible_rect().has_point(view.back_button.get_global_rect().get_center()),"Back button center lies inside dispatched viewport")
  await dispatch_click(view.back_button.get_global_rect().get_center())
  check(view.insertion_active and view.insertion_session.target==0.0,"Real viewport mouse click reaches native Back button")
  check(cart.transform==pose,"Mouse cancellation request itself preserves continuity")
  view.advance_insertion(100.0)
  check(not view.insertion_active,"Mouse-requested reverse reaches collection")
  for code in [KEY_ENTER,KEY_X]:
   check(view.start_insertion(),"Keyboard dispatch fixture starts")
   view.advance_insertion(0.3)
   view.back_button.grab_focus()
   dispatch_key(code)
   check(view.insertion_session.target==0.0,"Enter or mapped confirm activates focused Back through main")
   view.advance_insertion(100.0)
  for role in ["cartridge","camera"]:
   if not view.insertion_active: view.start_insertion()
   view.advance_insertion(0.3)
   if role == "cartridge": view.box.cartridge.free()
   else: view.camera.free()
   view.advance_insertion(0.1)
   view.back_button.grab_focus()
   dispatch_key(KEY_ENTER)
   check(not view.visible and main.library_state=="system","Focused Enter exits a latched failure through main")
   main._layout()
   var previous_size := root.size
   root.size = Vector2i(1024,768)
   await process_frame
   main._layout()
   check(view.insertion_rebuild and not view.visible,"Hidden failed view tolerates host layout and viewport resize")
   root.size = previous_size
   main.reduced_motion = true
   main.enter_library()
   await process_frame
   check(is_instance_valid(view.box) and is_instance_valid(view.camera) and not view.insertion_failed,"Main reopen rebuilds removed geometry/camera safely")
   main.reduced_motion = false
 else:
  check(not view.insertion_active,"Without linked private media main dispatch does not invent a stage")
 main.free()
 await process_frame
