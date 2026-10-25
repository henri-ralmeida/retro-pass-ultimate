extends SceneTree
## Headless-only test for the isolated two-joint proof.
## godot --headless --path . --script res://cosmic/test_box_dual_hinge.gd
## No GUI, screenshots, source edits, camera changes, or production imports.

const GameBox := preload("res://cosmic/game_box.gd")
const DualHinge := preload("res://cosmic/box_dual_hinge.gd")
const TOLERANCE_M := 0.0000002

var failures: Array[String] = []
var checks := 0
var max_lower_error := 0.0
var max_upper_error := 0.0
var max_rigid_vertex_error := 0.0
var max_length_error := 0.0
var tested_poses := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)

func _run() -> void:
	var box := GameBox.new()
	box.configure({"id": "isolated_dual_hinge_test", "title": "Isolated Dual Hinge Test",
		"cover_front": "res://assets/local_box_art/wonder_boy_front.png",
		"cover_back": "res://assets/local_box_art/wonder_boy_back.png",
		"cover_spine": "res://assets/local_box_art/wonder_boy_spine.png"})
	get_root().add_child(box)
	var rig := DualHinge.new()
	rig.sleeve_margin_enabled = false
	var before := _snapshot(box)
	_check(bool(box.get_meta("hinge_pivot_repaired", false)), "Approved upper hinge correction is present")
	_check(rig.configure(box), "Configure succeeds: " + rig.last_error)
	if not rig.configured:
		_finish(box)
		return
	var report: Dictionary = rig.get_joint_report()
	print("AXES ", report)
	for key in ["lower_pivot", "upper_pivot"]:
		var point: Vector3 = report[key]
		print("PRECISE ", key, " = (%.14f, %.14f, %.14f)" % [point.x, point.y, point.z])
	_check_snapshot_exact(box, before, "configuration")
	_check(rig.get_joint_report()["axis_direction"].is_equal_approx(Vector3.BACK), "Both axes point along native +Z")
	var source := box.original_model.find_child("SMS_BOX_ROOT", true, false) as Node3D
	var wall := source.find_child("Case_wall", true, false) as MeshInstance3D
	var spine := source.find_child("Box_LEFT_SPINE", true, false) as MeshInstance3D
	var back := source.find_child("Case_back", true, false) as MeshInstance3D
	var rim := box.lid.find_child("Lid_rim", true, false) as MeshInstance3D
	var lower: PackedVector3Array = report["lower_axis_closed"]
	var upper: PackedVector3Array = report["upper_axis_closed"]
	var lower_local_wall := PackedVector3Array()
	var upper_local_wall := PackedVector3Array()
	var upper_local_lid := PackedVector3Array()
	for index in 9:
		var fraction := float(index) / 8.0
		var p1 := lower[0].lerp(lower[1], fraction)
		var p2 := upper[0].lerp(upper[1], fraction)
		_check(_inside_convex_mesh(back, back.transform.affine_inverse() * p1), "Lower anchor inside actual back triangle hull " + str(index))
		_check(_inside_convex_mesh(wall, wall.transform.affine_inverse() * p1), "Lower anchor on actual wall triangle hull " + str(index))
		_check(_inside_convex_mesh(wall, wall.transform.affine_inverse() * p2), "Upper anchor on actual wall triangle hull " + str(index))
		_check(_inside_convex_mesh(rim, (box.lid.transform * rim.transform).affine_inverse() * p2), "Upper anchor inside actual lid rim triangle hull " + str(index))
		lower_local_wall.append(wall.transform.affine_inverse() * p1)
		upper_local_wall.append(wall.transform.affine_inverse() * p2)
		upper_local_lid.append(box.lid.transform.affine_inverse() * p2)
	var wall_closed := wall.transform
	var spine_closed := spine.transform
	var lid_closed := box.lid.transform
	var lower_pivot: Vector3 = report["lower_pivot"]
	var upper_pivot: Vector3 = report["upper_pivot"]
	# Includes the original single-hinge poses, flat opening, intermediate
	# two-joint poses, signed excursions, and repeat traversal in reverse.
	var angles_a := [-30.0, 0.0, 10.0, 25.0, 40.0, 60.0, 75.0, 90.0, 110.0]
	var angles_b := [-20.0, 0.0, 15.0, 45.0, 70.0, 90.0, 105.0, 115.0, 140.0]
	for a in angles_a:
		for b in angles_b:
			_check_pose(rig, box, source, wall, spine, before, wall_closed, spine_closed, lid_closed, lower, lower_local_wall, upper_local_wall, upper_local_lid, lower_pivot, upper_pivot, a, b)
	angles_a.reverse()
	angles_b.reverse()
	for a in angles_a:
		for b in angles_b:
			_check_pose(rig, box, source, wall, spine, before, wall_closed, spine_closed, lid_closed, lower, lower_local_wall, upper_local_wall, upper_local_lid, lower_pivot, upper_pivot, a, b)
	_check(rig.reset(), "Reset succeeds")
	_check_snapshot_exact(box, before, "reset after angle grid")
	# Independent kinematic controls: changing the lid joint cannot move spine.
	rig.set_angles(35.0, 0.0)
	var spine_before := spine.transform
	var wall_before := wall.transform
	rig.set_angles(35.0, 105.0)
	_check(spine.transform == spine_before and wall.transform == wall_before, "Lid angle does not change spine pose")
	# Original approved behavior is a strict subset at a=0.
	rig.reset()
	box.set_lid_angle(115.0)
	var original_single_hinge := box.lid.transform
	box.set_lid_angle(0.0)
	rig.set_angles(0.0, 115.0)
	_check(box.lid.transform.is_equal_approx(original_single_hinge), "a=0 reproduces approved single hinge")
	# Reject invalid angles atomically.
	var prior := _snapshot(box)
	_check(not rig.set_angles(NAN, 90.0), "NaN rejected")
	_check_snapshot_exact(box, prior, "NaN rejection")
	_check(not rig.set_angles(90.0, INF), "Infinity rejected")
	_check_snapshot_exact(box, prior, "infinity rejection")
	_check(not rig.configure(box), "Duplicate configure rejected without mutation")
	_check_snapshot_exact(box, prior, "duplicate configure rejection")
	_check(rig.restore(), "Restore succeeds")
	_check_snapshot_exact(box, before, "restore")
	_check(not rig.configured, "Restore releases rig")
	_check(rig.restore(), "Repeated restore is harmless")
	_check(not rig.set_angles(10.0, 10.0), "Unconfigured rig rejects pose changes")
	_check_snapshot_exact(box, before, "released rig rejection")
	# Reconfigure/reset cycles must not accumulate coordinate drift.
	for iteration in 20:
		_check(rig.configure(box), "Reconfigure cycle " + str(iteration))
		rig.set_angles(40.0 + iteration, 100.0 - iteration)
		_check(rig.restore(), "Restore cycle " + str(iteration))
	_check_snapshot_exact(box, before, "twenty configure/restore cycles")
	# Parent translation/rotation/nonuniform scale changes cannot break joints;
	# these are external display transforms and must never be modified by rig.
	box.transform = Transform3D(Basis.from_euler(Vector3(0.2, -0.4, 0.3)).scaled(Vector3(1.3, 0.8, 1.1)), Vector3(1.5, -0.2, 3.0))
	var transformed_before := _snapshot(box)
	_check(rig.configure(box), "Configure under transformed display ancestor")
	rig.set_angles(65.0, 100.0)
	var base_world := source.global_transform
	for index in lower_local_wall.size():
		var p := lower[0].lerp(lower[1], float(index) / 8.0)
		_check((wall.global_transform * lower_local_wall[index]).distance_to(base_world * p) < TOLERANCE_M * 50.0, "Lower contact under transformed ancestor " + str(index))
		_check((wall.global_transform * upper_local_wall[index]).distance_to(box.lid.global_transform * upper_local_lid[index]) < TOLERANCE_M * 50.0, "Upper contact under transformed ancestor " + str(index))
	rig.restore()
	_check_snapshot_exact(box, transformed_before, "transformed display ancestor restore")
	# A rebuilt GameBox invalidates old references. It must not mutate new ones.
	_check(rig.configure(box), "Configure before rebuild")
	box.configure({"id": "rebuilt"})
	var rebuilt := _snapshot(box)
	_check(not rig.set_angles(50.0, 100.0), "Stale rig rejected after rebuild")
	_check(not rig.restore(), "Stale restore reports removed nodes")
	_check_snapshot_exact(box, rebuilt, "stale rig after rebuild")
	print("METRICS ", {"tested_poses": tested_poses, "max_lower_anchor_error_m": max_lower_error, "max_upper_anchor_error_m": max_upper_error, "max_rigid_vertex_error_m": max_rigid_vertex_error, "max_native_length_error_m": max_length_error})
	_finish(box)

