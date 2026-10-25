extends RefCounted
## Locally bounded, reversible articulation of the original spine sleeve's unsupported
## 2 mm upper margin. No texture crop/stretch or whole-sheet normal offset.
## Only the supported sheet's existing four-corner surface is split at the
## measured wall edge. Original mesh resource is restored whenever fold=0.
## Scope validated: calibrated path (0,0) -> (90,10.345512) and return.
const CLEARANCE_M := 0.000002
var last_error := ""
var fold_degrees := 0.0
var _art: MeshInstance3D
var _original: Mesh
var _fold_mesh: Mesh
var _arrays: Array
var _art_closed := Transform3D.IDENTITY
var _pivot := Vector3.ZERO
var _low := Vector3.ZERO
var _high := Vector3.ZERO
var _planes: Array[Plane] = []
var _source_points := PackedVector3Array()
var _reverse_winding := false

func configure(art: MeshInstance3D, lid_shell: MeshInstance3D, lid: Node3D, fold_y: float) -> bool:
	_art = art
	_original = art.mesh
	_art_closed = art.transform
	if _original.get_surface_count() != 1:
		last_error = "Sleeve margin expects one original surface."
		return false
	_arrays = _original.surface_get_arrays(0)
	_source_points.clear()
	_low = Vector3(INF, INF, INF)
	_high = Vector3(-INF, -INF, -INF)
	for point in _arrays[Mesh.ARRAY_VERTEX]:
		var source: Vector3 = _art_closed * point
		_source_points.append(source)
		_low = _low.min(source)
		_high = _high.max(source)
	if absf(_high.x - _low.x) > 0.0000001 or fold_y <= _low.y or fold_y >= _high.y:
		last_error = "Unexpected source sleeve plane or wall-edge position."
		return false
	_pivot = Vector3(_low.x, fold_y, 0.0)
	var indices: PackedInt32Array = _arrays[Mesh.ARRAY_INDEX]
	var geometric_normal := (_source_points[indices[1]] - _source_points[indices[0]]).cross(_source_points[indices[2]] - _source_points[indices[0]])
	_reverse_winding = geometric_normal.x < 0.0
	var shell_transform := lid.transform * lid_shell.transform
	var center := shell_transform * lid_shell.get_aabb().get_center()
	for surface in lid_shell.mesh.get_surface_count():
		var arrays: Array = lid_shell.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in range(0, order.size(), 3):
			var a := shell_transform * vertices[order[index]]
			var b := shell_transform * vertices[order[index + 1]]
			var c := shell_transform * vertices[order[index + 2]]
			var normal := (b - a).cross(c - a)
			if normal.length_squared() < 1e-20: continue
			normal = normal.normalized()
			if normal.dot(center - a) > 0.0: normal = -normal
			_planes.append(Plane(normal, normal.dot(a)))
	return true

func update(relative_lid_motion: Transform3D) -> bool:
	if _safe(0.0, relative_lid_motion):
		restore()
		return true
	var lower := 0.0
	var upper := 30.0
	if not _safe(upper, relative_lid_motion):
		restore()
		last_error = "Margin correction is not validated for this angle; original mesh retained."
		return false
	for iteration in 24:
		var middle := (lower + upper) * 0.5
		if _safe(middle, relative_lid_motion): upper = middle
		else: lower = middle
	if _fold_mesh and _art.mesh == _fold_mesh and fold_degrees == upper:
		return true
	fold_degrees = upper
	_build_fold(upper)
	last_error = ""
	return true

func restore() -> void:
	if is_instance_valid(_art) and _original:
		_art.mesh = _original
	fold_degrees = 0.0
	_fold_mesh = null

