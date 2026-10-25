extends RefCounted
## Demonstrative paper flex, NOT OEM mechanics or a force/material simulation.
## configure(box, canonical_book, options) reads original geometry without moving it.
## Local point/normal inputs are ORIGINAL book.root coordinates in native metres.
## pose_for(p) is the book.root transform relative to its unchanged lid parent.
## apply_progress(p) deforms ONLY temporary copies of the two booklet meshes;
## exact original mesh resources/transforms are restored at rest. No box edits.
## begin_release/return/abort + tick provide reversible, focus-paused traversal.
## The fixed sequence is bend free paper, slide clear, lift, unbend, approach.
## Collision certificates use conservative strip volumes against bounds derived
## from every original mesh's actual vertices in the CURRENT open-box pose.
## A potential collision rejects the plan, even if caused by conservative bounds.

const PARTS := ["Case_lid", "Lid_rim", "Lid_rim_001", "Lid_rim_002", "Lid_rim_003", "Manual_clip", "Manual_clip_001"]
const CUTS := [0.0, 0.23, 0.48, 0.65, 0.85, 1.0]
const PHASES := ["bending_free_paper", "sliding_clear", "lifting", "unbending", "approaching"]
const STRIPS := 64
const INTERVALS_PER_PHASE := 8
const CLEARANCE_M := 0.000025
const BEND_MARGIN_M := 0.001
const SLIDE_MARGIN_M := 0.0001
const MAX_DISTANCE_M := 0.25

var last_error := ""
var progress: float:
	get: return _progress
var busy: bool:
	get: return configured and _progress != _target
var configured: bool:
	get: return _valid and _references_valid()
var state: String:
	get:
		if not configured: return "blocked"
		if _progress == 0.0 and not busy: return "held"
		if _progress == 1.0 and not busy: return "released"
		return "returning" if _target < _progress else str(sample(_progress).phase)

var _box: Node3D
var _book: RefCounted
var _root: Node3D
var _lid: Node3D
var _source: Node3D
var _closed_lid := Transform3D.IDENTITY
var _lid_current := Transform3D.IDENTITY
var _rest := Transform3D.IDENTITY
var _source_center := Vector3.ZERO
var _local_bounds := AABB()
var _bend_x := 0.0
var _free_length := 0.0
var _angle := PI * 0.5
var _slide := 0.0
var _lift := 0.03
var _approach := Vector3(0.0, -0.02, 0.0)
var _duration := 1.1
var _progress := 0.0
var _target := 0.0
var _valid := false
var _obstacles: Array[Dictionary] = []
var _meshes: Array[Dictionary] = []
var _strip_x: Array[float] = []
var _report: Dictionary = {}

