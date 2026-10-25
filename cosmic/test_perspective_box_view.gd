extends SceneTree
## Deterministic render-projection/lifecycle tests, not visual or controller QA.
## Run: godot --headless --path . --script cosmic/test_perspective_box_view.gd

const BoxView := preload("res://cosmic/perspective_box_view.gd")
var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		push_error(message)

func projected_bounds(view: Control, named_mesh: String = "") -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for mesh in view.box.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or not mesh.mesh or (not named_mesh.is_empty() and mesh.name != named_mesh):
			continue
		for surface in mesh.mesh.get_surface_count():
			for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var pixel: Vector2 = view.camera.unproject_position(mesh.global_transform * vertex)
				low = low.min(pixel)
				high = high.max(pixel)
	return Rect2(low, high - low)

func run() -> void:
	var console_world := Node3D.new()
	root.add_child(console_world)
	var console_camera := Camera3D.new()
	console_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	console_camera.size = 10.0
	console_camera.position = Vector3(3.0, 4.0, 5.0)
	console_world.add_child(console_camera)
	console_camera.current = true
	var original_camera_transform := console_camera.transform
	var item := {"id": "neutral_projection_test", "title": "Neutral projection test", "cover_front": "", "cover_back": "", "cover_spine": ""}
	var view := BoxView.new()
	view.set_active(true)
	view.set_frame(Rect2(31.0, 47.0, 420.0, 400.0))
	check(view.configure(item), "Neutral public GameBox configures before entering tree: " + view.last_error)
	if not view.configured:
		view.free()
		quit(1)
		return
	root.add_child(view)
	await process_frame
	check(view.mouse_filter == Control.MOUSE_FILTER_IGNORE and view.viewport_container.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Both UI layers ignore mouse")
	check(view.focus_mode == Control.FOCUS_NONE and view.viewport.gui_disable_input, "Passive layer cannot take keyboard/gamepad focus")
	check(view.viewport.own_world_3d and view.viewport.find_world_3d() != root.find_world_3d(), "Box world is isolated from the console")
	check(view.viewport.transparent_bg, "Transparent viewport compositing")
	check(view.box.item == item and view.box.item_id == item.id, "Same catalog entry with no data or artwork substitution")
	check(view.box.original_model.transform == Transform3D.IDENTITY, "Original native source geometry is not reframed or scaled")
	check(not view.box.cartridge.visible, "Duplicate cartridge stays hidden")
	check(view.camera.projection == Camera3D.PROJECTION_FRUSTUM, "Only box uses calibrated perspective frustum")
	check(console_camera.current and console_camera.projection == Camera3D.PROJECTION_ORTHOGONAL and console_camera.size == 10.0 and console_camera.transform == original_camera_transform, "Console camera remains exactly unchanged")
	check(view.visible and view.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Configured active layer renders")
	var calibrated_transform := view.camera.transform
	var joint: Dictionary = view.rig.get_joint_report()
	check(is_equal_approx(joint.base_spine_degrees, 90.0) and is_equal_approx(joint.spine_lid_degrees, 10.345512025270239), "Exact validated dual joint deltas")
	check(joint.lower_anchor_error_m < 0.0000001 and joint.upper_anchor_error_m < 0.0000001, "Calibrated joints remain in contact")
	var reference_aspect := 0.0
	for frame_size in [Vector2(420, 400), Vector2(640, 360), Vector2(480, 360), Vector2(100, 700), Vector2(1000, 100), Vector2(64, 64), Vector2(8000, 4500)]:
		view.set_frame(Rect2(Vector2(31, 47), frame_size))
		await process_frame
		var bounds := projected_bounds(view)
		var render_size := Vector2(view.viewport.size)
		check(bounds.position.is_finite() and bounds.size.is_finite(), "Finite geometry projection at " + str(frame_size))
		check(bounds.position.x > 0.5 and bounds.position.y > 0.5 and bounds.end.x < render_size.x - 0.5 and bounds.end.y < render_size.y - 0.5, "Entire visible case fits with safe padding at " + str(frame_size))
		check(bounds.get_center().distance_to(render_size * 0.5) < 0.03, "Actual mesh projection is centered at " + str(frame_size))
		check(view.camera.transform == calibrated_transform, "Aspect changes do not move/reorient calibrated camera at " + str(frame_size))
		check(is_equal_approx(view.viewport_container.scale.x, view.viewport_container.scale.y), "UI image is not stretched at " + str(frame_size))
		var aspect := bounds.size.x / bounds.size.y
		if reference_aspect == 0.0:
			reference_aspect = aspect
		check(absf(aspect - reference_aspect) < 0.0001, "Projected case proportions stay invariant at " + str(frame_size))
		var back := projected_bounds(view, "Box_BACK")
		var spine := projected_bounds(view, "Box_LEFT_SPINE")
		var front := projected_bounds(view, "Box_FRONT")
		check(back.get_center().x < spine.get_center().x and spine.get_center().x < front.get_center().x, "Back-left / spine / front-right arrangement at " + str(frame_size))
		check(maxi(view.viewport.size.x, view.viewport.size.y) <= BoxView.MAX_VIEWPORT_DIMENSION, "Extreme frames keep bounded render dimensions")
	view.set_frame(Rect2(10, 20, 420, 400))
	var saved_box: Node3D = view.box
	var saved_pose: Transform3D = view.box.lid.transform
	var saved_projection: Projection = view.camera.get_camera_projection()
	for repeat in range(10):
		view.set_scene_active(false)
		check(view.visible and view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Focus loss retains visible snapshot while rendering is paused")
		view.set_scene_active(true)
		check(view.visible and view.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Focus return resumes rendering")
		view.set_active(false)
		check(not view.visible and view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Inactive screen hides and stops layer")
		view.set_active(true)
		check(view.box == saved_box and view.box.lid.transform == saved_pose and view.camera.get_camera_projection() == saved_projection, "Pause/hide/reopen preserves same box, pose, and camera")
	view.set_frame(Rect2(0, 0, 0, 10))
	check(not view.visible and view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Zero-sized frame cannot render")
	view.set_frame(Rect2(0, 0, NAN, 10))
	check(not view.visible, "Nonfinite frame cannot render")
	view.set_frame(Rect2(10, 20, 420, 400))
	check(view.visible, "Valid frame recovers after invalid geometry")
	view.clear()
	check(not view.configured and not view.visible and view.box == null and view.rig == null, "Clear releases box and rig and hides layer")
	check(view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Clear stops rendering")
	view.clear()
	check(not view.configure({"id": "missing", "model_path": ""}), "Missing original model fails explicitly instead of inventing articulated geometry")
	check(not view.last_error.is_empty() and not view.visible, "Failed configure remains hidden with actionable reason")
	check(view.configure({"id": "new_neutral", "title": "New neutral entry"}), "New valid catalog entry recovers after clear/failure")
	check(view.visible and view.box.item_id == "new_neutral", "Reconfigure respects requested active state and new item")
	check(view._world.find_children("LibraryBox_*", "Node3D", false, false).size() == 1, "Only one catalog box is attached after replacement")
	check(console_camera.current and console_camera.transform == original_camera_transform, "Repeated layer lifecycles never modify console camera")
	view.clear()
	view.queue_free()
	console_world.queue_free()
	await process_frame
	print("PERSPECTIVE_BOX_VIEW_TESTS ", JSON.stringify({"assertions": assertions, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