func _check_pose(rig: RefCounted, box: Node3D, source: Node3D, wall: MeshInstance3D, spine: MeshInstance3D, before: Dictionary, wall_closed: Transform3D, spine_closed: Transform3D, lid_closed: Transform3D, lower: PackedVector3Array, lower_local_wall: PackedVector3Array, upper_local_wall: PackedVector3Array, upper_local_lid: PackedVector3Array, p1: Vector3, p2: Vector3, a: float, b: float) -> void:
	tested_poses += 1
	var label := "pose (%s, %s)" % [a, b]
	_check(rig.set_angles(a, b), label + " applies")
	var first := _independent_rotation(p1, a)
	var second := _independent_rotation(p2, b)
	var expected_lid := first * second * lid_closed
	_check(wall.transform.is_equal_approx(first * wall_closed), label + " spine wall rigid transform")
	_check(spine.transform.is_equal_approx(first * spine_closed), label + " sleeve rigid transform")
	_check(box.lid.transform.is_equal_approx(expected_lid), label + " serial joint composition")
	var max_lower := 0.0
	var max_upper := 0.0
	for index in lower_local_wall.size():
		var p := lower[0].lerp(lower[1], float(index) / 8.0)
		max_lower = maxf(max_lower, (wall.transform * lower_local_wall[index]).distance_to(p))
		max_upper = maxf(max_upper, (wall.transform * upper_local_wall[index]).distance_to(box.lid.transform * upper_local_lid[index]))
	max_lower_error = maxf(max_lower_error, max_lower)
	max_upper_error = maxf(max_upper_error, max_upper)
	_check(max_lower < TOLERANCE_M, label + " lower molded seam contact")
	_check(max_upper < TOLERANCE_M, label + " upper molded seam contact")
	# Every node retains its hierarchy; every mesh resource, array and material
	# remains untouched. Nonmoving tray/cartridge transforms are exact.
	for mesh in box.find_children("*", "MeshInstance3D", true, false):
		var old: Dictionary = before[mesh.get_instance_id()]
		_check(mesh.mesh == old.mesh, label + " original mesh resource " + str(mesh.name))
		_check(mesh.get_parent().get_instance_id() == old.parent_id, label + " hierarchy " + str(mesh.name))
		for surface in mesh.mesh.get_surface_count():
			_check(mesh.mesh.surface_get_arrays(surface) == old.arrays[surface], label + " vertices/UV/normals/indices " + str(mesh.name))
			_check(mesh.mesh.surface_get_material(surface) == old.materials[surface], label + " original material " + str(mesh.name))
			_check(mesh.get_surface_override_material(surface) == old.overrides[surface], label + " override material " + str(mesh.name))
		var closed_source: Transform3D = old.source_transform
		var expected := closed_source
		if mesh == wall or mesh == spine:
			expected = first * closed_source
		elif box.lid.is_ancestor_of(mesh):
			expected = first * second * closed_source
		else:
			_check(mesh.transform == old.transform, label + " base/cartridge unmoved " + str(mesh.name))
		var actual := _relative_transform(mesh, source)
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var vertex_error := 0.0
		for vertex in vertices:
			vertex_error = maxf(vertex_error, (actual * vertex).distance_to(expected * vertex))
		max_rigid_vertex_error = maxf(max_rigid_vertex_error, vertex_error)
		_check(vertex_error < TOLERANCE_M, label + " all vertices follow rigid motion " + str(mesh.name))
		if vertices.size() > 1:
			var length_error := absf((actual * vertices[0]).distance_to(actual * vertices[-1]) - (closed_source * vertices[0]).distance_to(closed_source * vertices[-1]))
			max_length_error = maxf(max_length_error, length_error)
			_check(length_error < TOLERANCE_M, label + " native length preserved " + str(mesh.name))

