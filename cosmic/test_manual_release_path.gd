extends SceneTree
## Isolated synthetic media; uses the actual public box geometry and canonical
## ManualBook. No game-page content or source assets are modified.
const GameBox := preload("res://cosmic/game_box.gd")
const Book := preload("res://cosmic/manual_book.gd")
const Release := preload("res://cosmic/manual_release_path.gd")
var failures: Array[String] = []
var checks := 0
var apply_time_total_usec := 0
var apply_time_max_usec := 0
var apply_time_samples := 0
var fixture_path := "user://qa_release_%d.png" % OS.get_process_id()

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var image := Image.create(1039, 1455, false, Image.FORMAT_RGBA8)
	image.fill(Color("ddd5c2"))
	check(image.save_png(fixture_path) == OK, "Synthetic fixture saved outside project")
	var texture := ImageTexture.create_from_image(image)
	var box := GameBox.new()
	box.configure({"id": "qa_release"})
	root.add_child(box)
	var book := Book.new()
	check(book.configure(box, {"id": "qa_release", "manual_item_id": "qa_release", "manual_pages": [fixture_path]}, texture), "Canonical synthetic booklet attaches")
	if not book.configured:
		_finish(box, book, null)
		return
	box.set_lid_angle(115.0)
	box.cartridge.position.y += 0.13
	box.opened = true
	box.cartridge_out = true
	var native_before := snapshot_originals(box, book.root)
	var root_rest: Transform3D = book.root.transform
	var paper_original: Mesh = book.paper.mesh
	var cover_original: Mesh = book.cover.mesh
	var paper_arrays: Array = paper_original.surface_get_arrays(0)
	var cover_arrays: Array = cover_original.surface_get_arrays(0)
	var paper_material: Material = book.paper.material_override
	var cover_material: Material = book.cover.material_override
	var release := Release.new()
	check(release.configure(box, book), "Flex profile validates: " + release.last_error)
	if not release.configured:
		print("BLOCKER ", release.get_report())
		_finish(box, book, release)
		return
	var report: Dictionary = release.get_report()
	print("RELEASE_PROFILE ", report)
	check(report.pose_validated and int(report.swept_interval_count) == 2 * Release.INTERVALS_PER_PHASE + 3, "All five phases have continuous swept-volume certification")
	check(float(report.minimum_certified_axis_gap_m) >= Release.CLEARANCE_M, "All original obstacle envelopes remain separated")
	check(float(report.rigid_slide_required_m) > float(report.rigid_right_rim_clearance_m) * 5.0, "Rigid planar slide is correctly identified as geometrically insufficient")
	check(absf(float(report.slide_offset_source_m.x) - 0.0326) < 0.00001, "Release slide derives from actual clip endpoint")
	check(float(report.curved_right_rim_clearance_m) > 0.0025, "90 degree free-paper bend leaves measurable right-rim clearance")
	check(snapshot_originals(box, book.root) == native_before, "Configuration does not move original geometry")
	check(book.root.transform == root_rest and book.paper.mesh == paper_original and book.cover.mesh == cover_original, "Configuration does not move or replace the book")
	var held := Vector3(float(report.bend_start_local_x_m) - 0.0005, -0.0004, 0.065)
	for p in [0.0, 0.05, 0.15, 0.23]:
		check(release.deform_point(held, p) == held, "Paper beneath clips remains exactly flat while free region curls")
		check(Vector3(release.sample(p).offset_source_m) == Vector3.ZERO, "No slide/lift before initial curl finishes")
	check(release.sample(0.48).offset_source_m.y == 0.0, "No lift before projected clip release")
	check(is_zero_approx(float(release.sample(1.0).bend_radians)), "Endpoint is a flat canonical booklet")
	for direction in [1, -1]:
		for step in 101:
			var p := float(step if direction == 1 else 100 - step) / 100.0
			var apply_started := Time.get_ticks_usec()
			check(release.apply_progress(p), "Apply bounded forward/reverse pose")
			var apply_usec := Time.get_ticks_usec() - apply_started
			apply_time_total_usec += apply_usec
			apply_time_max_usec = maxi(apply_time_max_usec, apply_usec)
			apply_time_samples += 1
			check(book.root.get_parent() == box.lid, "Book remains with original lid parent")
			check(snapshot_originals(box, book.root) == native_before, "Clips, rims, lid, base, cartridge and materials remain unchanged")
			check(book.paper.material_override == paper_material and book.cover.material_override == cover_material, "Canonical material/cover texture is retained")
			for point in [held, Vector3(0.0, 0.0004, 0.0), Vector3(0.06, -0.0004, 0.084)]:
				var bent: Vector3 = release.deform_point(point, p)
				var normal: Vector3 = release.deform_normal(Vector3.DOWN, point, p)
				check(bent.is_finite() and normal.is_finite() and absf(normal.length() - 1.0) < 0.000001, "Bending positions/normals remain finite and normalized")
			if step == 35 and direction == 1:
				check(book.paper.mesh is ArrayMesh and book.cover.mesh is ArrayMesh, "Curved paper uses actual subdivided meshes, not a planar proxy")
				check_mesh_vertices(book, release, p)
	check(book.root.transform == root_rest and book.paper.mesh == paper_original and book.cover.mesh == cover_original, "Inverse path restores exact original root and mesh resources")
	check(paper_original.surface_get_arrays(0) == paper_arrays and cover_original.surface_get_arrays(0) == cover_arrays, "Original mesh arrays were never edited")
	for invalid in [-0.1, 1.1, NAN, INF]:
		check(not release.apply_progress(invalid), "Invalid/out-of-range progress rejected")
		check(book.root.transform == root_rest, "Invalid progress cannot move the book")
	check(release.begin_release(), "Begin release")
	release.tick(0.1, false)
	check(release.progress == 0.0, "Focus loss pauses without consuming time")
	release.tick(NAN)
	release.tick(-1.0)
	check(release.progress == 0.0, "Invalid time ignored")
	release.tick(0.1)
	var partial := release.progress
	check(partial > 0.0 and partial < 1.0, "Focused ticking advances bounded progress")
	check(release.abort(), "Abort requests exact inverse path")
	release.tick(0.05)
	check(release.progress < partial and release.progress > 0.0, "Abort reverses rather than teleporting")
	check(release.begin_release(), "Reversal can resume outward along the same path")
	for index in 40: release.tick(0.1)
	check(release.progress == 1.0 and release.state == "released", "Release reaches exact endpoint")
	check(book.paper.mesh == paper_original and book.cover.mesh == cover_original, "Released endpoint is the original flat mesh, suitable for reader binding")
	check(release.begin_return(true), "Reduced-motion return uses validated endpoint")
	check(release.progress == 0.0 and book.root.transform == root_rest, "Reduced-motion return restores exact rest")
	check(release.begin_release(true), "Reduced-motion release remains within previously certified path")
	check(release.progress == 1.0, "Reduced-motion release reaches endpoint")
	release.restore()
	check(book.root.transform == root_rest and book.paper.mesh == paper_original and book.cover.mesh == cover_original, "Synchronous teardown restores exact canonical geometry")
	release.clear()
	var unsafe := Release.new()
	check(not unsafe.configure(box, book, {"lift_distance_m": 0.001}), "Insufficient lift is rejected, not silently raised")
	check(book.root.transform == root_rest and book.paper.mesh == paper_original, "Rejected lift never modifies book")
	unsafe.clear()
	check(not unsafe.configure(box, book, {"approach_offset_source_m": Vector3(0.0, 0.1, 0.0)}), "Approach back through original lid is rejected")
	check(unsafe.get_report().has("collision"), "Blocked path identifies phase and original obstacle")
	print("RELEASE_EXPECTED_BLOCKER ", unsafe.get_report())
	unsafe.clear()
	check(release.configure(box, book), "Reconfigure after restoration")
	var clip: Node3D = box.lid.find_child("Manual_clip", true, false)
	var clip_pose := clip.transform
	clip.position.x += 0.0001
	check(not release.apply_progress(0.1), "Changed obstacle geometry invalidates path before movement")
	check(book.root.transform == root_rest, "Invalidated path stops without crossing unknown space")
	clip.transform = clip_pose
	release.restore()
	check(snapshot_originals(box, book.root) == native_before, "Failure injection and restoration leave original scene exact")
	_finish(box, book, release)

