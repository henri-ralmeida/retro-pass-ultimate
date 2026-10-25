extends SceneTree
## Isolated SYNTHETIC geometry/UV fixture. Not a game manual or visual sign-off.
## Run only after the separate live QA session releases Godot:
## godot --headless --path . --script res://cosmic/test_manual_book.gd
## No private paths, commercial page content, production integration, or model edits.

const GameBox := preload("res://cosmic/game_box.gd")
const ManualBook := preload("res://cosmic/manual_book.gd")
const DualHinge := preload("res://cosmic/box_dual_hinge.gd")
const TOLERANCE_M := 0.0000002

var failures: Array[String] = []
var checks := 0
var tested_poses := 0
var fixture_path := "user://qa_synthetic_manual_book_%d.png" % OS.get_process_id()

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var image := Image.create(1039, 1455, false, Image.FORMAT_RGBA8)
	image.fill(Color("ded7c6"))
	# Four distinct corners make a later synthetic visual orientation check possible.
	image.fill_rect(Rect2i(0, 0, 100, 100), Color.RED)
	image.fill_rect(Rect2i(939, 0, 100, 100), Color.GREEN)
	image.fill_rect(Rect2i(0, 1355, 100, 100), Color.BLUE)
	image.fill_rect(Rect2i(939, 1355, 100, 100), Color.YELLOW)
	_check(image.save_png(fixture_path) == OK, "Synthetic first-page fixture saves outside the source tree")
	var texture := ImageTexture.create_from_image(image)
	var item := {"id": "qa_synthetic_book", "title": "SYNTHETIC QA ONLY", "manual_item_id": "qa_synthetic_book", "manual_pages": [fixture_path]}
	var box := GameBox.new()
	box.configure({"id": "qa_synthetic_book"})
	root.add_child(box)
	var original := _snapshot(box)
	var book := ManualBook.new()
	_check(not book.configure(box, {"id": "qa_synthetic_book", "manual_item_id": "qa_synthetic_book"}, texture), "Absent pages produce no booklet")
	_check(book.root == null and not book.configured, "Absent pages leave no instance")
	_check(not book.configure(box, item, null), "No first-page texture produces no booklet")
	var wrong: Dictionary = item.duplicate(true)
	wrong.manual_item_id = "another_game"
	_check(not book.configure(box, wrong, texture), "Mismatched manual identity rejected")
	wrong = item.duplicate(true)
	wrong.manual_game_id = "another_game"
	_check(not book.configure(box, wrong, texture), "A conflicting second identity declaration is rejected")
	wrong = item.duplicate(true)
	wrong.id = "another_game"
	wrong.manual_item_id = "another_game"
	_check(not book.configure(box, wrong, texture), "A different catalog item cannot attach to this box")
	wrong = item.duplicate(true)
	wrong.erase("manual_item_id")
	_check(not book.configure(box, wrong, texture), "An explicit manual identity binding is required")
	for path in ["https://invalid.example/page.png", "res://folder/../page.png", "//server/page.jpg", "res://missing-page.png", "res://page.pdf"]:
		wrong = item.duplicate(true)
		wrong.manual_pages = [path]
		_check(not book.configure(box, wrong, texture) and book.root == null, "Invalid or missing local first page rejected: " + path)
	for thickness in [NAN, INF, -0.001, 0.0, 0.002, "0.0008"]:
		_check(not book.configure(box, item, texture, {"thickness_m": thickness}) and book.root == null, "Invalid/oversized thickness is rejected, not compressed")
	var wide_image := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	var wide_texture := ImageTexture.create_from_image(wide_image)
	_check(not book.configure(box, item, wide_texture), "An aspect ratio that cannot span both clips is rejected, not stretched")
	_check(_snapshot(box) == original, "All failed attachment attempts leave original nodes/resources exactly unchanged")
	_check(book.configure(box, item, texture), "Valid isolated first-page fixture attaches: " + book.last_error)
	if not book.configured:
		_finish(box, book)
		return
	var report: Dictionary = book.get_report()
	var book_root: Node3D = book.root
	var book_local := book_root.transform
	var lid_closed: Transform3D = box.lid.transform
	var cover_mesh := book.cover.mesh
	var paper_mesh := book.paper.mesh
	var cover_material := book.cover.material_override as StandardMaterial3D
	var paper_material := book.paper.material_override as StandardMaterial3D
	_check(book_root.get_parent() == box.lid, "Booklet is a direct child of the original lid")
	_check(book_root.get_child_count() == 2, "Only unprinted paper volume and actual supplied cover quad exist")
	_check(book.cover.mesh is QuadMesh and book.paper.mesh is BoxMesh, "Simple independent meshes, not edited originals")
	_check(cover_material.albedo_texture == texture, "The exact host-supplied texture is used")
	_check(paper_material.roughness >= 0.9 and cover_material.roughness >= 0.9, "Paper and cover use high roughness")
	_check(not report.thickness_is_measured and report.thickness_basis == "demonstration_only_not_measured", "Demonstrative thickness is explicitly unmeasured")
	_check(absf(report.thickness_m - 0.0008) < TOLERANCE_M, "Default demonstration thickness is 0.8 mm")
	var dimensions: Vector2 = report.page_size_m
	_check(dimensions.x <= 0.120 + TOLERANCE_M and dimensions.y <= 0.176 + TOLERANCE_M, "Page remains within conservative fit envelope")
	_check(absf(dimensions.x / dimensions.y - 1039.0 / 1455.0) < 0.000001, "Native 1039:1455 aspect ratio remains unstretched")
	_check(absf(dimensions.x - 0.120) < TOLERANCE_M and absf(dimensions.y - 0.120 * 1455.0 / 1039.0) < TOLERANCE_M, "Expected fitted dimensions are approximately 120 by 168.046 mm")
	_check(report.clip_clearance_m > ManualBook.MIN_DEPTH_CLEARANCE_M and report.lid_clearance_m > ManualBook.MIN_DEPTH_CLEARANCE_M, "Both thickness clearances remain positive")
	_check((lid_closed * book_local).origin.distance_to(report.source_center_m) < TOLERANCE_M, "Booklet pose is derived from corrected closed lid coordinates")
	_check(book.cover.basis.determinant() > 0.9999, "Cover uses a proper rotation, not a mirrored transform")
	_check(book.cover.basis.x == Vector3.LEFT and book.cover.basis.y == Vector3.FORWARD and book.cover.basis.z == Vector3.DOWN, "Inside-readable geometric axes are right -X, top -Z, normal -Y")
	_check_uvs(book)
	_check(_snapshot_originals(box, original) == original, "Successful configuration does not mutate original geometry, materials, hierarchy, or poses")
	# Sampling checks relative retention/contact-clearance invariance. It is not
	# a fresh continuous collision proof or a simulation of pressure and flex.
	for direction in [1, -1]:
		for step in 231:
			var index := step if direction == 1 else 230 - step
			box.set_lid_angle(115.0 * float(index) / 230.0)
			_check_pose(book, box, book_local, lid_closed, report)
	box.set_lid_angle(0.0)
	_check(box.lid.transform == lid_closed, "Simple opening returns exactly to corrected closed pose")
	var rig := DualHinge.new()
	rig.sleeve_margin_enabled = false
	_check(rig.configure(box), "Dual rig configures without taking ownership of booklet geometry")
	if rig.configured:
		for direction in [1, -1]:
			for step in 181:
				var index := step if direction == 1 else 180 - step
				_check(rig.set_angles(90.0 * float(index) / 180.0, 10.345512025270239 * float(index) / 180.0), "Calibrated dual pose applies")
				_check_pose(book, box, book_local, lid_closed, report)
		_check(rig.restore(), "Dual rig restores without modifying the booklet")
	_check(book.root.transform == book_local and book.cover.mesh == cover_mesh and book.paper.mesh == paper_mesh, "Repeated opening cannot drift or replace booklet resources")
	_check(_snapshot_originals(box, original) == original, "Opening/return preserves all original nodes, resources, materials, arrays, and hierarchy")
	book.clear()
	_check(not is_instance_valid(book_root) and book.root == null, "Clear frees only the booklet subtree")
	_check(_snapshot(box) == original, "Clear exactly restores the original scene membership")
	book.clear()
	_check(_snapshot(box) == original, "Repeated clear is harmless")
	box.set_lid_angle(30.0)
	var opened_before := _snapshot(box)
	_check(not book.configure(box, item, texture) and book.root == null, "Attachment while open is rejected instead of resetting the rig")
	_check(_snapshot(box) == opened_before, "Open-pose rejection leaves the rig unchanged")
	box.set_lid_angle(0.0)
	_check(book.configure(box, item, texture), "Reconfigure after return succeeds")
	_check(not book.configure(box, {"id": "qa_synthetic_book", "manual_item_id": "qa_synthetic_book"}, texture) and book.root == null, "Changing to absent pages cannot retain the preceding manual")
	_check(_snapshot(box) == original, "Absent-media replacement preserves original scene")
	_check(book.configure(box, item, texture), "Configure before model rebuild")
	box.configure({"id": "qa_synthetic_book"})
	_check(not book.configured and not bool(book.get_report().configured), "A rebuilt GameBox invalidates the old booklet helper")
	book.clear()
	_check(box.lid != null, "Clearing stale booklet does not free the replacement model")
	box.configure(item)
	_check(box.manual_book != null and box.manual_book.configured, "GameBox creates the canonical booklet for explicitly bound local pages")
	if box.manual_book != null:
		_check(box.manual_book.root.get_parent() == box.lid, "Integrated booklet belongs to original lid clips")
		_check(box.manual_book.get_report().item_id == item.id, "Integrated booklet preserves same-entry identity")
	box.configure({"id":"another_game"})
	_check(box.manual_book == null and box.find_child("LocalManualBook",true,false) == null, "Changing games removes old manual without substitution")
	_finish(box, book)

