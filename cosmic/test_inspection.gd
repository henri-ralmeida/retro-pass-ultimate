extends SceneTree
## Deterministic checks for separate interactive 3D inspection.
## Run: godot --headless --path . --script cosmic/test_inspection.gd
## Not visual QA or a physical mouse/gamepad hardware test.

var failures: Array[String] = []
var assertions := 0
var emitted: Array[String] = []

func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok:
  failures.append(message)
  push_error(message)

func _initialize() -> void:
 run.call_deferred()

func _key(code: Key) -> InputEventKey:
 var event := InputEventKey.new()
 event.keycode = code
 event.pressed = true
 return event

func _mouse(button: MouseButton, pressed: bool, position: Vector2) -> InputEventMouseButton:
 var event := InputEventMouseButton.new()
 event.button_index = button
 event.pressed = pressed
 event.position = position
 event.global_position = position
 return event

func _motion(relative: Vector2, position: Vector2 = Vector2.ZERO) -> InputEventMouseMotion:
 var event := InputEventMouseMotion.new()
 event.relative = relative
 event.position = position
 event.global_position = position
 return event

func _gamepad_a() -> InputEventJoypadButton:
 var event := InputEventJoypadButton.new()
 event.button_index = JOY_BUTTON_A
 event.pressed = true
 return event

func _reset_state(scene: Node) -> bool:
 return is_zero_approx(scene.inspection_yaw) and is_zero_approx(scene.inspection_pitch) and is_equal_approx(scene.inspection_zoom, 1.0) and scene.inspection_pivot.rotation.is_zero_approx() and not scene.inspection_dragging

func _no_selection(scene: Node, message: String) -> void:
 check(scene.selection_count == 0 and emitted.is_empty(), message)

func _projected_bounds(scene: Node) -> Rect2:
 var low := Vector2(INF, INF)
 var high := Vector2(-INF, -INF)
 var center: Vector3 = scene.model_bounds.get_center()
 var viewport_size := Vector2(scene.viewport.size)
 for index in range(8):
  # model_bounds is expressed in the original presentation coordinates. The
  # centered pivot supplies the complete current rotation and world transform.
  var world_corner: Vector3 = scene.inspection_pivot.to_global(scene.model_bounds.get_endpoint(index) - center)
  var projected: Vector2 = scene.camera.unproject_position(world_corner) / viewport_size
  low = low.min(projected)
  high = high.max(projected)
 return Rect2(low, high - low)

func _check_max_zoom_framing(scene: Node, label: String) -> void:
 var bounds := _projected_bounds(scene)
 var margin := 0.035
 var clipped_in_depth := false
 for index in range(8):
  var world_corner: Vector3 = scene.inspection_pivot.to_global(scene.model_bounds.get_endpoint(index) - scene.model_bounds.get_center())
  var distance: float = -scene.camera.to_local(world_corner).z
  clipped_in_depth = clipped_in_depth or distance <= scene.camera.near or distance >= scene.camera.far
 var all_inside := bounds.position.x >= margin and bounds.position.y >= margin and bounds.end.x <= 1.0 - margin and bounds.end.y <= 1.0 - margin
 check(all_inside and not clipped_in_depth, "%s: all eight rotated corners remain visible with at least 3.5%% edge margin; projected=%s" % [label, bounds])
 var projected_center: Vector2 = scene.camera.unproject_position(scene.inspection_pivot.global_position) / Vector2(scene.viewport.size)
 check(projected_center.distance_to(Vector2(0.5, 0.5)) < 0.002, "%s: console center remains at viewport center" % label)
 var occupancy := maxf(bounds.size.x, bounds.size.y)
 check(occupancy >= 0.89 and occupancy <= 0.93, "%s: maximum zoom fills the viewport without shrinking or cropping; occupancy=%.4f" % [label, occupancy])

