extends RefCounted
## Reversible presentation rig validated in an isolated proof; not OEM CAD.
## Optional default-on sleeve-margin helper bends only the existing unsupported
## 2 mm edge; disable sleeve_margin_enabled for the original all-rigid audit.
## Two rigid joints derived from the original Case_wall vertices. The original
## corrected upper hinge is retained. No source mesh/UV/material/native dimensions,
## scene hierarchy, camera, or source asset is edited.
##
## Usage: var rig = preload("res://lab/dual_hinge.gd").new()
##        assert(rig.configure(game_box))  # Must be in its closed pose.
##        rig.set_angles(40.0, 100.0)
##        rig.reset()    # Exact original local transforms, rig still active.
##        rig.restore()  # Exact restoration, then releases rig references.
## Angles are independent signed DELTAS from CLOSED, not included panel angles.
## Positive angles rotate about source +Z. (90, 90) is nominally unfolded.
## This proof intentionally does not infer mechanical stops from photographs.
## Do not call GameBox.set_lid_angle/toggle_lid while this helper owns the pose.
##
## Inherited limitations: the source is a rigid beveled tray, not a modeled
## living-hinge case. Moving its spine wall can leave the top/bottom tray-wall
## corners exposed. The three independent artwork sheets already have margins;
## they are not a continuous sleeve. This helper preserves those margins instead
## of stretching them or inventing a bridge. Contact tests concern the two
## molded hinge lines, not literal coincidence of the artwork edges.

const EDGE_EPS_M := 0.0000001
const SleeveMargin := preload("res://cosmic/box_sleeve_margin.gd")
var sleeve_margin_enabled := true
var _margin: RefCounted

var last_error := ""
var base_spine_degrees := 0.0
var spine_lid_degrees := 0.0
var configured := false

var _box: Node3D
var _source: Node3D
var _wall: MeshInstance3D
var _spine_art: MeshInstance3D
var _lid: Node3D
var _wall_closed := Transform3D.IDENTITY
var _spine_closed := Transform3D.IDENTITY
var _lid_closed := Transform3D.IDENTITY
var _lower_axis := PackedVector3Array()
var _upper_axis := PackedVector3Array()
var _lower_pivot := Vector3.ZERO
var _upper_pivot := Vector3.ZERO
var _axis_direction := Vector3.BACK
var _spine_motion := Transform3D.IDENTITY
var _front_motion := Transform3D.IDENTITY
var _art_margins: Dictionary = {}

