extends Control
## Passive, transparent HOME-box layer. Its private 3D world cannot change or
## duplicate the orthographic console scene. No input, animations, or ROM access.
## configure() and set_frame() are safe before or after entering the scene tree.
## set_active() controls visibility; set_scene_active() pauses rendering on focus
## loss while retaining the current image, model, and pose. clear() releases the
## model and rig, retaining the reusable viewport and requested active state.

const GameBox := preload("res://cosmic/game_box.gd")
const DualHinge := preload("res://cosmic/box_dual_hinge.gd")

# Fixed perspective_dual calibration from the validated isolated hinge proof.
# Source frame: native metres, Z along the case height; camera up is source -Z.
# Joint values are independent signed deltas from CLOSED about source +Z.
# The proof used a 1228x617 viewport, focal length 1423.0687873725724 px,
# principal point (321.3616497147174, 312.32233524767975), and 6.936927 px RMSE.
# Here ONLY its image scale/translation change to fit the caller's rectangle:
# the camera position/orientation, physical model, artwork, and joint angles do
# not change with aspect ratio. An off-axis frustum preserves that perspective.
const BASE_SPINE_DEGREES := 90.0
const SPINE_LID_DEGREES := 10.345512025270239
const CAMERA_AZIMUTH_DEGREES := 42.136630903367454
const CAMERA_ELEVATION_DEGREES := -0.8349583888981938
const CAMERA_DISTANCE_M := 0.5509460395840563
const CAMERA_NEAR_M := 0.02
const CAMERA_FAR_M := 10.0
const SAFE_BORDER_FRACTION := 0.035
const MIN_SAFE_BORDER_PIXELS := 4.0
const MAX_VIEWPORT_DIMENSION := 4096

var viewport_container: SubViewportContainer
var viewport: SubViewport
var camera: Camera3D
var box: Node3D
var rig: RefCounted
var configured := false
var last_error := ""

var _world: Node3D
var _active := false
var _scene_active := true
var _frame_valid := false
var _angular_bounds := Rect2()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	hide()

func _ready() -> void:
	_ensure_viewport()
	_update_frame()

func configure(item: Dictionary) -> bool:
	clear()
	_ensure_viewport()
	var next_box := GameBox.new()
	next_box.configure(item)
	if not is_instance_valid(next_box.original_model):
		next_box.free()
		return _fail("The catalog entry did not load a compatible original box model.")
	# GameBox owns media resolution and its neutral public fallback. Do not
	# substitute artwork, infer a game, or read a private manifest here.
	next_box.original_model.transform = Transform3D.IDENTITY
	if is_instance_valid(next_box.cartridge):
		next_box.cartridge.hide()
	var next_rig := DualHinge.new()
	if not next_rig.configure(next_box):
		var reason: String = next_rig.last_error
		next_box.free()
		return _fail(reason)
	if not next_rig.set_angles(BASE_SPINE_DEGREES, SPINE_LID_DEGREES):
		var reason: String = next_rig.last_error
		next_rig.restore()
		next_box.free()
		return _fail(reason)
	box = next_box
	rig = next_rig
	_world.add_child(box)
	if not _measure_angular_bounds():
		var reason := last_error
		clear()
		return _fail(reason)
	configured = true
	last_error = ""
	_update_frame()
	return true

func set_frame(frame: Rect2) -> void:
	if not frame.position.is_finite() or not frame.size.is_finite() or frame.size.x <= 0.0 or frame.size.y <= 0.0:
		_frame_valid = false
		_apply_activity()
		return
	position = frame.position
	size = frame.size
	_ensure_viewport()
	_update_frame()

func set_active(value: bool) -> void:
	_active = value
	_apply_activity()

func set_scene_active(value: bool) -> void:
	_scene_active = value
	_apply_activity()