func _snapshot(box: Node3D) -> Dictionary:
	var snapshot: Dictionary = {}
	var source := box.original_model.find_child("SMS_BOX_ROOT", true, false) as Node3D
	for node in [box] + box.find_children("*", "Node3D", true, false):
		var record := {"node": node, "transform": node.transform, "global_transform": node.global_transform, "parent_id": node.get_parent().get_instance_id()}
		if node is MeshInstance3D:
			record["mesh"] = node.mesh
			record["material_override"] = node.material_override
			record["arrays"] = []
			record["materials"] = []
			record["overrides"] = []
			record["source_transform"] = _relative_transform(node, source)
			for surface in node.mesh.get_surface_count():
				record.arrays.append(node.mesh.surface_get_arrays(surface))
				record.materials.append(node.mesh.surface_get_material(surface))
				record.overrides.append(node.get_surface_override_material(surface))
			var world_vertices := PackedVector3Array()
			for surface in node.mesh.get_surface_count():
				for vertex in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					world_vertices.append(node.global_transform * vertex)
			record["world_vertices"] = world_vertices
		snapshot[node.get_instance_id()] = record
	return snapshot

func _check_snapshot_exact(box: Node3D, expected: Dictionary, label: String) -> void:
	var actual := _snapshot(box)
	_check(actual.size() == expected.size(), label + " exact node count")
	for id in expected:
		_check(actual.has(id), label + " same original node")
		if not actual.has(id):
			continue
		var original: Dictionary = expected[id]
		var current: Dictionary = actual[id]
		_check(current == original, label + " exact transforms/resources/UV/materials/world vertices " + str(original.node.name))