func configure(game_box: Node3D) -> bool:
	if configured:
		return _fail("Restore the existing rig before configuring another box.")
	if not is_instance_valid(game_box):
		return _fail("GameBox is missing.")
	var model := game_box.get("original_model") as Node3D
	if not is_instance_valid(model):
		return _fail("GameBox must have loaded its original GLB before configuration.")
	var source := model.find_child("SMS_BOX_ROOT", true, false) as Node3D
	var lid := game_box.get("lid") as Node3D
	if not is_instance_valid(source) or not is_instance_valid(lid):
		return _fail("Original source box or lid is missing.")
	var wall := source.find_child("Case_wall", true, false) as MeshInstance3D
	var spine_art := source.find_child("Box_LEFT_SPINE", true, false) as MeshInstance3D
	var back := source.find_child("Case_back", true, false) as MeshInstance3D
	var rim := lid.find_child("Lid_rim", true, false) as MeshInstance3D
	if not wall or not spine_art or not back or not rim:
		return _fail("Expected native spine, artwork, back, and lid rim are required.")
	if wall.get_parent() != source or spine_art.get_parent() != source or lid.get_parent() != source:
		return _fail("Unexpected hierarchy; this proof will not rewrite the source hierarchy.")
	if bool(game_box.get("opened")) or not lid.basis.is_equal_approx(Basis.IDENTITY):
		return _fail("Configure only from the exact closed GameBox pose.")
	if not bool(game_box.get_meta("hinge_pivot_repaired", false)):
		return _fail("The approved single-hinge contact correction is required first.")
	var points := _vertices_in_parent(wall)
	if points.is_empty():
		return _fail("Spine wall has no readable vertex positions.")
	var lower := _outer_longitudinal_edge(points, false)
	var upper := _outer_longitudinal_edge(points, true)
	if lower.size() != 2 or upper.size() != 2:
		return _fail("Could not derive both longitudinal hinge edges from the source mesh.")
	var lower_center := (lower[0] + lower[1]) * 0.5
	var upper_center := (upper[0] + upper[1]) * 0.5
	if Vector2(lid.position.x, lid.position.y).distance_to(Vector2(upper_center.x, upper_center.y)) > EDGE_EPS_M:
		return _fail("Corrected lid pivot disagrees with the source wall upper edge: lid=%s derived=%s distance=%s." % [lid.position, upper_center, lid.position.distance_to(upper_center)])
	var lower_direction := (lower[1] - lower[0]).normalized()
	var upper_direction := (upper[1] - upper[0]).normalized()
	if lower_direction.distance_to(upper_direction) > EDGE_EPS_M:
		return _fail("The two source hinge lines are not parallel.")
	# AABBs are only a defensive prerequisite. The companion test additionally
	# verifies the actual triangle hulls at endpoints and intermediate samples.
	for point in lower:
		if not back.get_aabb().grow(EDGE_EPS_M).has_point(back.transform.affine_inverse() * point):
			return _fail("Lower hinge edge is not within the native back's bounds.")
	for point in upper:
		if not rim.get_aabb().grow(EDGE_EPS_M).has_point((lid.transform * rim.transform).affine_inverse() * point):
			return _fail("Upper hinge edge no longer contacts the corrected lid rim.")
	_box = game_box
	_source = source
	_wall = wall
	_spine_art = spine_art
	_lid = lid
	_wall_closed = wall.transform
	_spine_closed = spine_art.transform
	_lid_closed = lid.transform
	_lower_axis = lower
	_upper_axis = upper
	_lower_pivot = lower_center
	# Retain the actual approved pivot, not a separately rounded replacement.
	_upper_pivot = lid.position
	_axis_direction = lower_direction
	_art_margins = _measure_original_art_margins()
	base_spine_degrees = 0.0
	spine_lid_degrees = 0.0
	_spine_motion = Transform3D.IDENTITY
	_front_motion = Transform3D.IDENTITY
	if sleeve_margin_enabled:
		_margin = SleeveMargin.new()
		var shell := lid.find_child("Case_lid", true, false) as MeshInstance3D
		if not shell or not _margin.configure(spine_art, shell, lid, _upper_pivot.y):
			return _fail("Unable to configure isolated sleeve-margin correction.")
	configured = true
	last_error = ""
	return true

func set_angles(base_spine_deg: float, spine_lid_deg: float) -> bool:
	if not _references_valid():
		return _fail("Rig is not configured, or GameBox was rebuilt; configure a new rig.")
	if not is_finite(base_spine_deg) or not is_finite(spine_lid_deg):
		return _fail("Both joint angles must be finite; pose was not changed.")
	base_spine_degrees = base_spine_deg
	spine_lid_degrees = spine_lid_deg
	_spine_motion = _around(_lower_pivot, base_spine_deg)
	_front_motion = _around(_upper_pivot, spine_lid_deg)
	# Exact zero fast paths are intentional. They avoid roundoff on closing and
	# leave the already approved upper hinge correction untouched.
	_wall.transform = _wall_closed if base_spine_deg == 0.0 else _spine_motion * _wall_closed
	_spine_art.transform = _spine_closed if base_spine_deg == 0.0 else _spine_motion * _spine_closed
	if base_spine_deg == 0.0 and spine_lid_deg == 0.0:
		_lid.transform = _lid_closed
	elif spine_lid_deg == 0.0:
		_lid.transform = _spine_motion * _lid_closed
	elif base_spine_deg == 0.0:
		_lid.transform = _front_motion * _lid_closed
	else:
		_lid.transform = _spine_motion * _front_motion * _lid_closed
	if _margin and not _margin.update(_front_motion):
		return _fail(_margin.last_error)
	last_error = ""
	return true

func reset() -> bool:
	return set_angles(0.0, 0.0)

func restore() -> bool:
	if not configured:
		return true
	if not _references_valid():
		_release()
		return _fail("The original nodes no longer exist; no replacement nodes were changed.")
	var restored := reset()
	_release()
	return restored

