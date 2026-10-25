extends SceneTree
## Geometry-only regression. Real visual QA remains separate.
## The shared axis belongs to both original molded volumes, so contact is
## invariant continuously, not merely at the 461 sampled quarter-degree poses.

const MODEL := "res://assets/library_models/master_system_box_cartridge.glb"
const ORIGINAL_SHA256 := "9f185f9483654504862ccf4e030852fe9915a8adee022e9b8b0acbd18d3c3d49"
var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	while node != ancestor:
		result = node.transform * result
		node = node.get_parent()
	return result

func transform_error(actual: Transform3D, expected: Transform3D) -> float:
	return maxf(actual.origin.distance_to(expected.origin), maxf(
		actual.basis.x.distance_to(expected.basis.x), maxf(
		actual.basis.y.distance_to(expected.basis.y), actual.basis.z.distance_to(expected.basis.z))))

func convex_planes(mesh: MeshInstance3D) -> Array[Plane]:
	var planes: Array[Plane] = []
	var center := mesh.get_aabb().get_center()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in range(0, indices.size(), 3):
			var a := vertices[indices[index]]
			var b := vertices[indices[index + 1]]
			var c := vertices[indices[index + 2]]
			var normal := (b - a).cross(c - a)
			if normal.length_squared() < 1e-20: continue
			normal = normal.normalized()
			if normal.dot(center - a) > 0.0: normal = -normal
			planes.append(Plane(normal, a))
	return planes

func exterior_distance(point: Vector3, planes: Array[Plane]) -> float:
	var distance := -INF
	for plane in planes: distance = maxf(distance, plane.distance_to(point))
	return distance