func get_report() -> Dictionary:
	var rotation := Basis(Vector3.BACK, deg_to_rad(fold_degrees))
	var tip := Vector3(_low.x, _high.y, 0.0)
	return {"fold_degrees": fold_degrees, "free_margin_width_m": _high.y - _pivot.y, "sheet_unfolded_width_m": _high.y - _low.y, "sheet_height_m": _high.z - _low.z, "tip_offset_m": _pivot + rotation * (tip - _pivot) - tip, "minimum_separating_plane_clearance_m": CLEARANCE_M, "original_resource_restored": _art.mesh == _original, "scope": "Calibrated path only; rigid shell and original UV mapping unchanged."}

func _safe(degrees: float, motion: Transform3D) -> bool:
	var rotation := Basis(Vector3.BACK, deg_to_rad(degrees))
	var corners := PackedVector3Array([
		Vector3(_low.x, _pivot.y, _low.z), Vector3(_low.x, _high.y, _low.z),
		Vector3(_low.x, _high.y, _high.z), Vector3(_low.x, _pivot.y, _high.z)])
	for index in corners.size(): corners[index] = _pivot + rotation * (corners[index] - _pivot)
	# Entire folded patch must lie beyond ONE actual supporting plane. That is
	# a surface-based separation proof, not merely an AABB or corner-in-box test.
	for plane in _planes:
		var normal := motion.basis * plane.normal
		var offset := plane.d + normal.dot(motion.origin)
		var smallest := INF
		for corner in corners: smallest = minf(smallest, normal.dot(corner) - offset)
		if smallest >= CLEARANCE_M: return true
	return false

func _uv_at(source: Vector3) -> Vector2:
	var uv: PackedVector2Array = _arrays[Mesh.ARRAY_TEX_UV]
	var result := Vector2.ZERO
	var y := (source.y - _low.y) / (_high.y - _low.y)
	var z := (source.z - _low.z) / (_high.z - _low.z)
	for index in _source_points.size():
		var point := _source_points[index]
		var weight_y := 1.0 - y if absf(point.y - _low.y) < 0.0000001 else y
		var weight_z := 1.0 - z if absf(point.z - _low.z) < 0.0000001 else z
		result += uv[index] * weight_y * weight_z
	return result

func _build_fold(degrees: float) -> void:
	var points := PackedVector3Array([
		Vector3(_low.x, _low.y, _low.z), Vector3(_low.x, _pivot.y, _low.z), Vector3(_low.x, _pivot.y, _high.z), Vector3(_low.x, _low.y, _high.z),
		Vector3(_low.x, _pivot.y, _low.z), Vector3(_low.x, _high.y, _low.z), Vector3(_low.x, _high.y, _high.z), Vector3(_low.x, _pivot.y, _high.z)])
	var uv := PackedVector2Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var old_normals: PackedVector3Array = _arrays[Mesh.ARRAY_NORMAL]
	var old_tangents: PackedFloat32Array = _arrays[Mesh.ARRAY_TANGENT]
	var inverse := _art_closed.affine_inverse()
	var rotation := Basis(Vector3.BACK, deg_to_rad(degrees))
	for index in points.size():
		uv.append(_uv_at(points[index]))
		var normal: Vector3 = _art_closed.basis * old_normals[0]
		if index >= 4:
			points[index] = _pivot + rotation * (points[index] - _pivot)
			normal = rotation * normal
		points[index] = inverse * points[index]
		normals.append((inverse.basis * normal).normalized())
		if not old_tangents.is_empty():
			var tangent := _art_closed.basis * Vector3(old_tangents[0], old_tangents[1], old_tangents[2])
			if index >= 4: tangent = rotation * tangent
			tangent = (inverse.basis * tangent).normalized()
			tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, old_tangents[3]]))
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	if _reverse_winding:
		for index in range(0, indices.size(), 3):
			var temporary := indices[index + 1]
			indices[index + 1] = indices[index + 2]
			indices[index + 2] = temporary
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	if not tangents.is_empty(): arrays[Mesh.ARRAY_TANGENT] = tangents
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh.surface_set_material(0, _original.surface_get_material(0))
	_fold_mesh = mesh
	_art.mesh = mesh
