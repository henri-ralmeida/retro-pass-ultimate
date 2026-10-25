extends SceneTree
## Deterministic library interaction and projected-box framing checks.
## Does not replace visual QA or a physical gamepad test.
var failures: Array[String] = []
var assertions := 0
var exits := 0

func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok:
  failures.append(message)
  push_error(message)

func _initialize() -> void: run.call_deferred()

func key(code: Key, echo_value: bool = false) -> InputEventKey:
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = true
 event.echo = echo_value
 return event

func mouse(button: MouseButton, pressed_value: bool, point: Vector2) -> InputEventMouseButton:
 var event := InputEventMouseButton.new()
 event.button_index = button
 event.pressed = pressed_value
 event.position = point
 event.global_position = point
 return event

func motion(relative_value: Vector2) -> InputEventMouseMotion:
 var event := InputEventMouseMotion.new()
 event.relative = relative_value
 return event

func axis(which: JoyAxis, value: float) -> InputEventJoypadMotion:
 var event := InputEventJoypadMotion.new()
 event.axis = which
 event.axis_value = value
 return event

func _assert_framing(view: Control, label: String) -> void:
 var low := Vector2(INF,INF)
 var high := Vector2(-INF,-INF)
 var viewport_size: Vector2 = Vector2(view.viewport.size)
 var depth_ok := true
 for mesh in view.box.find_children("*", "MeshInstance3D", true, false):
  if not mesh.mesh or not mesh.is_visible_in_tree(): continue
  for index in range(8):
   var corner: Vector3 = mesh.to_global(mesh.get_aabb().get_endpoint(index))
   var projected: Vector2 = view.camera.unproject_position(corner)/viewport_size
   low = low.min(projected)
   high = high.max(projected)
   var depth: float = -view.camera.to_local(corner).z
   depth_ok = depth_ok and depth > view.camera.near and depth < view.camera.far
 check(low.x >= 0.049 and low.y >= 0.049 and high.x <= 0.951 and high.y <= 0.951 and depth_ok,label+": every visible mesh corner remains in frame with 4.9% margin")
 var center: Vector2 = view.camera.unproject_position(view.pivot.global_position)/viewport_size
 check(center.distance_to(Vector2(0.5,0.5)) < 0.002,label+": centered pivot")

