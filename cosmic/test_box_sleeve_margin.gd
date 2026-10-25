extends SceneTree
const GameBox := preload("res://cosmic/game_box.gd")
const DualHinge := preload("res://cosmic/box_dual_hinge.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
func run() -> void:
	var box := GameBox.new()
	box.configure({"id": "sleeve_margin_isolated_test"})
	root.add_child(box)
	var rig := DualHinge.new()
	var before := snapshot(box)
	check(rig.configure(box), "Configure corrected helper")
	var art: MeshInstance3D = box.find_child("Box_LEFT_SPINE", true, false)
	var lid_closed: Transform3D = box.lid.transform
	var original_mesh: Mesh = art.mesh
	var original_arrays: Array = original_mesh.surface_get_arrays(0)
	var art_bounds: AABB = art.get_aabb()
	var original_width := art_bounds.size.y
	var original_height := art_bounds.size.z
	var frames: Array = []
	var max_fold := 0.0
	for direction in [1, -1]:
		for step in 181:
			var index := step if direction == 1 else 180 - step
			var a := 90.0 * float(index) / 180.0
			var b := 10.345512025270239 * float(index) / 180.0
			check(rig.set_angles(a, b), "Apply %s/%s" % [direction, index])
			var margin: Dictionary = rig.get_joint_report().sleeve_margin
			max_fold = maxf(max_fold, margin.fold_degrees)
			var arrays: Array = art.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var source_vertices: Array = []
			for point in v: source_vertices.append(vec(art.transform * point))
			if art.mesh != original_mesh:
				check(v.size() == 8, "Only original sleeve split into two quads")
				check(v[1] == v[4] and v[2] == v[7], "Fold line is continuous")
				check(uv[1] == uv[4] and uv[2] == uv[7], "UVs continuous at fold line")
				check(absf(v[0].distance_to(v[1]) + v[4].distance_to(v[5]) - original_width) < 0.0000001, "Full original 22 mm geodesic width preserved")
				check(absf(v[0].distance_to(v[3]) - original_height) < 0.0000001 and absf(v[4].distance_to(v[7]) - original_height) < 0.0000001, "Original 182 mm height preserved")
				var uv_min := Vector2(INF, INF)
				var uv_max := Vector2(-INF, -INF)
				for point in uv:
					uv_min = uv_min.min(point)
					uv_max = uv_max.max(point)
				check(uv_min == Vector2.ZERO and uv_max == Vector2.ONE, "Full UV extent retained, no crop")
			else:
				check(arrays == original_arrays, "Unfolded mesh arrays exactly original")
			for mesh in box.find_children("*", "MeshInstance3D", true, false):
				if mesh != art:
					check(mesh.mesh == before[mesh.get_instance_id()].mesh, "Other mesh resource unchanged: " + str(mesh.name))
			check(art.mesh.surface_get_material(0) == original_mesh.surface_get_material(0), "Original sleeve material retained")
			var current_mesh: Mesh = art.mesh
			var current_transform: Transform3D = art.transform
			check(rig.set_angles(a, b), "Repeated same pose accepted")
			check(art.mesh == current_mesh and art.transform == current_transform, "Same pose idempotent including mesh resource")
			var motion: Transform3D = box.lid.transform * lid_closed.affine_inverse()
			frames.append({"direction": direction, "sample": index, "a": a, "b": b, "fold_degrees": margin.fold_degrees, "art_vertices_source": source_vertices, "art_indices": Array(arrays[Mesh.ARRAY_INDEX]), "lid_motion": [vec(motion.basis.x), vec(motion.basis.y), vec(motion.basis.z), vec(motion.origin)]})
	check(art.mesh == original_mesh, "Closed mesh resource restored")
	check(snapshot(box) == before, "Return to closed exactly restores every node, resource, array and world vertex")
	check(rig.restore(), "Restore succeeds")
	check(snapshot(box) == before, "Restore remains exactly closed")
	check(rig.configure(box), "Reconfigure")
	check(rig.set_angles(90.0, 10.345512025270239), "Reopen after reconfigure")
	var final_report: Dictionary = rig.get_joint_report().sleeve_margin
	rig.restore()
	check(snapshot(box) == before, "Reconfigure/reopen/restore remains exact")
	var file := FileAccess.open("user://sleeve_margin_test_frames.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": frames, "final_margin_report": final_report, "checks": checks, "failures": failures, "max_fold_degrees": max_fold}))
	print("SLEEVE_MARGIN_RESULT ", {"checks": checks, "frames": frames.size(), "failures": failures, "max_fold_degrees": max_fold, "final_report": final_report})
	box.free()
	quit(0 if failures.is_empty() else 1)
func vec(p: Vector3) -> Array: return [p.x, p.y, p.z]
func snapshot(box: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for node in [box] + box.find_children("*", "Node3D", true, false):
		var r := {"transform": node.transform, "world": node.global_transform, "parent": node.get_parent().get_instance_id()}
		if node is MeshInstance3D:
			r.mesh = node.mesh
			r.arrays = []
			r.vertices = PackedVector3Array()
			for surface in node.mesh.get_surface_count():
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				r.arrays.append(arrays)
				for vertex in arrays[Mesh.ARRAY_VERTEX]: r.vertices.append(node.global_transform * vertex)
		result[node.get_instance_id()] = r
	return result