func configure(box: Node3D, book: RefCounted, options: Dictionary = {}) -> bool:
	var configure_started := Time.get_ticks_usec()
	if _valid or (not _meshes.is_empty() and is_instance_valid(_root)):
		return _fail("Restore and clear the existing release helper before configuring again.")
	last_error = ""
	_report.clear()
	_obstacles.clear()
	_meshes.clear()
	_strip_x.clear()
	if not is_instance_valid(box) or not is_instance_valid(book) or not bool(book.get("configured")):
		return _fail("A valid box and canonical attached ManualBook are required.")
	var report: Dictionary = book.get_report()
	_root = book.get("root") as Node3D
	_lid = box.get("lid") as Node3D
	if not is_instance_valid(_root) or not is_instance_valid(_lid) or _root.get_parent() != _lid:
		return _fail("The canonical booklet must remain a direct child of the original lid.")
	_source = _lid.get_parent() as Node3D
	if not is_instance_valid(_source) or str(_source.name) != "SMS_BOX_ROOT":
		return _fail("Unexpected original box hierarchy.")
	_box = box
	_book = book
	_closed_lid = report.get("closed_lid_pose", Transform3D.IDENTITY)
	_rest = report.get("book_local_pose", Transform3D.IDENTITY)
	_lid_current = _lid.transform
	if not _root.transform.is_equal_approx(_rest):
		return _fail("Configure only with the canonical booklet at its retained rest pose.")
	var source_rest := _closed_lid * _rest
	if not source_rest.basis.is_equal_approx(Basis.IDENTITY):
		return _fail("This bounded release profile requires the original axis-aligned booklet frame.")
	_source_center = source_rest.origin
	var required: Dictionary = {}
	for child in _lid.get_children():
		if child is MeshInstance3D:
			var key := str(child.name).replace(".", "_")
			if PARTS.has(key): required[key] = child
	for name_value in PARTS:
		if not required.has(name_value): return _fail("Original lid piece is missing: " + name_value)
	var first := true
	for mesh_value in [book.get("paper"), book.get("cover")]:
		var part := mesh_value as MeshInstance3D
		if not is_instance_valid(part) or part.get_parent() != _root or not part.mesh:
			return _fail("Both original canonical booklet meshes must be present.")
		if not part.basis.is_equal_approx(part.basis.orthonormalized()) or not is_equal_approx(part.basis.determinant(), 1.0):
			return _fail("Booklet mesh transforms must remain rigid and unmirrored.")
		var bounds := _mesh_bounds(part.mesh, part.transform)
		_local_bounds = bounds if first else _local_bounds.merge(bounds)
		first = false
		_meshes.append({"node": part, "original": part.mesh, "transform": part.transform, "template": []})
	if not _bounds_finite(_local_bounds) or _local_bounds.size.x <= 0.0 or _local_bounds.size.y <= 0.0 or _local_bounds.size.z <= 0.0:
		return _fail("Booklet volume is empty or invalid.")
	var clip_a := _mesh_bounds(required.Manual_clip.mesh, _closed_lid * required.Manual_clip.transform)
	var clip_b := _mesh_bounds(required.Manual_clip_001.mesh, _closed_lid * required.Manual_clip_001.transform)
	var clip_end := maxf(clip_a.end.x, clip_b.end.x)
	_bend_x = clip_end + BEND_MARGIN_M - _source_center.x
	_free_length = _local_bounds.end.x - _bend_x
	_slide = clip_end + SLIDE_MARGIN_M - (_source_center.x + _local_bounds.position.x)
	if _free_length <= 0.005 or _slide <= 0.0 or _slide > MAX_DISTANCE_M:
		return _fail("The source clips do not admit this bounded free-paper release profile.")
	if _free_length / _angle + _local_bounds.position.y <= 0.0:
		return _fail("Paper thickness exceeds the bounded cylindrical radius.")
	var requested_lift: Variant = options.get("lift_distance_m", 0.03)
	var requested_duration: Variant = options.get("duration_seconds", 1.1)
	if not _numeric(requested_lift) or not _numeric(requested_duration): return _fail("Lift and duration must be finite numbers.")
	_lift = float(requested_lift)
	_duration = float(requested_duration)
	# The presented cartridge occupies space farther along the lid normal.
	# A 20 mm final approach keeps the canonical presented pose clear; a caller's
	# alternative remains subject to the same full-volume validation below.
	var requested_approach: Variant = options.get("approach_offset_source_m", Vector3(0.0, -0.02, 0.0))
	if not requested_approach is Vector3 or not requested_approach.is_finite(): return _fail("Approach must be a finite source-frame offset.")
	_approach = requested_approach
	if _lift <= 0.0 or _lift > MAX_DISTANCE_M or _approach.length() > MAX_DISTANCE_M or _duration < 0.15 or _duration > 10.0:
		return _fail("Requested lift, approach, or duration exceeds the bounded profile.")
	var right_bounds := _mesh_bounds(required.Lid_rim_001.mesh, _closed_lid * required.Lid_rim_001.transform)
	var curved_right := _source_center.x + _bend_x + _free_length / _angle + _local_bounds.end.y + _slide
	var right_clearance := right_bounds.position.x - curved_right
	if right_clearance <= CLEARANCE_M: return _fail("Even a 90 degree free-paper curl cannot clear the original right rim.")
	var lid_y_min := INF
	for name_value in PARTS:
		var part: MeshInstance3D = required[name_value]
		lid_y_min = minf(lid_y_min, _mesh_bounds(part.mesh, _closed_lid * part.transform).position.y)
	var required_lift := _source_center.y + _local_bounds.end.y - lid_y_min + SLIDE_MARGIN_M
	if _lift < required_lift: return _fail("Lift is insufficient to unbend outside the original clips/rims.")
	for part_value in _source.find_children("*", "MeshInstance3D", true, false):
		var part := part_value as MeshInstance3D
		if _root.is_ancestor_of(part) or not part.mesh: continue
		var relative := _relative_transform(part, _source)
		var reference := _closed_lid * _lid_current.affine_inverse() * relative
		var bounds := _mesh_bounds(part.mesh, reference)
		if not _bounds_finite(bounds): return _fail("Original obstacle geometry is invalid: " + str(part.name))
		_obstacles.append({"node": part, "name": str(part.name), "mesh": part.mesh, "relative": relative, "bounds": bounds})
	for index in STRIPS + 1:
		_strip_x.append(lerpf(_local_bounds.position.x, _local_bounds.end.x, float(index) / STRIPS))
	_strip_x.append(_bend_x)
	_strip_x.sort()
	_report = {
		"configured": false, "pose_validated": false, "item_id": report.get("item_id", ""),
		"input_frame": "Original book.root local coordinates, native metres; no display scale",
		"pose_frame": "Transform relative to the unchanged BOX_LID_HINGE parent",
		"source_frame": "SMS_BOX_ROOT closed native frame attached to the current lid pose",
		"bend_start_source_x_m": _source_center.x + _bend_x, "bend_start_local_x_m": _bend_x,
		"free_length_m": _free_length, "bend_degrees": rad_to_deg(_angle), "radius_m": _free_length / _angle,
		"slide_offset_source_m": Vector3.RIGHT * _slide, "lift_offset_source_m": Vector3.DOWN * _lift,
		"approach_offset_source_m": _approach, "minimum_required_lift_m": required_lift,
		"curved_right_rim_clearance_m": right_clearance,
		"rigid_slide_required_m": _slide,
		"rigid_right_rim_clearance_m": right_bounds.position.x - (_source_center.x + _local_bounds.end.x),
		"thickness_is_measured": false, "page_size_m": report.get("page_size_m", Vector2.ZERO),
		"obstacle_count": _obstacles.size(), "strip_count": _strip_x.size() - 1,
		"collision_method": "Original vertex-derived obstacle AABBs; conservative swept strip volumes, including a bending derivative bound between samples. Any potential overlap is rejected.",
		"limitations": ["Demonstrative cylindrical paper flex, not OEM CAD, elasticity, page friction, or a measured thickness.", "Axis-aligned obstacle envelopes can conservatively reject a geometrically possible path.", "Certificate applies only while the original lid/base/cartridge relative geometry stays unchanged."]
	}
	var validation_started := Time.get_ticks_usec()
	if not _validate_path(): return false
	_report.validation_time_usec = Time.get_ticks_usec() - validation_started
	if not _build_templates(): return _fail("Canonical cover/volume cannot be subdivided without changing their content.")
	_progress = 0.0
	_target = 0.0
	_valid = true
	_report.configured = true
	_report.pose_validated = true
	_report.configure_time_usec = Time.get_ticks_usec() - configure_started
	last_error = ""
	return true