func run() -> void:
 # Data-only second entry verifies multi-item carousel without shipping fake art.
 var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/local_box_art/manifest.json")) if FileAccess.file_exists("res://assets/local_box_art/manifest.json") else {"items":[]}
 var fixture_items: Array = []
 for raw in manifest.get("items", []):
  var item: Dictionary = raw.duplicate(true)
  for field in ["cover_front","cover_back","cover_spine","model_path","uv_path","art_root"]:
   if item.has(field): item[field] = ProjectSettings.globalize_path("res://assets/local_box_art/" + str(item[field]))
  fixture_items.append(item)
 if fixture_items.is_empty(): fixture_items.append({"id":"test_one","title":"Wonder Boy"})
 fixture_items.append({"id":"test_missing", "title":"QA unavailable", "subtitle":"TEST ONLY"})
 var fixture := "user://library_view_manifest.json"
 FileAccess.open(fixture,FileAccess.WRITE).store_string(JSON.stringify({"items":fixture_items}))
 OS.set_environment("RETROPASS_BOX_ART_MANIFEST",fixture)
 root.size = Vector2i(1152,648)
 var scene = load("res://cosmic/main.tscn").instantiate()
 scene.input_profile.config_path = "res://evidence/cosmic/library_view_fixture.cfg"
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene._focus_returned()
 scene.reduced_motion = true
 scene.cooldown = 0.0
 scene.confirm_selection("library_view_test")
 var view = scene.library_view
 view.exit_requested.connect(func(): exits += 1)
 check(view.visible and not view.inspect_mode,"Library opens in collection mode")
 check(view.current_index == 0 and view.item_title.text == "Wonder Boy","Manifest first item is selected")
 check("Acervo local" in view.disclosure.text and "sem jogos" in view.disclosure.text,"Always-visible disclosure identifies concept-only library")
 check(view.cards.size() == 2 and view.card_textures[1].texture == null,"Missing artwork stays blank rather than inventing a cover")
 check(view.box.get_parent() == view.pivot and view.model_bounds.size.z > 0.05,"True volumetric box parented to centered pivot")
 check(view.camera.projection == Camera3D.PROJECTION_PERSPECTIVE,"Carousel uses perspective projection")
 check(view.neighbor_boxes.size() == 1,"One neighbor per distinct alternate item, no duplicates")
 check(view.neighbor_boxes[0].position.z < 0 and not is_zero_approx(view.neighbor_boxes[0].rotation.y),"Neighbor recedes and turns in perspective")
 check(not view.reset_button.visible and not view.zoom_controls.visible,"Inspection-only tools start hidden")
 view.navigate(-1)
 check(view.current_index == 1 and view.item_title.text == "QA unavailable","Previous wraps to second data entry")
 check(view.description.text == "Capa indisponível","Missing artwork uses one concise honest status")
 view.navigate(1)
 check(view.current_index == 0,"Next wraps to first concept")
 view.cards[1].pressed.emit()
 check(view.current_index == 1,"Accessible card selects its own title")
 view.cards[0].pressed.emit()
 var before: Basis = view.pivot.basis
 view.rotate_inspection(Vector2(50,50))
 view.zoom_inspection(1.0)
 check(view.pivot.basis.is_equal_approx(before) and is_equal_approx(view.zoom,1.0),"Collection does not permit unintended inspection manipulation")
 view.inspect_button.pressed.emit()
 check(view.inspect_mode and view.reset_button.visible and view.zoom_controls.visible,"Real inspect action opens dedicated tools")
 check(not view.cards[0].visible and not view.previous_button.visible,"Collection click targets hidden during inspection")
 check(view.model_bounds.get_center().is_zero_approx(),"Volumetric box has centered local bounds")
 if view.box.can_open():
  check(view.box.get_meta("original_room_geometry",false),"Selected box reuses original room geometry")
  view.confirm_selected()
  check(view.box.opened and is_equal_approx(view.box.lid.rotation.z,deg_to_rad(115)),"Original hinge opens to room angle")
  view.confirm_selected()
  check(view.box.cartridge_out,"Original separate cartridge can be extracted")
  view.reset_inspection()
  check(not view.box.opened and not view.box.cartridge_out,"Restore safely stows cartridge and closes lid")
 var origin: Vector3 = view.pivot.global_position
 view.rotate_inspection(Vector2(70,45))
 check(view.pivot.global_position.is_equal_approx(origin),"Rotation never translates box center")
 check(not is_equal_approx(view.yaw,view.DEFAULT_YAW) and not is_equal_approx(view.pitch,view.DEFAULT_PITCH),"Inspection rotates both yaw and pitch")
 view.reset_inspection()
 view.rotate_inspection(Vector2(TAU/0.008,TAU/0.008))
 check(is_equal_approx(view.yaw,view.DEFAULT_YAW) and is_equal_approx(view.pitch,view.DEFAULT_PITCH),"Full turns wrap through both axes")
 check(not view.has_method("show_face"),"Inspection has no pose presets or face carousel")
 for button in view.all_buttons:
  check(button.text not in ["Frente","Lombada","Verso"],"No face-selection button remains")
 check(not view.mode_label.visible and not view.disclosure.visible and not view.scan_button.visible,"Inspection hides explanatory chrome and collection tools")
 var long_title := "An exceptionally long unchanged catalog filename ".repeat(8)
 var original_title: String = view.ITEMS[view.current_index].title
 view.ITEMS[view.current_index].title = long_title
 view.toggle_inspection()
 view._select(view.current_index)
 view.layout()
 check(view.item_title.text == long_title and view.item_title.tooltip_text == long_title,"Full catalog title remains intact and available")
 check(view.item_title.size.x <= root.get_visible_rect().size.x-48 and view.item_title.clip_text and view.item_title.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,"Long title remains bounded with ellipsis")
 check(view.item_title.get_theme_font_size("font_size") == 18,"Long title shrinks only to a readable bounded minimum")
 for card in view.cards:
  var label: Label = card.get_node("CardTitle")
  check(label.clip_text and label.size.x <= card.size.x-20,"Game tabs bound their original title text")
 view.ITEMS[view.current_index].title = original_title
 view._select(view.current_index)
 view.toggle_inspection()
 view.zoom_inspection(100.0)
 check(is_equal_approx(view.zoom,view.ZOOM_MAX),"Zoom-in clamps at safe maximum")
 for window_size in [Vector2i(1152,648),Vector2i(1024,768),Vector2i(800,600),Vector2i(1728,720)]:
  root.size = window_size
  await process_frame
  view.layout()
  await process_frame
  for x in range(13):
   for y in range(9):
    view.yaw = float(x)*TAU/12.0
    view.pitch = float(y)*TAU/8.0
    view._apply_rotation()
    _assert_framing(view,"%s angle %d/%d" % [window_size,x,y])
  var screen := Rect2(Vector2.ZERO,get_root().get_visible_rect().size)
  for button in view.all_buttons:
   if button.is_visible_in_tree(): check(screen.encloses(button.get_global_rect()),"%s visible %s button stays onscreen" % [window_size,button.accessibility_name])
 view.zoom_inspection(-100.0)
 check(is_equal_approx(view.zoom,view.ZOOM_MIN),"Zoom-out clamps at safe minimum")
 view.reset_inspection()
 check(is_equal_approx(view.zoom,1.0) and is_equal_approx(view.yaw,view.DEFAULT_YAW) and is_equal_approx(view.pitch,view.DEFAULT_PITCH),"Restore resets angle and zoom")
 var view_center: Vector2 = view.viewport_container.get_global_rect().get_center()
 var footer_point: Vector2 = view.back_button.get_global_rect().get_center()
 check(not view.handle_event(mouse(MOUSE_BUTTON_LEFT,true,footer_point)) and not view.dragging,"UI button click is not stolen as a 3D drag")
 check(view.handle_event(mouse(MOUSE_BUTTON_LEFT,true,view_center)) and view.dragging,"Drag begins only in selected 3D viewport")
 var previous_yaw: float = view.yaw
 check(view.handle_event(motion(Vector2(20,10))) and view.yaw != previous_yaw,"Dragged motion rotates selected box")
 check(view.handle_event(mouse(MOUSE_BUTTON_LEFT,false,footer_point)) and not view.dragging,"Release outside viewport cancels captured drag")
 var old_zoom: float = view.zoom
 check(not view.handle_event(mouse(MOUSE_BUTTON_WHEEL_UP,true,footer_point)) and is_equal_approx(view.zoom,old_zoom),"Wheel on footer does not zoom box")
 check(view.handle_event(mouse(MOUSE_BUTTON_WHEEL_UP,true,view_center)) and view.zoom > old_zoom,"Wheel on 3D viewport zooms")
 view.handle_event(axis(JOY_AXIS_LEFT_X,0.9))
 view._process(0.1)
 check(not view.rotate_axis.is_zero_approx(),"Analog rotation is explicit ongoing input")
 view.handle_event(mouse(MOUSE_BUTTON_LEFT,true,view_center))
 scene._focus_lost()
 check(not view.dragging and view.rotate_axis.is_zero_approx() and is_zero_approx(view.zoom_axis),"Focus loss cancels drag and analog input")
 var held_yaw: float = view.yaw
 view.handle_event(motion(Vector2(50,10)))
 view._process(1.0)
 check(is_equal_approx(view.yaw,held_yaw),"Unfocused library cannot rotate")
 scene._focus_returned()
 view.reset_inspection()
 held_yaw = view.yaw
 view._process(20.0)
 check(is_equal_approx(view.yaw,held_yaw),"No autonomous box rotation, including reduced motion")
 view.handle_event(key(KEY_ESCAPE))
 check(not view.inspect_mode and view.visible and exits == 0,"First Escape leaves inspection, not collection")
 view.handle_event(key(KEY_ESCAPE,true))
 check(view.visible and exits == 0,"Held Escape echo cannot exit another level")
 view.handle_event(key(KEY_I,true))
 check(not view.inspect_mode,"Held inspect key does not reopen mode")
 view.handle_event(axis(JOY_AXIS_LEFT_X,0.9))
 var selected: int = view.current_index
 view.handle_event(axis(JOY_AXIS_LEFT_X,0.95))
 check(view.current_index == selected,"Held navigation axis switches only once")
 view.handle_event(axis(JOY_AXIS_LEFT_X,0.0))
 view.handle_event(axis(JOY_AXIS_LEFT_X,0.9))
 check(view.current_index != selected,"Neutral axis rearms deliberate navigation")
 view.cancel_drag()
 var was_reduced: bool = scene.reduced_motion
 view.handle_event(key(KEY_M))
 check(scene.reduced_motion != was_reduced,"Mapped motion action remains reachable in library")
 view.motion_button.pressed.emit()
 check(scene.reduced_motion == was_reduced,"Motion is a real accessible footer button")
 view.handle_event(key(KEY_ESCAPE))
 check(exits == 1 and not view.visible and scene.library_state == "system","Second deliberate Escape exits and restores host")
 check(not view.handle_event(key(KEY_I)),"Closed library does not consume input")
 scene.queue_free()
 await process_frame
 var result := {"passed":failures.is_empty(),"assertions":assertions,"failures":failures,"mode":"headless interaction and projected geometry; not visual or hardware QA"}
 FileAccess.open("res://evidence/cosmic/library_view_tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("COSMIC_LIBRARY_VIEW_TESTS ",JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