func clear() -> void:
	configured = false
	if is_instance_valid(rig):
		rig.restore()
	rig = null
	if is_instance_valid(box):
		# Detach immediately so rebuilding cannot render two catalog entries.
		if box.get_parent():
			box.get_parent().remove_child(box)
		box.queue_free()
	box = null
	_angular_bounds = Rect2()
	last_error = ""
	_apply_activity()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(viewport):
		_update_frame()
	elif what == NOTIFICATION_EXIT_TREE and is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _ensure_viewport() -> void:
	if is_instance_valid(viewport):
		return
	viewport_container = SubViewportContainer.new()
	viewport_container.name = "BoxPerspectiveContainer"
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_container.focus_mode = Control.FOCUS_NONE
	# Render at physical UI dimensions. The container's uniform scale below is
	# only needed for extreme caller sizes; it never stretches an image axis.
	viewport_container.stretch = false
	add_child(viewport_container)
	viewport = SubViewport.new()
	viewport.name = "BoxPerspectiveViewport"
	viewport.size = Vector2i(2, 2)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport_container.add_child(viewport)
	_world = Node3D.new()
	_world.name = "BoxOnlyWorld"
	viewport.add_child(_world)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.48
	world_environment.environment = environment
	_world.add_child(world_environment)
	camera = Camera3D.new()
	camera.name = "CalibratedBoxCamera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var azimuth := deg_to_rad(CAMERA_AZIMUTH_DEGREES)
	var elevation := deg_to_rad(CAMERA_ELEVATION_DEGREES)
	var origin := Vector3(-sin(azimuth) * cos(elevation), -cos(azimuth) * cos(elevation), -sin(elevation)) * CAMERA_DISTANCE_M
	camera.transform = Transform3D(Basis.IDENTITY, origin).looking_at(Vector3.ZERO, Vector3(0.0, 0.0, -1.0))
	_world.add_child(camera)
	camera.current = true
	var key_light := DirectionalLight3D.new()
	key_light.name = "NeutralBoxKey"
	key_light.basis = camera.basis
	key_light.light_energy = 0.52
	key_light.light_color = Color.WHITE
	_world.add_child(key_light)

func _update_frame() -> void:
	if not is_instance_valid(viewport):
		return
	_frame_valid = size.is_finite() and size.x >= 1.0 and size.y >= 1.0
	if not _frame_valid:
		_apply_activity()
		return
	# Keep huge UI sizes bounded without independent horizontal/vertical scale.
	var render_scale := maxf(1.0, maxf(size.x, size.y) / float(MAX_VIEWPORT_DIMENSION))
	var pixels := Vector2i(maxi(2, int(round(size.x / render_scale))), maxi(2, int(round(size.y / render_scale))))
	viewport.size = pixels
	viewport_container.position = Vector2.ZERO
	viewport_container.size = Vector2(pixels)
	viewport_container.scale = Vector2.ONE * render_scale
	if configured:
		var extent := Vector2(pixels)
		var border := maxf(MIN_SAFE_BORDER_PIXELS / render_scale, minf(extent.x, extent.y) * SAFE_BORDER_FRACTION)
		border = minf(border, minf(extent.x, extent.y) * 0.2)
		var usable := extent - Vector2.ONE * border * 2.0
		var pixels_per_radian := minf(usable.x / _angular_bounds.size.x, usable.y / _angular_bounds.size.y)
		var frustum_height := CAMERA_NEAR_M * extent.y / pixels_per_radian
		var frustum_offset := _angular_bounds.get_center() * CAMERA_NEAR_M
		camera.set_frustum(frustum_height, frustum_offset, CAMERA_NEAR_M, CAMERA_FAR_M)
	_apply_activity()

func _measure_angular_bounds() -> bool:
	# Actual mesh vertices rather than a transformed AABB give tight bounds even
	# on the rotated front panel. Coordinates are accumulated locally so this
	# also works before the Control enters the tree. Hidden cartridge is excluded.
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	var count := 0
	var camera_inverse := camera.transform.affine_inverse()
	for candidate in box.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if not mesh_instance.mesh:
			continue
		var transform := Transform3D.IDENTITY
		var current: Node = mesh_instance
		var visible_path := true
		while current != _world:
			if current is Node3D:
				if not current.visible:
					visible_path = false
					break
				transform = current.transform * transform
			current = current.get_parent()
		if not visible_path:
			continue
		var to_camera := camera_inverse * transform
		for surface in mesh_instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := to_camera * vertex
				if not point.is_finite() or -point.z <= CAMERA_NEAR_M or -point.z >= CAMERA_FAR_M:
					return _fail("The box geometry is outside the calibrated camera depth range.")
				var angular := Vector2(point.x, point.y) / -point.z
				low = low.min(angular)
				high = high.max(angular)
				count += 1
	if count == 0 or (high - low).x <= 0.0 or (high - low).y <= 0.0:
		return _fail("The box has no visible, measurable geometry.")
	_angular_bounds = Rect2(low, high - low)
	return true

func _apply_activity() -> void:
	visible = _active and configured and _frame_valid
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible and _scene_active else SubViewport.UPDATE_DISABLED

func _fail(reason: String) -> bool:
	last_error = reason
	_apply_activity()
	return false