func sample(value: float = -1.0) -> Dictionary:
	var p := _bounded(value)
	var phase := 4
	for index in 5:
		if p <= float(CUTS[index + 1]):
			phase = index
			break
	var f := clampf((p - float(CUTS[phase])) / (float(CUTS[phase + 1]) - float(CUTS[phase])), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	var angle := 0.0
	var offset := Vector3.ZERO
	match phase:
		0: angle = _angle * f
		1:
			angle = _angle
			offset.x = _slide * f
		2:
			angle = _angle
			offset = Vector3(_slide, -_lift * f, 0.0)
		3:
			angle = _angle * (1.0 - f)
			offset = Vector3(_slide, -_lift, 0.0)
		4: offset = Vector3(_slide, -_lift, 0.0) + _approach * f
	return {"progress": p, "phase": PHASES[phase], "phase_index": phase, "bend_radians": angle, "offset_source_m": offset}

func deform_point(original: Vector3, value: float = -1.0) -> Vector3:
	return _bend_point(original, float(sample(value).bend_radians))

func deform_normal(normal: Vector3, original_point: Vector3, value: float = -1.0) -> Vector3:
	var angle := float(sample(value).bend_radians)
	var phi := angle * maxf(original_point.x - _bend_x, 0.0) / maxf(_free_length, 0.000001)
	return (Basis(Vector3.BACK, -phi) * normal).normalized()

func pose_for(value: float = -1.0) -> Transform3D:
	var pose := _rest
	pose.origin += _closed_lid.basis.inverse() * Vector3(sample(value).offset_source_m)
	return pose

func begin_release(reduced_motion: bool = false) -> bool:
	return _request(1.0, reduced_motion)

func begin_return(reduced_motion: bool = false) -> bool:
	return _request(0.0, reduced_motion)

func abort(reduced_motion: bool = false) -> bool:
	return begin_return(reduced_motion)

func tick(delta: float, focused: bool = true) -> bool:
	if not configured: return false
	if not focused or not is_finite(delta) or delta <= 0.0 or not busy: return true
	return apply_progress(move_toward(_progress, _target, minf(delta, 0.1) / _duration))

func apply_progress(value: float) -> bool:
	if not configured or not is_finite(value) or value < 0.0 or value > 1.0:
		return _fail("Progress must be finite, bounded, and attached to a validated path.")
	if not _geometry_unchanged():
		_valid = false
		_report.pose_validated = false
		return _fail("Original relative geometry changed; movement stopped without crossing unvalidated space.")
	var angle := float(sample(value).bend_radians)
	for record in _meshes:
		var node: MeshInstance3D = record.node
		if is_zero_approx(angle):
			node.mesh = record.original
			continue
		var arrays: Array = record.template.duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var transform: Transform3D = record.transform
		var inverse := transform.affine_inverse()
		for index in vertices.size():
			var point := transform * vertices[index]
			vertices[index] = inverse * _bend_point(point, angle)
			var phi := angle * maxf(point.x - _bend_x, 0.0) / _free_length
			normals[index] = (inverse.basis * Basis(Vector3.BACK, -phi) * transform.basis * normals[index]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var deformed := ArrayMesh.new()
		deformed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		deformed.surface_set_material(0, record.original.surface_get_material(0))
		node.mesh = deformed
	_root.transform = pose_for(value)
	_progress = value
	last_error = ""
	return true

func restore() -> void:
	if is_instance_valid(_root): _root.transform = _rest
	for record in _meshes:
		if is_instance_valid(record.node):
			record.node.mesh = record.original
			record.node.transform = record.transform
	_progress = 0.0
	_target = 0.0

func clear() -> void:
	restore()
	_valid = false
	_box = null
	_book = null
	_root = null
	_lid = null
	_source = null
	_obstacles.clear()
	_meshes.clear()

func get_report() -> Dictionary:
	var result := _report.duplicate(true)
	result.configured = configured
	result.progress = _progress
	result.state = state
	result.error = last_error
	return result

func _request(target: float, reduced_motion: bool) -> bool:
	if not configured or not _geometry_unchanged(): return _fail("The release path is unavailable or its geometry changed.")
	_target = target
	return apply_progress(target) if reduced_motion else true

func _bounded(value: float) -> float:
	if value == -1.0: return _progress
	return clampf(value, 0.0, 1.0) if is_finite(value) else _progress

func _bend_point(point: Vector3, angle: float) -> Vector3:
	if angle <= 0.000000001 or point.x <= _bend_x: return point
	var radius := _free_length / angle
	var phi := (point.x - _bend_x) / radius
	return Vector3(_bend_x + (radius + point.y) * sin(phi), -radius * (1.0 - cos(phi)) + point.y * cos(phi), point.z)

func _strip_bounds(index: int, sample_value: Dictionary) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for x in [_strip_x[index], _strip_x[index + 1]]:
		for y in [_local_bounds.position.y, _local_bounds.end.y]:
			var point := _bend_point(Vector3(x, y, 0.0), float(sample_value.bend_radians)) + _source_center + Vector3(sample_value.offset_source_m)
			low = low.min(point)
			high = high.max(point)
	low.z = _source_center.z + _local_bounds.position.z + Vector3(sample_value.offset_source_m).z
	high.z = _source_center.z + _local_bounds.end.z + Vector3(sample_value.offset_source_m).z
	return AABB(low, high - low)

func _validate_path() -> bool:
	var min_gap := INF
	var tests := 0
	var intervals := 0
	for phase in 5:
		# Translation has an exact swept AABB: subdividing it adds no safety.
		# Curve intervals retain a continuous, component-wise derivative bound.
		var phase_steps := INTERVALS_PER_PHASE if phase == 0 or phase == 3 else 1
		for step in phase_steps:
			intervals += 1
			var p0 := lerpf(float(CUTS[phase]), float(CUTS[phase + 1]), float(step) / phase_steps)
			var p1 := lerpf(float(CUTS[phase]), float(CUTS[phase + 1]), float(step + 1) / phase_steps)
			var a := sample(p0)
			var b := sample(p1)
			for strip in _strip_x.size() - 1:
				var swept := _strip_bounds(strip, a).merge(_strip_bounds(strip, b))
				# Neutral curve is integral_0^s (cos(theta*u/L),-sin(...)) du.
				# Its theta derivative is <=s²/(2L); thickness adds |y|s/L.
				# Every angle lies within half the endpoint angle difference.
				# Inflate endpoint union by this bound, never presume samples alone.
				var s := maxf(_strip_x[strip + 1] - _bend_x, 0.0)
				var half_thickness := maxf(absf(_local_bounds.position.y), absf(_local_bounds.end.y))
				var half_angle_delta := absf(float(b.bend_radians) - float(a.bend_radians)) * 0.5
				var sine_bound := sin(maxf(float(a.bend_radians), float(b.bend_radians)))
				var center_bound := s * s / (2.0 * _free_length)
				var thickness_bound := half_thickness * s / _free_length
				var pad_x := (center_bound * sine_bound + thickness_bound) * half_angle_delta
				var pad_y := (center_bound + thickness_bound * sine_bound) * half_angle_delta
				swept.position -= Vector3(pad_x, pad_y, 0.0)
				swept.size += Vector3(pad_x * 2.0, pad_y * 2.0, 0.0)
				# Intersect with independent analytic envelopes, not just samples:
				# y' = y -(R+y)(1-cos(phi)) <= y; x' >= bend_x;
				# sin(phi)<=phi gives x'<=original_x+max(y,0).
				# These stop symmetric derivative padding from inventing motion
				# INTO the lid while every actual point bends away from it.
				var offset_low := Vector3(a.offset_source_m).min(Vector3(b.offset_source_m))
				var offset_high := Vector3(a.offset_source_m).max(Vector3(b.offset_source_m))
				var low := swept.position
				var high := swept.end
				low.x = maxf(low.x, _source_center.x + minf(_strip_x[strip], _bend_x) + offset_low.x)
				high.x = minf(high.x, _source_center.x + _strip_x[strip + 1] + maxf(_local_bounds.end.y, 0.0) + offset_high.x)
				high.y = minf(high.y, _source_center.y + _local_bounds.end.y + offset_high.y)
				swept = AABB(low, high - low)
				for obstacle in _obstacles:
					var other: AABB = obstacle.bounds
					var gap := (swept.position - other.end).max(other.position - swept.end)
					var separation := maxf(gap.x, maxf(gap.y, gap.z))
					tests += 1
					min_gap = minf(min_gap, separation)
					if separation < CLEARANCE_M:
						_report.collision = {"phase": PHASES[phase], "interval": step, "strip": strip, "obstacle": obstacle.name, "axis_separation_m": separation, "potential_not_exact_triangle_collision": true}
						return _fail("Conservative swept booklet volume meets original obstacle: %s during %s." % [obstacle.name, PHASES[phase]])
	_report.swept_interval_count = intervals
	_report.volume_pair_tests = tests
	_report.minimum_certified_axis_gap_m = min_gap
	_report.continuous_bound = "Endpoint strip volumes plus analytic angular derivative inflation; straight phases use swept translation bounds."
	return true

func _build_templates() -> bool:
	for record in _meshes:
		var mesh: Mesh = record.original
		if mesh is QuadMesh:
			record.template = _cover_template(mesh, record.transform)
		elif mesh is BoxMesh:
			record.template = _paper_template(mesh, record.transform)
		else: return false
		if record.template.is_empty(): return false
	return true

func _cover_template(mesh: QuadMesh, transform: Transform3D) -> Array:
	var original: Array = mesh.surface_get_arrays(0)
	var ov: PackedVector3Array = original[Mesh.ARRAY_VERTEX]
	var ou: PackedVector2Array = original[Mesh.ARRAY_TEX_UV]
	var oi: PackedInt32Array = original[Mesh.ARRAY_INDEX]
	if ov.size() != 4 or ou.size() != 4 or oi.size() != 6: return []
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var cuts: Array[float] = []
	for index in STRIPS + 1: cuts.append(float(index) / STRIPS)
	var bend_in_mesh := transform.affine_inverse() * Vector3(_bend_x, 0.0, 0.0)
	cuts.append(clampf(bend_in_mesh.x / mesh.size.x + 0.5, 0.0, 1.0))
	cuts.sort()
	for strip in cuts.size() - 1:
		var offset := vertices.size()
		for index in 4:
			var u := lerpf(cuts[strip], cuts[strip + 1], ou[index].x)
			vertices.append(Vector3((u - 0.5) * mesh.size.x, (0.5 - ou[index].y) * mesh.size.y, 0.0))
			normals.append(Vector3.BACK)
			uvs.append(Vector2(u, ou[index].y))
		for index in oi: indices.append(offset + index)
	return _arrays(vertices, normals, uvs, indices)

func _paper_template(mesh: BoxMesh, transform: Transform3D) -> Array:
	var half := mesh.size * 0.5
	var cuts: Array[float] = []
	for index in STRIPS + 1: cuts.append(lerpf(-half.x, half.x, float(index) / STRIPS))
	cuts.append(clampf((transform.affine_inverse() * Vector3(_bend_x, 0.0, 0.0)).x, -half.x, half.x))
	cuts.sort()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for strip in cuts.size() - 1:
		var x0 := cuts[strip]
		var x1 := cuts[strip + 1]
		for sign_value in [-1.0, 1.0]:
			_append_quad([Vector3(x0, sign_value * half.y, -half.z), Vector3(x1, sign_value * half.y, -half.z), Vector3(x1, sign_value * half.y, half.z), Vector3(x0, sign_value * half.y, half.z)], Vector3.UP * sign_value, vertices, normals, uvs, indices)
			_append_quad([Vector3(x0, -half.y, sign_value * half.z), Vector3(x1, -half.y, sign_value * half.z), Vector3(x1, half.y, sign_value * half.z), Vector3(x0, half.y, sign_value * half.z)], Vector3.BACK * sign_value, vertices, normals, uvs, indices)
	for sign_value in [-1.0, 1.0]:
		_append_quad([Vector3(sign_value * half.x, -half.y, -half.z), Vector3(sign_value * half.x, half.y, -half.z), Vector3(sign_value * half.x, half.y, half.z), Vector3(sign_value * half.x, -half.y, half.z)], Vector3.RIGHT * sign_value, vertices, normals, uvs, indices)
	return _arrays(vertices, normals, uvs, indices)

func _append_quad(points: Array, normal: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	var offset := vertices.size()
	for index in 4:
		vertices.append(points[index])
		normals.append(normal)
		uvs.append([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN][index])
	var direction: Vector3 = (Vector3(points[1]) - Vector3(points[0])).cross(Vector3(points[2]) - Vector3(points[0]))
	var order := [0, 2, 1, 0, 3, 2] if direction.dot(normal) > 0.0 else [0, 1, 2, 0, 2, 3]
	for index in order: indices.append(offset + index)

func _arrays(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays

func _mesh_bounds(mesh: Mesh, transform: Transform3D) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for surface in mesh.get_surface_count():
		for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var point: Vector3 = transform * vertex
			low = low.min(point)
			high = high.max(point)
	return AABB(low, high - low)

func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != ancestor and current != null:
		if current is Node3D: result = current.transform * result
		current = current.get_parent()
	return result

func _bounds_finite(bounds: AABB) -> bool:
	return bounds.position.is_finite() and bounds.end.is_finite() and bounds.size.is_finite()

func _numeric(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _geometry_unchanged() -> bool:
	if not _references_valid() or _lid.transform != _lid_current: return false
	for obstacle in _obstacles:
		if not is_instance_valid(obstacle.node) or obstacle.node.mesh != obstacle.mesh or _relative_transform(obstacle.node, _source) != obstacle.relative: return false
	return true

func _references_valid() -> bool:
	return is_instance_valid(_box) and is_instance_valid(_book) and is_instance_valid(_root) and is_instance_valid(_lid) and is_instance_valid(_source) and _root.get_parent() == _lid and _box.get("lid") == _lid and not _root.is_queued_for_deletion()

func _fail(message: String) -> bool:
	last_error = message
	return false