func _check_pose(book: RefCounted, box: Node3D, local_pose: Transform3D, lid_closed: Transform3D, report: Dictionary) -> void:
	tested_poses += 1
	_check(book.configured and book.root.get_parent() == box.lid, "Sample retains exact lid parent")
	_check(book.root.transform == local_pose, "Sample retains exact local booklet pose")
	var source_pose: Transform3D = box.lid.transform * book.root.transform
	var motion: Transform3D = box.lid.transform * lid_closed.affine_inverse()
	var center: Vector3 = report.source_center_m
	_check(source_pose.origin.distance_to(motion * center) < TOLERANCE_M, "Sample follows approved lid motion without drift")
	var normal: Vector3 = motion.basis * Vector3.UP
	var front := motion * (center - Vector3.UP * float(report.thickness_m) * 0.5)
	var back := motion * (center + Vector3.UP * float(report.thickness_m) * 0.5)
	var lid_point := motion * Vector3(center.x, float(report.lid_inner_y_m), center.z)
	_check(absf((lid_point - back).dot(normal) - float(report.lid_clearance_m)) < TOLERANCE_M, "Sample preserves lid separation")
	for clip in report.clip_bounds_closed:
		var contact_reference := motion * Vector3(center.x, clip.end.y, center.z)
		_check(absf((front - contact_reference).dot(normal) - float(report.clip_clearance_m)) < TOLERANCE_M, "Sample preserves original clip gap without penetration")

