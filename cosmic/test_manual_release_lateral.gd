extends SceneTree
## Isolated geometry regression for the host's lateral approach candidate.
## Synthetic texture only; this does not certify viewport visibility or pixels.
const GameBox := preload("res://cosmic/game_box.gd")
const Book := preload("res://cosmic/manual_book.gd")
const Release := preload("res://cosmic/manual_release_path.gd")
const APPROACH := Vector3(0.07, 0.01, 0.0)
var checks := 0
var failures: Array[String] = []
var fixture_path := "user://qa_release_lateral_%d.png" % OS.get_process_id()

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var image := Image.create(1039, 1455, false, Image.FORMAT_RGBA8)
	image.fill(Color("ddd5c2"))
	check(image.save_png(fixture_path) == OK, "Temporary synthetic fixture saved")
	var box := GameBox.new()
	box.configure({"id": "qa_release_lateral"})
	root.add_child(box)
	var book := Book.new()
	check(book.configure(box, {"id": "qa_release_lateral", "manual_item_id": "qa_release_lateral", "manual_pages": [fixture_path]}, ImageTexture.create_from_image(image)), "Canonical booklet configured")
	var release := Release.new()
	if book.configured:
		box.set_lid_angle(115.0)
		box.cartridge.position.y += 0.13
		box.opened = true
		box.cartridge_out = true
		var original_root: Transform3D = book.root.transform
		var paper_original: Mesh = book.paper.mesh
		var cover_original: Mesh = book.cover.mesh
		var original_nodes := snapshot_originals(box, book.root)
		check(release.configure(box, book, {"approach_offset_source_m": APPROACH}), "Lateral profile validates in actual presented pose: " + release.last_error)
		print("LATERAL_RELEASE_PROFILE ", release.get_report())
		if release.configured:
			var report := release.get_report()
			check(report.pose_validated and report.approach_offset_source_m == APPROACH, "Requested approach is certified without changing it")
			check(int(report.volume_pair_tests) == 29640, "All 24 obstacle volumes and 65 strips are checked over 19 continuous intervals")
			check(float(report.minimum_certified_axis_gap_m) >= Release.CLEARANCE_M, "Every swept volume retains required separation")
			var before_approach := Vector3(release.sample(0.85).offset_source_m)
			var final_offset := Vector3(release.sample(1.0).offset_source_m)
			check((final_offset - before_approach).is_equal_approx(APPROACH), "Only last phase adds the requested lateral displacement")
			check(absf(final_offset.x - 0.1026) < 0.00001 and absf(final_offset.y + 0.02) < 0.000001, "Endpoint is source +102.6 mm / -20 mm")
			check(is_zero_approx(float(release.sample(1.0).bend_radians)), "Endpoint remains flat for source-pose reader binding")
			for direction in [1, -1]:
				for step in 101:
					var p := float(step if direction == 1 else 100 - step) / 100.0
					check(release.apply_progress(p), "Apply forward/reverse lateral path")
					check(snapshot_originals(box, book.root) == original_nodes, "Original box, clips and presented cartridge remain exact")
					check(book.root.get_parent() == box.lid, "Book remains the original lid child")
					if p == 1.0:
						check(book.paper.mesh == paper_original and book.cover.mesh == cover_original, "Released endpoint uses the original flat mesh resources")
			check(book.root.transform == original_root and book.paper.mesh == paper_original and book.cover.mesh == cover_original, "Inverse path restores exact source geometry")
			release.apply_progress(0.92)
			release.restore()
			check(book.root.transform == original_root and book.paper.mesh == paper_original and book.cover.mesh == cover_original, "Synchronous teardown from lateral approach restores exactly")
		release.clear()
		check(release.configure(box, book), "Original default profile still validates")
		check(release.get_report().get("approach_offset_source_m") == Vector3(0.0, -0.02, 0.0), "Default helper approach remains unchanged")
	release.clear()
	book.clear()
	box.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture_path))
	print("MANUAL_RELEASE_LATERAL_TESTS ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty(), "visual_pixels_verified": false, "projected_occlusion_verified": false}))
	quit(0 if failures.is_empty() else 1)

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
