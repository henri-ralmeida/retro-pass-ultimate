extends SceneTree
## Deterministic stress/regression coverage for inspection zoom.
## Run: godot --headless --path . --script cosmic/test_zoom_stress.gd
## This checks geometry, state, and synthetic input, NOT rendered pixels,
## physical mouse hardware, GPU/driver behavior, or absence of aliasing.

const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1152, 648), Vector2i(1024, 768), Vector2i(2560, 1080)]
const ZOOM_LEVELS: Array[float] = [0.65, 1.0, 1.35]
const ROTATION_STEPS := 24
const INPUT_REPEATS := 128
const CYCLES := 24
const MIN_EDGE_MARGIN := 0.035

var failures: Array[String] = []
var failure_count := 0
var assertions := 0
var geometry_states := 0
var synthetic_events := 0
var emitted: Array[String] = []
var meshes: Array[Node] = []
var model_transform := Transform3D.IDENTITY
var minimum_edge_margin := INF
var minimum_mesh_occupancy := INF
var minimum_near_clearance := INF
var maximum_mesh_occupancy := 0.0
var started_usec := 0
var sections: Dictionary = {}
var main_sha256 := ""

func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok:
  failure_count += 1
  if failures.size() < 200:
   failures.append(message)
   push_error(message)

func _initialize() -> void:
 run.call_deferred()

func _key(code: Key, echo: bool = false, pressed: bool = true) -> InputEventKey:
 var event := InputEventKey.new()
 event.keycode = code
 event.pressed = pressed
 event.echo = echo
 return event

func _mouse(button: MouseButton, pressed: bool, position: Vector2) -> InputEventMouseButton:
 var event := InputEventMouseButton.new()
 event.button_index = button
 event.pressed = pressed
 event.position = position
 event.global_position = position
 return event

func _motion(relative: Vector2, position: Vector2) -> InputEventMouseMotion:
 var event := InputEventMouseMotion.new()
 event.relative = relative
 event.position = position
 event.global_position = position
 return event

func _send(event: InputEvent) -> void:
 synthetic_events += 1
 root.push_input(event, true)

func _neutral(scene: Node) -> bool:
 return is_zero_approx(scene.inspection_yaw) and is_zero_approx(scene.inspection_pitch) and is_equal_approx(scene.inspection_zoom, 1.0) and scene.inspection_pivot.rotation.is_zero_approx() and not scene.inspection_dragging

func _pose(scene: Node) -> Vector3:
 return Vector3(scene.inspection_yaw, scene.inspection_pitch, scene.inspection_zoom)

func _project(scene: Node, world_points: PackedVector3Array) -> Dictionary:
 var low := Vector2(INF, INF)
 var high := Vector2(-INF, -INF)
 var all_finite := true
 var all_in_depth := true
 var min_near_clearance := INF
 var viewport_size := Vector2(scene.viewport.size)
 for point in world_points:
  var projected: Vector2 = scene.camera.unproject_position(point) / viewport_size
  var depth: float = -scene.camera.to_local(point).z
  all_finite = all_finite and point.is_finite() and projected.is_finite() and is_finite(depth)
  all_in_depth = all_in_depth and depth > scene.camera.near and depth < scene.camera.far and not scene.camera.is_position_behind(point)
  min_near_clearance = minf(min_near_clearance, depth - scene.camera.near)
  low = low.min(projected)
  high = high.max(projected)
 return {"bounds": Rect2(low, high - low), "finite": all_finite, "depth": all_in_depth, "near_clearance": min_near_clearance}