func check_mesh_vertices(book: RefCounted, release: RefCounted, p: float) -> void:
	for record in release._meshes:
		var node: MeshInstance3D = record.node
		var current: Array = node.mesh.surface_get_arrays(0)
		var template: Array = record.template
		var verts: PackedVector3Array = current[Mesh.ARRAY_VERTEX]
		var base: PackedVector3Array = template[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = current[Mesh.ARRAY_NORMAL]
		check(verts.size() > 200 and verts.size() == base.size(), "Meshes have longitudinal subdivisions")
		for index in verts.size():
			var expected: Vector3 = release.deform_point(record.transform * base[index], p)
			check((record.transform * verts[index]).distance_to(expected) < 0.0000002, "Applied mesh vertex matches certified deformation")
			check(normals[index].is_finite() and absf(normals[index].length() - 1.0) < 0.000002, "Applied mesh normal is finite/unit")
		check(current[Mesh.ARRAY_TEX_UV] == template[Mesh.ARRAY_TEX_UV], "Bending never changes UV coordinates or commercial image content")
	check(book.cover.material_override.albedo_texture != null, "Real host texture binding remains intact in synthetic test")

func snapshot_originals(box: Node3D, book_root: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for node in [box] + box.find_children("*", "Node3D", true, false):
		if node == book_root or book_root.is_ancestor_of(node): continue
		var entry := {"transform": node.transform, "parent": node.get_parent().get_instance_id()}
		if node is MeshInstance3D:
			entry.mesh = node.mesh
			entry.material = node.material_override
		result[node.get_instance_id()] = entry
	return result

func _finish(box: Node3D, book: RefCounted, release: RefCounted) -> void:
	if release: release.clear()
	book.clear()
	box.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
	print("MANUAL_RELEASE_PATH_TESTS ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty(), "visual_pixels_verified": false, "apply_mean_usec": float(apply_time_total_usec) / maxf(apply_time_samples, 1), "apply_max_usec": apply_time_max_usec}))
	quit(0 if failures.is_empty() else 1)