func _check_uvs(book: RefCounted) -> void:
	var arrays: Array = book.cover.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for index in uvs.size():
		low = low.min(uvs[index])
		high = high.max(uvs[index])
		var point: Vector3 = book.cover.basis * vertices[index]
		if is_zero_approx(uvs[index].x): _check(point.x > 0.0, "Texture left maps to source +X when viewed from the cavity")
		if is_equal_approx(uvs[index].x, 1.0): _check(point.x < 0.0, "Texture right maps to source -X when viewed from the cavity")
		if is_zero_approx(uvs[index].y): _check(point.z < 0.0, "Texture top maps to source -Z")
	_check(low == Vector2.ZERO and high == Vector2.ONE, "Complete native UV rectangle is retained without crop")

func _snapshot(box: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for node in [box] + box.find_children("*", "Node3D", true, false):
		var entry := {"transform": node.transform, "parent": node.get_parent().get_instance_id()}
		if node is MeshInstance3D:
			entry.mesh = node.mesh
			entry.material = node.material_override
			entry.arrays = []
			for surface in node.mesh.get_surface_count(): entry.arrays.append(node.mesh.surface_get_arrays(surface))
		result[node.get_instance_id()] = entry
	return result

func _snapshot_originals(box: Node3D, original: Dictionary) -> Dictionary:
	var all := _snapshot(box)
	var selected: Dictionary = {}
	for id in original:
		if all.has(id): selected[id] = all[id]
	return selected

func _finish(box: Node3D, book: RefCounted) -> void:
	book.clear()
	box.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
	print("MANUAL_BOOK_TESTS ", JSON.stringify({"checks": checks, "sampled_poses": tested_poses, "failures": failures, "passed": failures.is_empty(), "visual_legibility_verified": false}))
	quit(0 if failures.is_empty() else 1)