func _health(scene: Node, label: String, expected_zoom: float = -1.0) -> void:
 geometry_states += 1
 var viewport_size := Vector2(scene.viewport.size)
 check(viewport_size.x > 1 and viewport_size.y > 1 and viewport_size.is_finite(), label + ": valid viewport")
 check(is_finite(scene.inspection_zoom) and is_finite(scene.inspection_yaw) and is_finite(scene.inspection_pitch) and is_finite(scene.camera.size) and scene.camera.size > 0.0, label + ": no NaN/infinity or collapsed camera")
 check(scene.inspection_zoom >= 0.65 and scene.inspection_zoom <= 1.35, label + ": useful zoom limits preserved")
 if expected_zoom >= 0:
  check(is_equal_approx(scene.inspection_zoom, expected_zoom), label + ": requested zoom retained")
 check(absf(scene.inspection_yaw) <= PI + 0.00001 and absf(scene.inspection_pitch) <= PI + 0.00001, label + ": rotation remains wrapped")
 check(scene.model.transform.is_equal_approx(model_transform) and scene.presentation.scale.is_equal_approx(Vector3.ONE) and scene.inspection_pivot.scale.is_equal_approx(Vector3.ONE), label + ": zoom never shrinks, translates, or distorts the model")
 check(scene.model.is_visible_in_tree() and scene.viewport_container.is_visible_in_tree() and scene.camera.is_current(), label + ": model, container, and camera remain active")
 check(scene.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, label + ": visible viewport remains updating")

 # Project eight enclosing-box corners through Camera3D, independently of the
 # framing formula. They must keep useful occupancy, not merely stay on screen.
 var enclosing_points := PackedVector3Array()
 for index in range(8):
  enclosing_points.append(scene.inspection_pivot.to_global(scene.model_bounds.get_endpoint(index) - scene.model_bounds.get_center()))
 var enclosing := _project(scene, enclosing_points)
 var bounds: Rect2 = enclosing.bounds
 var occupancy: float = maxf(bounds.size.x, bounds.size.y)
 var margin: float = minf(minf(bounds.position.x, bounds.position.y), minf(1.0 - bounds.end.x, 1.0 - bounds.end.y))
 minimum_edge_margin = minf(minimum_edge_margin, margin)
 check(enclosing.finite and enclosing.depth, label + ": enclosing box is finite and outside near/far clipping planes")
 check(margin >= MIN_EDGE_MARGIN, "%s: enclosing box keeps 3.5%% margin; bounds=%s" % [label, bounds])
 # Independent acceptance bands preserve visibly useful framing at each limit.
 if is_equal_approx(scene.inspection_zoom, 0.65):
  check(occupancy >= 0.42 and occupancy <= 0.46, "%s: minimum zoom is still useful, occupancy=%.5f" % [label, occupancy])
 elif is_equal_approx(scene.inspection_zoom, 1.0):
  check(occupancy >= 0.65 and occupancy <= 0.70, "%s: neutral framing preserved, occupancy=%.5f" % [label, occupancy])
 elif is_equal_approx(scene.inspection_zoom, 1.35):
  check(occupancy >= 0.89 and occupancy <= 0.93, "%s: maximum zoom stays large without clipping, occupancy=%.5f" % [label, occupancy])
 var center: Vector2 = scene.camera.unproject_position(scene.inspection_pivot.global_position) / viewport_size
 check(center.is_finite() and center.distance_to(Vector2(0.5, 0.5)) < 0.002, label + ": model pivot remains centered")

 # Do not trust model_bounds alone: inspect every actual visible mesh's local
 # AABB in its own global transform, including imported children/transforms.
 var actual_points := PackedVector3Array()
 var visible_meshes := 0
 for mesh in meshes:
  if not mesh.is_visible_in_tree(): continue
  visible_meshes += 1
  var mesh_box: AABB = mesh.get_aabb()
  for index in range(8): actual_points.append(mesh.to_global(mesh_box.get_endpoint(index)))
 var actual := _project(scene, actual_points)
 var actual_bounds: Rect2 = actual.bounds
 var actual_occupancy: float = maxf(actual_bounds.size.x, actual_bounds.size.y)
 minimum_mesh_occupancy = minf(minimum_mesh_occupancy, actual_occupancy)
 maximum_mesh_occupancy = maxf(maximum_mesh_occupancy, actual_occupancy)
 minimum_near_clearance = minf(minimum_near_clearance, actual.near_clearance)
 check(visible_meshes > 0 and actual.finite and actual.depth, label + ": real mesh geometry is finite, present, and inside depth range")
 check(actual_bounds.position.x >= MIN_EDGE_MARGIN and actual_bounds.position.y >= MIN_EDGE_MARGIN and actual_bounds.end.x <= 1.0 - MIN_EDGE_MARGIN and actual_bounds.end.y <= 1.0 - MIN_EDGE_MARGIN, "%s: real mesh corners stay inside viewport; bounds=%s" % [label, actual_bounds])
 check(actual_occupancy > 0.20 and actual_bounds.size.x > 0.015 and actual_bounds.size.y > 0.015, label + ": real mesh has nontrivial on-screen extent")
 check(scene.selection_count == 0 and emitted.is_empty(), label + ": no accidental system selection")