func get_joint_report() -> Dictionary:
	if not _references_valid():
		return {"configured": false, "error": last_error}
	var lower_spine := PackedVector3Array()
	var upper_spine := PackedVector3Array()
	var upper_lid := PackedVector3Array()
	var lower_error := 0.0
	var upper_error := 0.0
	for point in _lower_axis:
		var moved := _spine_motion * point
		lower_spine.append(moved)
		lower_error = maxf(lower_error, point.distance_to(moved))
	for point in _upper_axis:
		var from_spine := _spine_motion * point
		var from_lid := _spine_motion * _front_motion * point
		upper_spine.append(from_spine)
		upper_lid.append(from_lid)
		upper_error = maxf(upper_error, from_spine.distance_to(from_lid))
	return {
		"configured": true,
		"coordinate_frame": "SMS_BOX_ROOT native metres, before display rotation/scale",
		"angle_convention": "Independent signed rotation deltas from closed about source +Z",
		"base_spine_degrees": base_spine_degrees,
		"spine_lid_degrees": spine_lid_degrees,
		"lower_axis_closed": _lower_axis.duplicate(),
		"upper_axis_closed": _upper_axis.duplicate(),
		"lower_pivot": _lower_pivot,
		"upper_pivot": _upper_pivot,
		"axis_direction": _axis_direction,
		"lower_axis_spine_current": lower_spine,
		"upper_axis_spine_current": upper_spine,
		"upper_axis_lid_current": upper_lid,
		"lower_anchor_error_m": lower_error,
		"upper_anchor_error_m": upper_error,
		"inherited_art_edge_gaps_m": _art_margins.duplicate(true),
		"sleeve_margin": _margin.get_report() if _margin else {"enabled": false},
		"limitations": [
			"Rigid-tray kinematic proof, not measured OEM living-hinge geometry or mechanical stops.",
			"Native top/bottom tray walls stay with the base; opening the spine exposes those inherited corner interfaces.",
			"Native artwork sheets have existing margins; literal sleeve continuity is not claimed or fabricated.",
			"Molded hinge contact is maintained; collision-free motion and material flex are not simulated."
		]
	}

func _around(pivot: Vector3, angle_deg: float) -> Transform3D:
	if angle_deg == 0.0:
		return Transform3D.IDENTITY
	var rotation := Basis(_axis_direction, deg_to_rad(angle_deg))
	return Transform3D(rotation, pivot - rotation * pivot)

func _references_valid() -> bool:
	return configured and is_instance_valid(_box) and is_instance_valid(_source) and is_instance_valid(_wall) and is_instance_valid(_spine_art) and is_instance_valid(_lid) and _box.get("lid") == _lid and _box.is_ancestor_of(_source) and _wall.get_parent() == _source and _spine_art.get_parent() == _source and _lid.get_parent() == _source

func _release() -> void:
	if _margin: _margin.restore()
	_margin = null
	configured = false
	_box = null
	_source = null
	_wall = null
	_spine_art = null
	_lid = null

func _fail(message: String) -> bool:
	last_error = message
	return false

static func _vertices_in_parent(mesh_instance: MeshInstance3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	if not mesh_instance.mesh:
		return points
	for surface in mesh_instance.mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			points.append(mesh_instance.transform * vertex)
	return points

static func _outer_longitudinal_edge(points: PackedVector3Array, top: bool) -> PackedVector3Array:
	var edge_y := -INF if top else INF
	for point in points:
		edge_y = maxf(edge_y, point.y) if top else minf(edge_y, point.y)
	var edge_x := INF
	for point in points:
		if absf(point.y - edge_y) < EDGE_EPS_M:
			edge_x = minf(edge_x, point.x)
	var z_low := INF
	var z_high := -INF
	for point in points:
		if absf(point.y - edge_y) < EDGE_EPS_M and absf(point.x - edge_x) < EDGE_EPS_M:
			z_low = minf(z_low, point.z)
			z_high = maxf(z_high, point.z)
	if not is_finite(z_low) or z_high - z_low <= EDGE_EPS_M:
		return PackedVector3Array()
	return PackedVector3Array([Vector3(edge_x, edge_y, z_low), Vector3(edge_x, edge_y, z_high)])

func _measure_original_art_margins() -> Dictionary:
	var back := _source.find_child("Box_BACK", true, false) as MeshInstance3D
	var front := _lid.find_child("Box_FRONT", true, false) as MeshInstance3D
	if not back or not front:
		return {}
	var back_points := _vertices_in_parent(back)
	var spine_points := _vertices_in_parent(_spine_art)
	var front_points := _vertices_in_parent(front)
	for index in front_points.size():
		front_points[index] = _lid_closed * front_points[index]
	var back_gap := INF
	var front_gap := INF
	for spine in spine_points:
		for point in back_points:
			back_gap = minf(back_gap, spine.distance_to(point))
		for point in front_points:
			front_gap = minf(front_gap, spine.distance_to(point))
	return {"back_to_spine_nearest_corners": back_gap, "spine_to_front_nearest_corners": front_gap}