func run() -> void:
 root.size = Vector2i(1152, 648)
 var packed = load("res://cosmic/main.tscn")
 if packed == null:
  check(false, "Main scene loads")
  _finish()
  return
 var scene = packed.instantiate()
 scene.library_enabled = false # Standalone selector fixture; route covered by test_library.gd.
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene.set_scene_active(true)
 scene._focus_returned()
 scene.cooldown = 0.0
 scene.system_selected.connect(func(id): emitted.append(id))
 var contract_ok := true
 for method in ["rotate_inspection", "zoom_inspection", "reset_inspection", "close_inspection", "_inspection_input", "toggle_inspection"]:
  var exists: bool = scene.has_method(method)
  check(exists, "Inspection API provides " + method)
  contract_ok = contract_ok and exists
 var properties: Array[String] = []
 for property in scene.get_property_list(): properties.append(property.name)
 for property_name in ["inspect_mode", "inspection_dragging", "inspection_yaw", "inspection_pitch", "inspection_zoom", "inspection_pivot", "reset_button"]:
  var exists: bool = property_name in properties
  check(exists, "Inspection state provides " + property_name)
  contract_ok = contract_ok and exists
 if not contract_ok:
  scene.queue_free()
  await process_frame
  _finish()
  return

 check(not scene.inspect_mode and not scene.history_open, "Both inspection and history start closed")
 check(scene.reset_button is Button and not scene.reset_button.visible, "Reset is a real button hidden outside inspection")
 check(scene.inspection_pivot is Node3D and scene.model.get_parent() == scene.inspection_pivot, "Model is parented to its dedicated rotation pivot")
 check(scene.inspection_pivot.position.is_equal_approx(scene.model_bounds.get_center()), "Rotation pivot is centered on the model bounds")
 var initial_transform: Transform3D = scene.presentation.global_transform.affine_inverse() * scene.model.global_transform
 check(initial_transform.is_equal_approx(scene.systems[0].presentation_transform), "Introducing the pivot preserves the model's original presentation transform")
 scene.rotate_inspection(Vector2(100, 100))
 scene.zoom_inspection(0.3)
 check(_reset_state(scene), "Rotation and zoom do nothing outside inspection")

 # Inspecionar is a distinct, immediate 3D mode, not the historical text view.
 scene.inspect_button.pressed.emit()
 check(scene.inspect_mode and not scene.history_open, "Inspecionar opens 3D mode without history")
 check(scene.reset_button.visible, "Inspection exposes the reset button")
 check(not scene.system_logo.visible, "Inspection removes the logo from the manipulation area")
 check(scene.console_button.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Central selection button cannot intercept inspection drags")
 check("voltar" in scene.inspect_button.accessibility_name.to_lower(), "Inspection button becomes Voltar")
 check(_reset_state(scene), "Inspection begins at neutral orientation and zoom")
 _no_selection(scene, "Opening inspection never selects a system")

 # Rotation stays about the actual console center, with a full turn per axis.
 var center_before: Vector3 = scene.inspection_pivot.global_position
 var model_center_local: Vector3 = scene.model.to_local(center_before)
 var model_offset: Vector3 = scene.model.position
 scene.rotate_inspection(Vector2(50, 25))
 check(is_equal_approx(scene.inspection_yaw, 0.4) and is_equal_approx(scene.inspection_pitch, 0.2), "Pointer deltas rotate yaw and pitch independently")
 check(scene.inspection_pivot.global_position.is_equal_approx(center_before), "Rotation never translates the pivot")
 check(scene.model.to_global(model_center_local).is_equal_approx(center_before), "Console center remains fixed while rotating")
 check(scene.model.position.is_equal_approx(model_offset), "Rotation does not orbit by changing the model offset")
 scene.reset_inspection()
 scene.rotate_inspection(Vector2(TAU / 0.008, 0))
 check(scene.inspection_pivot.basis.is_equal_approx(Basis.IDENTITY), "A full yaw turn returns to the same orientation")
 scene.reset_inspection()
 scene.rotate_inspection(Vector2(0, TAU / 0.008))
 check(scene.inspection_pivot.basis.is_equal_approx(Basis.IDENTITY), "A full pitch turn returns to the same orientation")
 scene.reset_inspection()
 scene.rotate_inspection(Vector2((PI * 1.5) / 0.008, (PI * 1.5) / 0.008))
 check(is_equal_approx(scene.inspection_yaw, -PI * 0.5) and is_equal_approx(scene.inspection_pitch, -PI * 0.5), "Both axes wrap through 360 degrees rather than clamp at a half turn")
 scene.reset_inspection()
 check(_reset_state(scene), "Reset clears both rotation axes")

 # Zoom changes orthographic framing, with hard limits in both directions.
 var neutral_camera_size: float = scene.camera.size
 scene.zoom_inspection(0.2)
 check(is_equal_approx(scene.inspection_zoom, 1.2), "Zoom increments are applied")
 check(scene.camera.size < neutral_camera_size, "Zooming in narrows the camera framing")
 scene.zoom_inspection(100.0)
 check(is_equal_approx(scene.inspection_zoom, 1.35), "Zoom-in limit is 1.35")
 scene.zoom_inspection(-100.0)
 check(is_equal_approx(scene.inspection_zoom, 0.65), "Zoom-out limit is 0.65")
 check(scene.camera.size > neutral_camera_size, "Zooming out widens the camera framing")
 scene.reset_inspection()
 check(_reset_state(scene) and is_equal_approx(scene.camera.size, neutral_camera_size), "Reset restores neutral zoom and camera framing")

 # Independently project the transformed bounding box, rather than duplicating
 # the camera-size formula. Test upright, side, upside-down, and combined views
 # at maximum zoom across both supported aspect ratios and a wider window.
 var original_window_size: Vector2i = root.size
 var framing_angles: Array[Vector2] = [
  Vector2(0, 0), Vector2(PI * 0.25, 0), Vector2(PI * 0.5, 0),
  Vector2(PI, 0), Vector2(PI * 1.5, 0), Vector2(0, PI * 0.5),
  Vector2(0, PI), Vector2(0, PI * 1.5), Vector2(PI * 0.25, PI * 0.25),
  Vector2(PI * 0.5, PI * 0.5), Vector2(PI, PI * 0.25),
  Vector2(-PI * 0.37, PI * 0.61)
 ]
 for window_size in [Vector2i(1152, 648), Vector2i(1024, 768), Vector2i(1728, 720)]:
  root.size = window_size
  await process_frame
  scene._layout()
  await process_frame
  var viewport_size := Vector2(scene.viewport.size)
  check(viewport_size.x > 1 and viewport_size.y > 1, "%s: inspection viewport has valid dimensions" % window_size)
  var viewport_ratio: float = viewport_size.x / viewport_size.y
  var container_ratio: float = scene.viewport_container.size.x / scene.viewport_container.size.y
  check(absf(viewport_ratio - container_ratio) < 0.02, "%s: renderer and layout agree on the inspection aspect ratio" % window_size)
  scene.reset_inspection()
  var neutral_bounds := _projected_bounds(scene)
  var neutral_occupancy := maxf(neutral_bounds.size.x, neutral_bounds.size.y)
  check(neutral_occupancy >= 0.65 and neutral_occupancy <= 0.70, "%s: neutral inspection fills roughly two thirds of its viewport" % window_size)
  for angles in framing_angles:
   scene.reset_inspection()
   scene.rotate_inspection(angles / 0.008)
   scene.zoom_inspection(100.0)
   _check_max_zoom_framing(scene, "%s yaw=%.2f pitch=%.2f" % [window_size, angles.x, angles.y])
 root.size = original_window_size
 await process_frame
 scene.reset_inspection()
 scene._layout()
 await process_frame

 # Mouse dragging requires a press in the console area and ends on any release.
 var inside: Vector2 = scene.viewport_container.get_global_rect().get_center()
 var outside := Vector2(-100, -100)
 scene._input(_motion(Vector2(40, 30), inside))
 check(_reset_state(scene), "Pointer movement without a pressed drag does not rotate")
 scene._input(_mouse(MOUSE_BUTTON_LEFT, true, inside))
 check(scene.inspection_dragging, "Press inside the console starts dragging")
 scene._input(_motion(Vector2(40, 30), inside))
 check(not is_zero_approx(scene.inspection_yaw) and not is_zero_approx(scene.inspection_pitch), "Dragging turns both axes")
 var yaw_before: float = scene.inspection_yaw
 scene._input(_motion(Vector2(10, 0), outside))
 check(not is_equal_approx(scene.inspection_yaw, yaw_before), "An active drag remains captured outside the viewport")
 scene._input(_mouse(MOUSE_BUTTON_LEFT, false, outside))
 check(not scene.inspection_dragging, "Releasing outside the viewport ends the drag")
 yaw_before = scene.inspection_yaw
 scene._input(_motion(Vector2(100, 100), inside))
 check(is_equal_approx(scene.inspection_yaw, yaw_before), "Later pointer movement does not resume a released drag")
 _no_selection(scene, "Dragging and releasing never select")
 scene.reset_inspection()
 scene._input(_mouse(MOUSE_BUTTON_WHEEL_UP, true, inside))
 check(scene.inspection_zoom > 1.0, "Wheel up over console zooms in")
 scene._input(_mouse(MOUSE_BUTTON_WHEEL_DOWN, true, inside))
 check(is_equal_approx(scene.inspection_zoom, 1.0), "Wheel down over console zooms out")

 # Footer UI never starts a drag or applies wheel zoom to the console.
 await process_frame
 for control in [scene.inspect_button, scene.motion_button, scene.reset_button]:
  var ui_position: Vector2 = control.get_global_rect().get_center()
  check(not scene.viewport_container.get_global_rect().has_point(ui_position), "%s is outside the 3D interaction area" % control.name)
  var handled: bool = scene._inspection_input(_mouse(MOUSE_BUTTON_LEFT, true, ui_position))
  check(not handled and not scene.inspection_dragging, "%s click is excluded from console dragging" % control.name)
  handled = scene._inspection_input(_mouse(MOUSE_BUTTON_WHEEL_UP, true, ui_position))
  check(not handled and is_equal_approx(scene.inspection_zoom, 1.0), "%s wheel interaction is excluded from console zoom" % control.name)
 _no_selection(scene, "Footer exclusion checks never select")

 # Keyboard alternatives and explicit reset are equivalent to mouse controls.
 scene._input(_key(KEY_RIGHT))
 scene._input(_key(KEY_DOWN))
 check(scene.inspection_yaw > 0.0 and scene.inspection_pitch > 0.0, "Right and Down rotate the console")
 scene._input(_key(KEY_LEFT))
 scene._input(_key(KEY_UP))
 check(is_zero_approx(scene.inspection_yaw) and is_zero_approx(scene.inspection_pitch), "Opposite arrow keys reverse rotation")
 scene._input(_key(KEY_PLUS))
 check(scene.inspection_zoom > 1.0, "Plus key zooms in")
 scene._input(_key(KEY_MINUS))
 check(is_equal_approx(scene.inspection_zoom, 1.0), "Minus key zooms out")
 scene.rotate_inspection(Vector2(50, 50))
 scene.zoom_inspection(0.2)
 scene._input(_key(KEY_R))
 check(_reset_state(scene), "R restores neutral angle and zoom")
 scene.rotate_inspection(Vector2(50, 50))
 scene.zoom_inspection(0.2)
 scene.inspection_dragging = true
 scene.reset_button.pressed.emit()
 check(_reset_state(scene), "Restaurar button resets angles, zoom, and drag capture")
 scene.rotate_inspection(Vector2(50, 50))
 scene.zoom_inspection(0.2)
 scene.reset_button.grab_focus()
 scene._input(_gamepad_a())
 check(_reset_state(scene), "Gamepad A on Restaurar activates the focused reset button")
 scene.reset_inspection()

 # Exercise the normal viewport input path too, including GUI button dispatch.
 root.push_input(_motion(Vector2.ZERO, inside), true)
 root.push_input(_mouse(MOUSE_BUTTON_LEFT, true, inside), true)
 root.push_input(_motion(Vector2(30, -20), inside + Vector2(30, -20)), true)
 root.push_input(_mouse(MOUSE_BUTTON_LEFT, false, outside), true)
 check(not is_zero_approx(scene.inspection_yaw) and not is_zero_approx(scene.inspection_pitch) and not scene.inspection_dragging, "Real viewport input starts, rotates, and releases a drag")
 scene.zoom_inspection(0.2)
 var reset_position: Vector2 = scene.reset_button.get_global_rect().get_center()
 root.push_input(_motion(Vector2.ZERO, reset_position), true)
 root.push_input(_mouse(MOUSE_BUTTON_LEFT, true, reset_position), true)
 root.push_input(_mouse(MOUSE_BUTTON_LEFT, false, reset_position), true)
 await process_frame
 check(_reset_state(scene), "Real pointer click on Restaurar reaches the GUI and resets the model")
 _no_selection(scene, "Real viewport drag and reset click never select")

 # Inspection blocks all automatic history, navigation, and selection paths.
 scene.auto_history_armed = true
 scene.console_button.grab_focus()
 scene.hovering = true
 scene._advance_dwell(30.0)
 check(scene.inspect_mode and not scene.history_open and is_zero_approx(scene.dwell_elapsed), "Long console dwell cannot interrupt active inspection")
 scene.open_history(false)
 check(scene.inspect_mode and not scene.history_open, "Direct history opening cannot overlay active inspection")
 var fixture = scene.systems[0].duplicate()
 fixture.system_id = "inspection_navigation_fixture"
 scene.systems.append(fixture)
 scene.navigate(1)
 check(scene.current_index == 0 and not scene.transition_busy, "Catalog navigation is blocked during inspection")
 scene.systems.pop_back()
 scene.cooldown = 0.0
 scene.confirm_selection("inspection_guard")
 scene.console_button.pressed.emit()
 scene._input(_key(KEY_ENTER))
 scene._input(_gamepad_a())
 _no_selection(scene, "Inspection blocks API, click, Enter, and focused-console gamepad selection")

 # Reduced motion stops automatic movement but still allows intentional input.
 if not scene.reduced_motion: scene.toggle_motion()
 var elapsed_before: float = scene.elapsed
 scene.rotate_inspection(Vector2(25, 25))
 scene.zoom_inspection(0.1)
 scene._process(1.0)
 check(not is_zero_approx(scene.inspection_yaw) and scene.inspection_zoom > 1.0, "Reduced motion still permits deliberate rotation and zoom")
 check(is_equal_approx(scene.elapsed, elapsed_before), "Reduced motion freezes automatic animation time")
 check(scene.presentation.position.is_zero_approx(), "Inspection has no floating translation in reduced motion")
 scene.toggle_motion()
 scene._process(1.0)
 check(scene.presentation.position.is_zero_approx(), "Inspection also suppresses floating with regular motion enabled")

 # Losing focus or pausing cancels drag and ignores further input until active.
 scene.reset_inspection()
 scene._input(_mouse(MOUSE_BUTTON_LEFT, true, inside))
 scene._input(_motion(Vector2(20, 10), inside))
 yaw_before = scene.inspection_yaw
 var zoom_before: float = scene.inspection_zoom
 scene._focus_lost()
 check(not scene.inspection_dragging, "Window focus loss cancels drag capture")
 scene._input(_motion(Vector2(100, 100), inside))
 scene._input(_mouse(MOUSE_BUTTON_WHEEL_UP, true, inside))
 scene._input(_key(KEY_RIGHT))
 check(is_equal_approx(scene.inspection_yaw, yaw_before) and is_equal_approx(scene.inspection_zoom, zoom_before), "Unfocused scene ignores rotation and zoom inputs")
 scene._focus_returned()
 scene._input(_motion(Vector2(100, 100), inside))
 check(is_equal_approx(scene.inspection_yaw, yaw_before), "Returning focus does not revive a stale drag")
 scene._input(_mouse(MOUSE_BUTTON_LEFT, true, inside))
 scene._input(_motion(Vector2(20, 0), inside))
 check(not is_equal_approx(scene.inspection_yaw, yaw_before), "A fresh press after focus return can drag again")
 yaw_before = scene.inspection_yaw
 scene.set_scene_active(false)
 check(not scene.inspection_dragging, "Scene deactivation cancels drag capture")
 scene._input(_motion(Vector2(100, 100), inside))
 scene._input(_key(KEY_RIGHT))
 check(is_equal_approx(scene.inspection_yaw, yaw_before), "Inactive scene ignores manipulation")
 scene.set_scene_active(true)
 scene._input(_motion(Vector2(100, 100), inside))
 check(is_equal_approx(scene.inspection_yaw, yaw_before), "Scene reactivation does not revive a stale drag")

 # Escape and I restore the selection presentation without reopening history.
 scene._input(_key(KEY_ESCAPE))
 check(not scene.inspect_mode and not scene.history_open, "Escape closes only inspection")
 check(_reset_state(scene), "Closing inspection resets angle, zoom, and drag")
 check(not scene.reset_button.visible and scene.system_logo.visible, "Closing restores the normal logo and footer")
 check(scene.console_button.mouse_filter == Control.MOUSE_FILTER_STOP, "Closing restores deliberate central click selection")
 check(scene.console_button.has_focus(), "Closing restores focus to the console")
 scene._advance_dwell(30.0)
 check(not scene.history_open and not scene.auto_history_armed, "Closing inspection cannot immediately open automatic history")
 scene._input(_key(KEY_I))
 check(scene.inspect_mode and not scene.history_open and _reset_state(scene), "I reopens clean 3D inspection")
 scene._input(_key(KEY_I))
 check(not scene.inspect_mode and not scene.history_open, "I also closes 3D inspection")
 _no_selection(scene, "The complete inspection workflow never selects a system")

 # Switching explicitly from history to 3D does not leave a text overlay/tween.
 scene.open_history(false)
 check(scene.history_open and not scene.inspect_mode, "Manual history remains a separate informational view")
 scene.toggle_inspection()
 check(scene.inspect_mode and not scene.history_open, "Explicit inspection switches from history to 3D")
 check(is_zero_approx(scene.history_blend) and not scene.history_panel.visible, "Switching removes the historical panel immediately")
 check(not scene.history_transition or not scene.history_transition.is_running(), "Switching does not leave a historical slide tween running")
 scene.close_inspection()
 scene.set_scene_active(false)
 scene.toggle_inspection()
 check(not scene.inspect_mode, "Inactive scene cannot enter inspection")
 scene.set_scene_active(true)
 scene._focus_lost()
 scene.toggle_inspection()
 check(not scene.inspect_mode, "Unfocused scene cannot enter inspection")

 scene.queue_free()
 await process_frame
 _finish()

func _finish() -> void:
 var result := {
  "assertions": assertions,
  "failures": failures,
  "passed": failures.is_empty(),
  "engine": Engine.get_version_info().string,
  "mode": "headless deterministic 3D inspection behavior; NOT visual or physical-controller QA"
 }
 DirAccess.make_dir_recursive_absolute("res://evidence/cosmic")
 var file = FileAccess.open("res://evidence/cosmic/inspection_tests.json", FileAccess.WRITE)
 if file: file.store_string(JSON.stringify(result, "  "))
 else: push_error("Could not write inspection_tests.json: " + error_string(FileAccess.get_open_error()))
 print("COSMIC_INSPECTION_TESTS ", JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