func _rotation_grid(scene: Node) -> void:
 var before := assertions
 for window_size in WINDOW_SIZES:
  root.size = window_size
  await process_frame
  scene._layout()
  await process_frame
  var ratio: float = float(scene.viewport.size.x) / scene.viewport.size.y
  var layout_ratio: float = scene.viewport_container.size.x / scene.viewport_container.size.y
  check(absf(ratio - layout_ratio) < 0.02, "%s: actual viewport follows aspect ratio" % window_size)
  for yaw_step in range(ROTATION_STEPS):
   for pitch_step in range(ROTATION_STEPS):
    scene.reset_inspection()
    var angles := Vector2(TAU * yaw_step / ROTATION_STEPS, TAU * pitch_step / ROTATION_STEPS)
    scene.rotate_inspection(angles / 0.008)
    for target_zoom in ZOOM_LEVELS:
     scene.zoom_inspection(target_zoom - scene.inspection_zoom)
     _health(scene, "%s grid(%d,%d) zoom=%.2f" % [window_size, yaw_step, pitch_step, target_zoom], target_zoom)
  print("ZOOM_STRESS_GRID ", window_size, " complete: ", geometry_states, " geometry states")
 sections.rotation_grid = assertions - before

func _extreme_finite_input(scene: Node) -> void:
 var before := assertions
 # Huge but finite deltas and very small deltas exercise wrapping/accumulation
 # without inventing NaN/INF input that real pointer/keyboard events cannot send.
 for delta in [Vector2(1e9, -1e9), Vector2(-1e12, 1e12), Vector2(0.000001, -0.000001), Vector2(PI / 0.008, -PI / 0.008), Vector2(TAU * 10000 / 0.008, -TAU * 10000 / 0.008)]:
  for zoom in ZOOM_LEVELS:
   scene.reset_inspection()
   scene.rotate_inspection(delta)
   scene.zoom_inspection(zoom - 1.0)
   _health(scene, "extreme finite delta=%s zoom=%.2f" % [delta, zoom], zoom)
 for amount in [1e12, -1e12, 1e20, -1e20]:
  scene.zoom_inspection(amount)
  _health(scene, "extreme finite zoom delta=%s" % amount, 1.35 if amount > 0 else 0.65)
 scene.reset_inspection()
 check(_neutral(scene), "Reset recovers neutral pose after extreme finite input")
 sections.extreme_finite_input = assertions - before

func _repeated_input(scene: Node) -> void:
 var before := assertions
 var inside: Vector2 = scene.viewport_container.get_global_rect().get_center()
 for wheel in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
  scene.reset_inspection()
  for step in range(INPUT_REPEATS):
   _send(_mouse(wheel, true, inside))
   _send(_mouse(wheel, false, inside))
   if step % 8 == 0: _health(scene, "repeated wheel=%d step=%d" % [wheel, step])
  _health(scene, "wheel clamp=%d" % wheel, 1.35 if wheel == MOUSE_BUTTON_WHEEL_UP else 0.65)
 for code in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
  scene.reset_inspection()
  for step in range(INPUT_REPEATS):
   _send(_key(code, step > 0))
   if step % 8 == 0: _health(scene, "repeated key=%d step=%d" % [code, step])
  var expected := 0.65 if code in [KEY_MINUS, KEY_KP_SUBTRACT] else 1.35
  _health(scene, "key clamp=%d" % code, expected)
  var pose_before := _pose(scene)
  _send(_key(code, false, false))
  check(_pose(scene).is_equal_approx(pose_before), "Key release does not apply another zoom step")
 scene.reset_inspection()
 for step in range(512):
  _send(_key(KEY_PLUS))
  _send(_mouse(MOUSE_BUTTON_WHEEL_DOWN, true, inside))
  _send(_mouse(MOUSE_BUTTON_WHEEL_UP, true, inside))
  _send(_key(KEY_MINUS))
  if step % 16 == 0: _health(scene, "alternating keyboard/wheel step=%d" % step, 1.0)
 check(is_equal_approx(scene.inspection_zoom, 1.0), "Alternating wheel and keyboard inputs do not accumulate zoom drift")
 sections.repeated_input = assertions - before