func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor := node
	while cursor != ancestor:
		result = cursor.transform * result
		cursor = cursor.get_parent() as Node3D
	return result

func _independent_rotation(pivot: Vector3, angle: float) -> Transform3D:
	# Independently constructs T(p) * R * T(-p), rather than helper internals.
	return Transform3D(Basis.IDENTITY, pivot) * Transform3D(Basis(Vector3.BACK, deg_to_rad(angle)), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)

func _inside_convex_mesh(instance: MeshInstance3D, point: Vector3) -> bool:
	# Native back/wall/rim are closed convex bevel boxes. Orient each face away
	# from the centroid, avoiding reliance on imported triangle winding. AABB
	# membership alone is deliberately not accepted as proof of mesh contact.
	var mesh := instance.mesh
	var center := instance.get_aabb().get_center()
	var valid_planes := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for index in range(0, count, 3):
			var a := vertices[indices[index] if not indices.is_empty() else index]
			var b := vertices[indices[index + 1] if not indices.is_empty() else index + 1]
			var c := vertices[indices[index + 2] if not indices.is_empty() else index + 2]
			var normal := (b - a).cross(c - a)
			if normal.length_squared() < 1e-20:
				continue
			normal = normal.normalized()
			if normal.dot(center - a) > 0.0:
				normal = -normal
			if normal.dot(point - a) > TOLERANCE_M:
				return false
			valid_planes += 1
	return valid_planes > 3

func _finish(box: Node3D) -> void:
	print("RESULT ", {"passed": failures.is_empty(), "checks": checks, "failures": failures})
	box.free()
	quit(0 if failures.is_empty() else 1)