func run() -> void:
	check(FileAccess.get_sha256(MODEL) == ORIGINAL_SHA256, "Original GLB remains byte-for-byte unchanged")
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	check(document.append_from_file(ProjectSettings.globalize_path(MODEL), state) == OK, "Original model loads")
	var source := document.generate_scene(state)
	var source_box := source.find_child("SMS_BOX_ROOT", true, false) as Node3D
	var box = load("res://cosmic/game_box.gd").new()
	root.add_child(box)
	box.configure({"id":"hinge_regression","title":"Hinge geometry regression"})
	check(box.can_open() and box.get_meta("hinge_pivot_repaired", false), "Original articulated hinge repaired at runtime")
	var box_root := box.original_model.find_child("SMS_BOX_ROOT", true, false) as Node3D
	var lid := box.lid as Node3D
	var wall := box_root.find_child("Case_wall", true, false) as MeshInstance3D
	var rim := lid.find_child("Lid_rim", true, false) as MeshInstance3D
	check(lid.position.distance_to(Vector3(-0.0673, 0.023, 0.0)) < 0.0000001, "Axis uses existing spine wall's outer top edge in source metres")
	check(lid.get_parent() == box_root, "Lid remains in original box hierarchy")
	var closed_bounds: AABB = box.get_local_bounds()
	var max_closed_world_error := 0.0
	var lid_closed: Dictionary = {}
	var fixed_closed: Dictionary = {}
	var compared_meshes := 0
	for original in source_box.find_children("*", "MeshInstance3D", true, false):
		var actual := box_root.find_child(str(original.name), true, false) as MeshInstance3D
		check(actual != null, "Original mesh retained: " + str(original.name))
		var expected_world: Transform3D = box.original_model.global_transform * relative_transform(original, source_box)
		max_closed_world_error = maxf(max_closed_world_error, transform_error(actual.global_transform, expected_world))
		for surface in original.mesh.get_surface_count():
			var before: PackedVector3Array = original.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var after: PackedVector3Array = actual.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			check(before == after, "Source vertex arrays preserved: " + str(original.name))
			for index in before.size():
				max_closed_world_error = maxf(max_closed_world_error, (actual.global_transform * after[index]).distance_to(expected_world * before[index]))
		if lid.is_ancestor_of(actual):
			lid_closed[actual] = lid.global_transform.affine_inverse() * actual.global_transform
		else:
			fixed_closed[actual] = actual.global_transform
		compared_meshes += 1
	check(max_closed_world_error < 0.000002, "All closed WORLD transforms and vertices preserve source geometry to float precision")
	check(compared_meshes == 18, "All original box meshes retained without added hinge or replacement panels")
	check(lid.is_ancestor_of(box_root.find_child("Box_FRONT", true, false)), "Front sleeve belongs to articulated lid")
	check(not lid.is_ancestor_of(box_root.find_child("Box_BACK", true, false)), "Back sleeve belongs to base")
	check(not lid.is_ancestor_of(box_root.find_child("Box_LEFT_SPINE", true, false)), "Spine sleeve belongs to base")
	var wall_planes := convex_planes(wall)
	var rim_planes := convex_planes(rim)
	check(not wall_planes.is_empty() and not rim_planes.is_empty(), "Contact uses actual original triangle planes, not bounding boxes")
	var joint := lid.position
	var max_axis_drift := 0.0
	var max_joint_exterior := -INF
	var max_rigid_error := 0.0
	for sample in range(461):
		var angle := float(sample) * 0.25
		box.set_lid_angle(angle)
		for z in [-0.09, 0.0, 0.09]:
			var expected: Vector3 = box_root.global_transform * (joint + Vector3(0, 0, z))
			var actual: Vector3 = lid.global_transform * Vector3(0, 0, z)
			max_axis_drift = maxf(max_axis_drift, actual.distance_to(expected))
			# The same world-space material point lies in both actual volumes at
			# three spine cross sections. Rotation about it cannot tear the join.
			max_joint_exterior = maxf(max_joint_exterior, exterior_distance(wall.to_local(actual), wall_planes))
			max_joint_exterior = maxf(max_joint_exterior, exterior_distance(rim.to_local(actual), rim_planes))
		for part in lid_closed:
			max_rigid_error = maxf(max_rigid_error, transform_error(part.global_transform, lid.global_transform * lid_closed[part]))
		for part in fixed_closed:
			max_rigid_error = maxf(max_rigid_error, transform_error(part.global_transform, fixed_closed[part]))
		if angle in [0.0, 30.0, 60.0, 90.0, 115.0]:
			check(max_rigid_error < 0.000002, "No detached planes or nonrigid lid parts at " + str(angle) + " degrees")
	check(max_axis_drift < 0.000002, "Joint is stationary for all 461 poses")
	check(max_joint_exterior < 0.0000002, "Actual rim and spine wall remain in contact throughout 0-115 degrees")
	check(max_rigid_error < 0.000002, "All moving parts/artwork rigidly follow the lid; base remains fixed")
	box.set_lid_angle(-100.0)
	check(is_zero_approx(lid.rotation.z), "Pose setter clamps below closed")
	box.set_lid_angle(500.0)
	check(is_equal_approx(rad_to_deg(lid.rotation.z), 115.0), "Pose setter clamps above open")
	box.set_lid_angle(NAN)
	check(is_finite(lid.rotation.z), "Pose setter rejects nonfinite angle")
	box.set_lid_angle(0.0)
	for cycle in range(20):
		box.toggle_lid()
		box.toggle_lid()
	check(box.get_local_bounds().is_equal_approx(closed_bounds), "Repeated close restores exact original closed extent")
	box.configure({"id":"hinge_reconfigured","title":"Reconfigured hinge"})
	check(box.lid.position.distance_to(joint) < 0.0000001, "Reconfigure does not accumulate pivot compensation")
	check(box.get_local_bounds().is_equal_approx(closed_bounds), "Reconfigure preserves closed source geometry")
	print("BOX_HINGE_TESTS ", JSON.stringify({"assertions":assertions,"passed":failures.is_empty(),"failures":failures,"samples":461,"joint_source_metres":str(joint),"compared_source_meshes":compared_meshes,"max_closed_world_error":max_closed_world_error,"max_axis_world_drift":max_axis_drift,"max_contact_exterior_source_metres":max_joint_exterior,"max_rigid_world_error":max_rigid_error}))
	source.free()
	box.free()
	quit(0 if failures.is_empty() else 1)