func _interrupted_input(scene: Node) -> void:
 var before := assertions
 for target_zoom in ZOOM_LEVELS:
  scene.reset_inspection()
  scene.rotate_inspection(Vector2(233, -159))
  scene.zoom_inspection(target_zoom - 1.0)
  var inside: Vector2 = scene.viewport_container.get_global_rect().get_center()
  # Outside the console but still inside the window. A negative coordinate
  # is outside the Window itself, where cancellation (not capture) is correct.
  var outside := Vector2(5, 5)
  _send(_mouse(MOUSE_BUTTON_LEFT, true, inside))
  check(scene.inspection_dragging, "Focus-loss fixture has a live drag")
  root.focus_exited.emit()
  check(not scene.inspection_dragging and not scene.application_focused, "Window focus-exited signal cancels drag")
  var pose_before := _pose(scene)
  for step in range(32):
   _send(_motion(Vector2(50, -20), inside))
   _send(_mouse(MOUSE_BUTTON_WHEEL_UP, true, inside))
   _send(_key(KEY_MINUS, true))
  check(_pose(scene).is_equal_approx(pose_before), "Unfocused repeated input cannot mutate pose")
  _health(scene, "focus lost zoom=%.2f" % target_zoom, target_zoom)
  root.focus_entered.emit()
  _send(_motion(Vector2(90, 110), inside))
  check(not scene.inspection_dragging and _pose(scene).is_equal_approx(pose_before), "Focus return does not resurrect stale dragging")
  _health(scene, "focus returned zoom=%.2f" % target_zoom, target_zoom)

  _send(_mouse(MOUSE_BUTTON_LEFT, true, inside))
  _send(_motion(Vector2(30, 40), outside))
  check(scene.inspection_dragging and not _pose(scene).is_equal_approx(pose_before), "Captured drag can move beyond the console rectangle")
  _send(_mouse(MOUSE_BUTTON_LEFT, false, outside))
  pose_before = _pose(scene)
  for step in range(32):
   _send(_mouse(MOUSE_BUTTON_WHEEL_UP, true, outside))
   _send(_mouse(MOUSE_BUTTON_LEFT, true, outside))
   _send(_motion(Vector2(30, 40), outside))
   _send(_mouse(MOUSE_BUTTON_LEFT, false, outside))
  check(not scene.inspection_dragging and _pose(scene).is_equal_approx(pose_before), "Outside press/wheel/motion cannot start drag or zoom")
  _send(_mouse(MOUSE_BUTTON_LEFT, true, inside))
  root.mouse_exited.emit()
  _send(_motion(Vector2(30, 40), inside))
  check(not scene.inspection_dragging and _pose(scene).is_equal_approx(pose_before), "Leaving and reentering the window never leaves a stuck drag")
  _health(scene, "pointer exit zoom=%.2f" % target_zoom, target_zoom)

  _send(_mouse(MOUSE_BUTTON_LEFT, true, inside))
  scene.set_scene_active(false)
  _send(_key(KEY_PLUS))
  _send(_motion(Vector2(30, 40), inside))
  check(not scene.inspection_dragging and _pose(scene).is_equal_approx(pose_before), "Deactivation cancels drag and ignores zoom/motion")
  check(scene.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Only inactive scene disables rendering")
  scene.set_scene_active(true)
  _send(_motion(Vector2(30, 40), inside))
  check(not scene.inspection_dragging and _pose(scene).is_equal_approx(pose_before), "Reactivation requires a fresh press")
  _health(scene, "reactivated zoom=%.2f" % target_zoom, target_zoom)
  _send(_mouse(MOUSE_BUTTON_LEFT, true, inside))
  _send(_motion(Vector2(12, -9), inside))
  _send(_mouse(MOUSE_BUTTON_LEFT, false, outside))
  check(not scene.inspection_dragging and not _pose(scene).is_equal_approx(pose_before), "Fresh drag works after all interruptions")
  _health(scene, "fresh drag after interruptions", target_zoom)
 sections.interrupted_input = assertions - before

func _history_cycles(scene: Node) -> void:
 var before := assertions
 for cycle in range(CYCLES):
  scene.reset_inspection()
  scene.rotate_inspection(Vector2(cycle * 121.7, cycle * -93.1))
  scene.zoom_inspection(100.0 if cycle % 2 == 0 else -100.0)
  var inside: Vector2 = scene.viewport_container.get_global_rect().get_center()
  _send(_mouse(MOUSE_BUTTON_LEFT, true, inside))
  _send(_key(KEY_ESCAPE if cycle % 2 == 0 else KEY_I))
  check(not scene.inspect_mode and not scene.inspection_dragging and _neutral(scene), "Cycle %d: exit clears zoom, rotation, and dragging" % cycle)
  scene.open_history(false)
  check(scene.history_open and not scene.inspect_mode, "Cycle %d: history opens separately" % cycle)
  if scene.history_transition: scene.history_transition.custom_step(0.2)
  scene._layout()
  root.focus_exited.emit()
  root.focus_entered.emit()
  _send(_key(KEY_I))
  check(scene.inspect_mode and not scene.history_open and _neutral(scene), "Cycle %d: history switches to fresh inspection" % cycle)
  check(not scene.history_panel.visible and is_zero_approx(scene.history_blend), "Cycle %d: no history overlay remains" % cycle)
  check(not scene.history_transition or not scene.history_transition.is_running(), "Cycle %d: no competing history tween remains" % cycle)
  await process_frame
  # A stale tween must not reappear on a subsequent frame or after a resize.
  root.size = WINDOW_SIZES[cycle % WINDOW_SIZES.size()]
  await process_frame
  scene._layout()
  await process_frame
  scene.zoom_inspection(100.0)
  _health(scene, "history/inspection cycle=%d" % cycle, 1.35)
  check(not scene.history_panel.visible and is_zero_approx(scene.history_blend), "Cycle %d: history stays closed after frame/resize" % cycle)
  if cycle % 3 == 0: scene.toggle_motion()
 sections.history_cycles = assertions - before

func _resize_while_dragging(scene: Node) -> void:
 var before := assertions
 for cycle in range(18):
  scene.reset_inspection()
  scene.zoom_inspection(100.0)
  var inside: Vector2 = scene.viewport_container.get_global_rect().get_center()
  _send(_mouse(MOUSE_BUTTON_LEFT, true, inside))
  _send(_motion(Vector2(50 * cycle, -71 * cycle), inside))
  root.size = WINDOW_SIZES[cycle % WINDOW_SIZES.size()]
  await process_frame
  scene._layout()
  await process_frame
  _health(scene, "resize while dragging=%d" % cycle, 1.35)
  _send(_mouse(MOUSE_BUTTON_LEFT, false, Vector2(-100, -100)))
  check(not scene.inspection_dragging, "Resize does not prevent outside release")
 sections.resize_while_dragging = assertions - before

func run() -> void:
 started_usec = Time.get_ticks_usec()
 main_sha256 = FileAccess.get_sha256("res://cosmic/main.gd")
 root.size = WINDOW_SIZES[0]
 var packed = load("res://cosmic/main.tscn")
 if packed == null:
  check(false, "Main scene loads")
  _finish()
  return
 var scene = packed.instantiate()
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene.set_scene_active(true)
 scene._focus_returned()
 scene.cooldown = 0.0
 scene.system_selected.connect(func(id): emitted.append(id))
 meshes = scene.model.find_children("*", "MeshInstance3D", true, false)
 model_transform = scene.model.transform
 check(not meshes.is_empty(), "Real console meshes exist for independent geometry checks")
 scene.toggle_inspection()
 await process_frame
 await _rotation_grid(scene)
 _extreme_finite_input(scene)
 _repeated_input(scene)
 _interrupted_input(scene)
 await _history_cycles(scene)
 await _resize_while_dragging(scene)
 scene.reset_inspection()
 _health(scene, "final reset", 1.0)
 check(_neutral(scene), "Final reset restores a usable neutral inspection")
 scene.close_inspection()
 check(not scene.inspect_mode and not scene.history_open and _neutral(scene), "Final exit leaves a clean selection screen")
 check(scene.selection_count == 0 and emitted.is_empty(), "Entire stress sequence makes no accidental selection")
 check(FileAccess.get_sha256("res://cosmic/main.gd") == main_sha256, "Source under test did not change during the run")
 scene.queue_free()
 await process_frame
 _finish()

func _finish() -> void:
 var result := {
  "assertions": assertions,
  "failure_count": failure_count,
  "failures": failures,
  "passed": failure_count == 0,
  "engine": Engine.get_version_info().string,
  "main_gd_sha256": main_sha256,
  "duration_seconds": (Time.get_ticks_usec() - started_usec) / 1000000.0,
  "mode": "headless deterministic geometry/state/synthetic-input QA; NOT visual pixels, physical hardware, GPU, or aliasing QA",
  "rotation_grid": "24 yaw x 24 pitch x 3 zoom levels x 3 aspect ratios = 5184 geometry states",
  "window_sizes": ["1152x648 (16:9)", "1024x768 (4:3)", "2560x1080 (ultrawide)"],
  "zoom_limits": [0.65, 1.35],
  "geometry_states": geometry_states,
  "synthetic_input_events": synthetic_events,
  "mesh_count": meshes.size(),
  "minimum_edge_margin": minimum_edge_margin,
  "minimum_mesh_occupancy": minimum_mesh_occupancy,
  "maximum_mesh_occupancy": maximum_mesh_occupancy,
  "minimum_near_clearance": minimum_near_clearance,
  "sections": sections
 }
 DirAccess.make_dir_recursive_absolute("res://evidence/cosmic")
 var file := FileAccess.open("res://evidence/cosmic/zoom_stress_tests.json", FileAccess.WRITE)
 if file: file.store_string(JSON.stringify(result, "  "))
 else: push_error("Could not write zoom_stress_tests.json: " + error_string(FileAccess.get_open_error()))
 print("COSMIC_ZOOM_STRESS_TESTS ", JSON.stringify(result))
 quit(0 if failure_count == 0 else 1)
