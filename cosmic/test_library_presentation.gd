extends SceneTree
## Integration of real library input, original GameBox rig, camera and lifecycle.
## Synthetic controls and local Linux rendering only, not physical gamepad QA.
var assertions := 0
var failures: Array[String] = []
var scene: Node
var view: Control
var exits := 0
var capture_dir := OS.get_environment("RETROPASS_FLOW_CAPTURE")

func check(value: bool, message: String) -> void:
 assertions += 1
 if not value:
  failures.append(message)
  push_error(message)

func _initialize() -> void: run.call_deferred()

func capture(label: String) -> void:
 if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))

func key(code: Key) -> InputEventKey:
 var event := InputEventKey.new()
 event.physical_keycode = code
 event.keycode = code
 event.pressed = true
 return event

func point_event(button: MouseButton, point: Vector2) -> InputEventMouseButton:
 var event := InputEventMouseButton.new()
 event.button_index = button
 event.position = point
 event.global_position = point
 event.pressed = true
 return event

func framed(label: String) -> void:
 for mesh in view.box.find_children("*", "MeshInstance3D", true, false):
  if not mesh.mesh or not mesh.is_visible_in_tree(): continue
  for index in 8:
   var corner: Vector3 = mesh.to_global(mesh.get_aabb().get_endpoint(index))
   var point: Vector2 = view.camera.unproject_position(corner) / Vector2(view.viewport.size)
   var depth: float = -view.camera.to_local(corner).z
   check(point.x >= 0.049 and point.y >= 0.049 and point.x <= 0.951 and point.y <= 0.951, label + ": all visible mesh corners have margin")
   check(depth > view.camera.near and depth < view.camera.far, label + ": visible corners remain within depth planes")

func run() -> void:
 var manifest := "user://library_presentation_fixture.json"
 FileAccess.open(manifest,FileAccess.WRITE).store_string(JSON.stringify({"items":[{"id":"fixture_one","title":"QA · sem arte"},{"id":"fixture_two","title":"QA · segundo item sem arte"}]}))
 OS.set_environment("RETROPASS_BOX_ART_MANIFEST",manifest)
 root.size = Vector2i(1152,648)
 scene = load("res://cosmic/main.tscn").instantiate()
 scene.input_profile.config_path = "user://library_presentation_controls.cfg"
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene._focus_returned()
 scene.reduced_motion = true
 scene.cooldown = 0.0
 scene.enter_library()
 view = scene.library_view
 view._select(0) # Explicit deterministic fixture choice after random startup.
 view.set_process(false)
 view.exit_requested.connect(func(): exits += 1)
 scene.reduced_motion = false
 await process_frame
 var original_box: Node3D = view.box
 var original_cart: Node3D = view.box.cartridge
 var original_parent: Node = original_cart.get_parent()
 var original_pose: Transform3D = original_cart.transform
 var initial_camera: Vector3 = view.camera.position
 var initial_basis: Basis = view.pivot.basis
 check(view.presentation.available, "Original reusable articulated rig is available")
 check(view.presentation.state == &"closed" and not view.inspect_mode, "Collection starts with selected box closed")
 for button in view.all_buttons:
  check(button.text not in ["Abrir caixa","Retirar cartucho"], "Separate part manipulation buttons are removed")
 await capture("01_collection_16x9")
 var scan_calls := [0]
 var scan_callback := Callable(view,"_choose_scan_folder")
 view.scan_button.pressed.disconnect(scan_callback)
 var scan_spy := func(): scan_calls[0] += 1
 view.scan_button.pressed.connect(scan_spy)
 view.scan_button.grab_focus()
 view.handle_event(key(KEY_X))
 check(scan_calls[0] == 1 and not view.inspect_mode and view.presentation.state == &"closed", "Mapped confirm activates focused Scan without opening box")
 view.scan_button.pressed.disconnect(scan_spy)
 view.scan_button.pressed.connect(scan_callback)
 view.confirm_button.grab_focus()
 view.toggle_inspection()
 check(view.inspect_mode and view.approach_busy and view.approach_progress == 0.0, "Inspection starts a continuous approach")
 check(view.camera.position.is_equal_approx(initial_camera), "Starting approach does not teleport camera")
 check(view.presentation.state == &"closed", "Inspection alone never opens the lid")
 view._advance_presentation(view.APPROACH_SECONDS * 0.3)
 check(view.approach_progress > 0.0 and view.approach_progress < 1.0, "Approach has intermediate positions")
 check(view.camera.position.z < initial_camera.z, "Selected closed box comes closer, even with only neutral art")
 check(view.pivot.basis.is_equal_approx(initial_basis), "Approach imposes no spin or face preset")
 view.navigate(1)
 view.cards[1].pressed.emit()
 check(view.current_index == 0 and view.box == original_box, "Navigation cannot replace a box during approach")
 var interrupted_camera: Vector3 = view.camera.position
 view.go_back()
 check(view.camera.position.is_equal_approx(interrupted_camera), "Back reverses an interrupted approach without a jump")
 view.go_back()
 check(exits == 0, "Repeated Back during return cannot exit library")
 view._advance_presentation(view.APPROACH_SECONDS)
 check(not view.inspect_mode and view.camera.position.is_equal_approx(initial_camera), "Interrupted approach returns exactly to its original carousel")

 view.handle_event(key(KEY_X))
 check(view.pending_confirm and view.presentation.state == &"closed", "Mapped confirmation approaches before opening")
 view._advance_presentation(view.APPROACH_SECONDS)
 check(view.approach_progress == 1.0 and view.presentation.extraction_progress == 0.0, "Box reaches foreground before extraction")
 await capture("02_inspect_closed_16x9")
 view._advance_presentation(view.BoxPresentation.OPEN_SECONDS * 0.5)
 check(view.presentation.lid_angle > 0.0 and view.presentation.lid_angle < 115.0, "Opening has real intermediate hinge positions")
 check(view.presentation.extraction_progress == 0.0 and original_cart.transform.is_equal_approx(original_pose), "Cartridge remains seated until lid fully opens")
 var paused_progress: float = view.presentation.progress
 var paused_approach: float = view.approach_progress
 scene._focus_lost()
 view._process(20.0)
 view._advance_presentation(20.0)
 check(view.presentation.progress == paused_progress and view.approach_progress == paused_approach, "Focus loss freezes both tracks without elapsed-time accumulation")
 scene._focus_returned()
 view._advance_presentation(0.01)
 check(view.presentation.progress > paused_progress and view.presentation.progress < paused_progress+0.02, "Focus return consumes only fresh caller time")
 var repeated_progress: float = view.presentation.progress
 view.handle_event(key(KEY_X))
 view.handle_event(key(KEY_X))
 check(view.presentation.progress == repeated_progress, "Repeated confirm does not restart or snap an opening")
 view._advance_presentation(1.5)
 check(view.presentation.state == &"presented" and view.box.cartridge_out, "Confirm completes opening then cartridge presentation")
 var source_basis: Basis = view.box.global_basis.inverse() * view.box.lid.get_parent().global_basis
 var base_normal: Vector3 = (source_basis * Vector3.UP).normalized()
 var lid_normal: Vector3 = (source_basis * (Basis(Vector3.BACK,deg_to_rad(view.BoxPresentation.OPEN_DEGREES)) * Vector3.DOWN)).normalized()
 var base_facing: Vector3 = view.pivot.basis * base_normal
 var lid_facing: Vector3 = view.pivot.basis * lid_normal
 check(base_facing.z > 0.7 and lid_facing.z > 0.7, "Confirmed orientation makes both original interior planes face camera")
 check(is_equal_approx(base_facing.z,lid_facing.z), "Presentation orientation comes from the two-plane bisector, not a guessed face preset")
 check(view.box == original_box and view.box.cartridge == original_cart and original_cart.get_parent() == original_parent, "Exact same box and cartridge retain their identity and parent")
 check(original_cart.basis.is_equal_approx(original_pose.basis), "Presentation preserves authored cartridge basis")
 var presented_pose: Transform3D = original_cart.transform
 view.confirm_selected()
 view._advance_presentation(5.0)
 check(original_cart.transform.is_equal_approx(presented_pose), "Repeated confirmation is idempotent when fully presented")
 var presented_angles := Vector2(view.yaw,view.pitch)
 await capture("03_presented_16x9")

 # Voluntary free giro and zoom remain available with no face selection API.
 view.rotate_inspection(Vector2(26,-17))
 check(not view.pivot.basis.is_equal_approx(initial_basis), "Voluntary rotation still works after presentation")
 check(not view.presentation_rotation_active, "Voluntary giro releases assisted confirm orientation")
 var rotated: Basis = view.pivot.basis
 view._advance_presentation(15.0)
 check(view.pivot.basis.is_equal_approx(rotated), "No autonomous rotation while idle")
 for window_size in [Vector2i(1152,648),Vector2i(1024,768),Vector2i(800,600)]:
  root.size = window_size
  await process_frame
  view.layout()
  await process_frame
  for zoom_value in [view.ZOOM_MIN,view.ZOOM_MAX]:
   view.zoom = zoom_value
   for angle in [Vector2(0,0),Vector2(0.8,0.4),Vector2(PI,PI*0.5),Vector2(4.0,2.0)]:
    view.yaw = angle.x
    view.pitch = angle.y
    view._apply_rotation()
    framed("%s zoom %.2f angle %s" % [window_size,zoom_value,angle])
  var screen := root.get_visible_rect()
  for button in view.all_buttons:
   if button.is_visible_in_tree(): check(screen.encloses(button.get_global_rect()), "%s visible footer remains onscreen" % window_size)
 root.size = Vector2i(1024,768)
 await process_frame
 view.yaw = presented_angles.x
 view.pitch = presented_angles.y
 view.zoom = 1.0
 view._apply_rotation()
 view.layout()
 await capture("04_presented_4x3")
 var center: Vector2 = view.viewport_container.get_global_rect().get_center()
 var overlap_button: Button = view.manual_button
 var saved_position: Vector2 = overlap_button.global_position
 overlap_button.global_position = center - overlap_button.size * 0.5
 check(not view.handle_event(point_event(MOUSE_BUTTON_LEFT,center)) and not view.dragging, "An overlapping real UI button cannot initiate model drag")
 var prior_zoom: float = view.zoom
 check(not view.handle_event(point_event(MOUSE_BUTTON_WHEEL_UP,center)) and view.zoom == prior_zoom, "Wheel over overlapping UI cannot zoom model")
 overlap_button.global_position = saved_position

 view.go_back()
 check(view.returning_to_carousel and view.approach_progress == 1.0, "Back begins stowing before camera retreat")
 view._advance_presentation(view.BoxPresentation.EXTRACT_SECONDS * 0.5)
 check(view.presentation.extraction_progress < 1.0 and view.presentation.extraction_progress > 0.0 and view.presentation.lid_angle == 115.0, "Return retracts cartridge while lid remains open")
 check(view.approach_progress == 1.0, "Camera waits until contents are safely stowed")
 view._advance_presentation(view.BoxPresentation.TOTAL_SECONDS)
 check(view.presentation.progress == 0.0 and view.approach_progress < 1.0, "Camera withdraws only after original cartridge and lid return")
 view._advance_presentation(view.APPROACH_SECONDS)
 check(not view.inspect_mode and exits == 0 and view.visible, "One Back safely returns to carousel, not out of library")
 check(original_cart.transform.is_equal_approx(original_pose), "Reversal restores exact cartridge transform without drift")
 view.navigate(1)
 check(view.current_index == 1, "Navigation rearms only after returning to carousel")
 scene.reduced_motion = true
 view.toggle_inspection()
 check(view.approach_progress == 1.0 and view.presentation.state == &"closed", "Reduced-motion inspection is immediate but remains closed")
 view.confirm_selected()
 check(view.presentation.state == &"presented", "Reduced-motion confirm reaches same valid endpoint")
 view.go_back()
 check(not view.inspect_mode and view.presentation.state == &"closed", "Reduced-motion Back restores safe carousel endpoint")
 scene.reduced_motion = false
 view.confirm_selected()
 view._advance_presentation(0.2)
 var focus_paused_approach: float = view.approach_progress
 scene._focus_lost()
 view._advance_presentation(20.0)
 check(view.approach_progress == focus_paused_approach and view.pending_confirm, "Focus loss during approach preserves pending confirm without advancing")
 scene._focus_returned()
 view.close()
 view._advance_presentation(20.0)
 check(not view.visible and not view.inspect_mode and view.presentation.state == &"closed", "Closing cancels all pending paths and restores hidden rig")
 view.open()
 check(view.presentation.state == &"closed" and view.approach_progress == 0.0, "Reopening cannot inherit an interrupted presentation")
 scene.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest))
 OS.set_environment("RETROPASS_BOX_ART_MANIFEST", "")
 var result := {"assertions":assertions,"passed":failures.is_empty(),"failures":failures,"mode":"real library with original rig; synthetic input; no emulation, Windows or physical controller claim"}
 print("LIBRARY_PRESENTATION_TESTS ",JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
