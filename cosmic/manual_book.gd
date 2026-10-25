extends RefCounted
## Optional display-only booklet under the ORIGINAL lid clips. No file decoder,
## animation, input, reader, camera, source-model edits, or embedded game media.
## configure(box, item, first_page_texture, options={}) must run while CLOSED,
## after GameBox has corrected its hinge and before a presentation rig opens it.
## The host must validate/authenticate its local pages and supply the decoded
## texture of EXACTLY item.manual_pages[0]. This helper cannot authenticate art.
## An explicit matching manual_item_id or manual_game_id is required as well as
## the box's matching item_id. Missing/invalid media creates no substitute.
## Default 0.8 mm thickness is a DISPLAY ASSUMPTION, NOT a physical measurement
## or a thickness inferred from page count. An oversized request is rejected,
## never compressed. All dimensions below are source metres, before display.
## clear() removes only this helper's own subtree. It never restores/moves a rig.

const MAX_RECT_M := Vector2(0.120, 0.176)
const DEFAULT_THICKNESS_M := 0.0008
const EDGE_MARGIN_M := 0.0045
const MIN_DEPTH_CLEARANCE_M := 0.00005
const CLIP_END_MARGIN_M := 0.001
const MIN_CLIP_OVERLAP_M := 0.005
const COVER_SEPARATION_M := 0.00005
const MAX_PAGES := 128
const MAX_FILE_BYTES := 8 * 1024 * 1024
const MAX_TEXTURE_EDGE := 4096
const EPS_M := 0.0000002

var root: Node3D
var paper: MeshInstance3D
var cover: MeshInstance3D
var last_error := ""
var configured: bool:
	get: return _references_valid()

var _box: Node3D
var _lid: Node3D
var _report: Dictionary = {}

func configure(box: Node3D, item: Dictionary, first_page_texture: Texture2D, options: Dictionary = {}) -> bool:
	# A new attempt discards the old booklet, even when the new item has no media.
	# This prevents a previous game's manual surviving a catalog selection change.
	clear()
	var media_error := _media_error(box, item, first_page_texture)
	if not media_error.is_empty(): return _fail(media_error)
	var candidate_lid := box.get("lid") as Node3D
	if not is_instance_valid(candidate_lid) or not bool(box.get_meta("hinge_pivot_repaired", false)):
		return _fail("The original lid with its approved hinge correction is required.")
	if bool(box.get("opened")) or not candidate_lid.basis.is_equal_approx(Basis.IDENTITY):
		return _fail("Attach the booklet only in the corrected closed pose, before opening the rig.")
	var corrected: Variant = box.get_meta("corrected_hinge_origin", null)
	if not corrected is Vector3 or candidate_lid.position.distance_to(corrected) > EPS_M:
		return _fail("The lid is not at its corrected closed origin.")
	var shell := _named_mesh(candidate_lid, "Case_lid")
	var left := _named_mesh(candidate_lid, "Lid_rim")
	var right := _named_mesh(candidate_lid, "Lid_rim_001")
	var bottom := _named_mesh(candidate_lid, "Lid_rim_002")
	var top := _named_mesh(candidate_lid, "Lid_rim_003")
	var clip_a := _named_mesh(candidate_lid, "Manual_clip")
	var clip_b := _named_mesh(candidate_lid, "Manual_clip_001")
	for part in [shell, left, right, bottom, top, clip_a, clip_b]:
		if not is_instance_valid(part) or not part.mesh or part.mesh.get_surface_count() == 0:
			return _fail("The original lid, four rims, and two manual clips must be readable.")
		if part.get_parent() != candidate_lid or not part.basis.is_equal_approx(Basis.IDENTITY):
			return _fail("Unexpected lid-piece hierarchy/orientation; the helper will not remodel it.")
	var lid_closed := candidate_lid.transform
	var shell_bounds := _source_bounds(shell, lid_closed)
	var left_bounds := _source_bounds(left, lid_closed)
	var right_bounds := _source_bounds(right, lid_closed)
	var bottom_bounds := _source_bounds(bottom, lid_closed)
	var top_bounds := _source_bounds(top, lid_closed)
	var clip_bounds: Array[AABB] = [_source_bounds(clip_a, lid_closed), _source_bounds(clip_b, lid_closed)]
	for bounds in [shell_bounds, left_bounds, right_bounds, bottom_bounds, top_bounds, clip_bounds[0], clip_bounds[1]]:
		if not _valid_solid_bounds(bounds):
			return _fail("Original lid geometry has empty, nonfinite, or degenerate vertex bounds.")
	var clip_top_y := maxf(clip_bounds[0].end.y, clip_bounds[1].end.y)
	var lid_inner_y := shell_bounds.position.y
	var gap := lid_inner_y - clip_top_y
	var requested: Variant = options.get("thickness_m", DEFAULT_THICKNESS_M)
	if not requested is float and not requested is int:
		return _fail("Booklet thickness must be a finite number of source metres.")
	var thickness := float(requested)
	if not is_finite(thickness) or thickness <= COVER_SEPARATION_M * 2.0:
		return _fail("Booklet thickness must be finite and positive.")
	if thickness >= gap:
		return _fail("Requested booklet thickness exceeds the original clip gap; no compression was applied.")
	if gap - thickness < MIN_DEPTH_CLEARANCE_M * 2.0:
		return _fail("Requested booklet thickness leaves insufficient clearance; no compression was applied.")
	var opening_min := Vector2(left_bounds.end.x, top_bounds.end.z)
	var opening_max := Vector2(right_bounds.position.x, bottom_bounds.position.z)
	var opening_size := opening_max - opening_min
	var fit_size := (opening_size - Vector2.ONE * EDGE_MARGIN_M * 2.0).min(MAX_RECT_M)
	if not fit_size.is_finite() or fit_size.x <= 0.0 or fit_size.y <= 0.0:
		return _fail("The existing lid has no usable conservative rectangular area.")
	var texture_size := Vector2(first_page_texture.get_width(), first_page_texture.get_height())
	var fit_scale := minf(fit_size.x / texture_size.x, fit_size.y / texture_size.y)
	var size_m := texture_size * fit_scale
	# Preserve the binding-side alignment when a narrow portrait uses less width.
	var x_min := opening_min.x + EDGE_MARGIN_M
	var x_max := x_min + size_m.x
	var center_z := (opening_min.y + opening_max.y) * 0.5
	var z_min := center_z - size_m.y * 0.5
	var z_max := center_z + size_m.y * 0.5
	for clip in clip_bounds:
		var overlap := minf(x_max, clip.end.x) - maxf(x_min, clip.position.x)
		if overlap < MIN_CLIP_OVERLAP_M or z_min > clip.position.z - CLIP_END_MARGIN_M or z_max < clip.end.z + CLIP_END_MARGIN_M:
			return _fail("The unstretched first-page aspect ratio cannot span both original clips safely.")
	var center := Vector3((x_min + x_max) * 0.5, (clip_top_y + lid_inner_y) * 0.5, center_z)
	var source_pose := Transform3D(Basis.IDENTITY, center)
	var local_pose := lid_closed.affine_inverse() * source_pose
	_box = box
	_lid = candidate_lid
	root = Node3D.new()
	root.name = "LocalManualBook"
	root.transform = local_pose
	root.set_meta("manual_item_id", str(item.id))
	root.set_meta("thickness_is_measured", false)
	root.set_meta("thickness_basis", "demonstration_only_not_measured")
	root.set_meta("cover_source", "host_supplied_manual_pages_0_no_fallback")
	_build_paper(size_m, thickness)
	_build_cover(first_page_texture, size_m, thickness)
	_lid.add_child(root)
	_report = {
		"coordinate_frame": "SMS_BOX_ROOT native metres, before display rotation/scale",
		"item_id": str(item.id), "page_count": item.manual_pages.size(),
		"cover_source": "host_supplied_manual_pages_0_no_fallback",
		"texture_size": Vector2i(first_page_texture.get_width(), first_page_texture.get_height()),
		"page_size_m": size_m, "thickness_m": thickness,
		"thickness_is_measured": false, "thickness_basis": "demonstration_only_not_measured",
		"clip_gap_m": gap, "clip_clearance_m": center.y - thickness * 0.5 - clip_top_y,
		"lid_clearance_m": lid_inner_y - center.y - thickness * 0.5,
		"source_center_m": center, "source_bounds_m": AABB(Vector3(x_min, center.y - thickness * 0.5, z_min), Vector3(size_m.x, thickness, size_m.y)),
		"closed_lid_pose": lid_closed, "book_local_pose": local_pose,
		"clip_bounds_closed": clip_bounds, "lid_inner_y_m": lid_inner_y,
		"cover_normal_source": Vector3.DOWN, "page_top_source": Vector3.FORWARD,
		"page_right_source": Vector3.LEFT, "full_texture_uv": true,
		"page_size_is_measured": false,
		"content_validation": "Host-supplied first-page texture; catalog identity checked, scan authenticity not inferred.",
		"limitations": ["Display thickness is not measured or inferred from page count.", "No clip pressure, paper flex, or OEM mechanical accuracy is claimed.", "UV orientation and legibility require pixel-level visual QA."]
	}
	last_error = ""
	return true

func get_report() -> Dictionary:
	if not _references_valid(): return {"configured": false, "error": last_error}
	var result := _report.duplicate(true)
	result["configured"] = true
	return result

func clear() -> void:
	if is_instance_valid(root):
		if root.get_parent(): root.get_parent().remove_child(root)
		root.free()
	root = null
	paper = null
	cover = null
	_box = null
	_lid = null
	_report.clear()
	last_error = ""

func _build_paper(size_m: Vector2, thickness: float) -> void:
	paper = MeshInstance3D.new()
	paper.name = "UnprintedPaperVolume"
	var shape := BoxMesh.new()
	# The 50 micrometre separation belongs INSIDE the declared thickness envelope.
	# A 2 micrometre gap flickered at native-scale reader distances in Compatibility.
	# It separates the real cover quad from the unprinted front of the paper body.
	shape.size = Vector3(size_m.x, thickness - COVER_SEPARATION_M, size_m.y)
	paper.mesh = shape
	paper.position.y = COVER_SEPARATION_M * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("eee9dc")
	material.roughness = 0.94
	material.metallic = 0.0
	paper.material_override = material
	root.add_child(paper)

func _build_cover(texture: Texture2D, size_m: Vector2, thickness: float) -> void:
	cover = MeshInstance3D.new()
	cover.name = "ValidatedFirstPage"
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Z
	quad.size = size_m
	cover.mesh = quad
	# A readable INSIDE-facing quad has right=-X, top=-Z, normal=-Y.
	# right x top = normal. Keeping right=+X with the same top would display
	# its reverse side to the cavity and mirror text. Use a proper rotation,
	# unchanged complete UVs, and verify the real scan's pixels in visual QA.
	cover.basis = Basis(Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN)
	cover.position.y = -thickness * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	material.roughness = 0.95
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	cover.material_override = material
	root.add_child(cover)

func _media_error(box: Node3D, item: Dictionary, texture: Texture2D) -> String:
	if not is_instance_valid(box) or box.is_queued_for_deletion(): return "GameBox is missing."
	var identity: Variant = item.get("id", "")
	if not identity is String or identity.strip_edges().is_empty(): return "A catalog item identity is required."
	if str(box.get("item_id")) != identity: return "The booklet item does not match this box."
	var declared := false
	for field in ["manual_item_id", "manual_game_id"]:
		if item.has(field):
			declared = true
			if not item[field] is String or item[field] != identity: return "The manual identity does not match this item."
	if not declared: return "An explicit matching manual_item_id or manual_game_id is required."
	var pages: Variant = item.get("manual_pages", [])
	if not pages is Array or pages.is_empty(): return "No local manual pages are available; no booklet was created."
	if pages.size() > MAX_PAGES: return "The local manual exceeds the page limit."
	for page in pages:
		if not page is String or not _path_allowed(page): return "Manual pages must use local PNG/JPEG paths."
	var file := FileAccess.open(pages[0], FileAccess.READ)
	if file == null: return "The first local manual page is unavailable."
	var length := file.get_length()
	file.close()
	if length <= 0 or length > MAX_FILE_BYTES: return "The first manual page is empty or exceeds the byte limit."
	if not is_instance_valid(texture): return "The host did not supply a validated first-page texture."
	if texture.get_width() <= 0 or texture.get_height() <= 0 or texture.get_width() > MAX_TEXTURE_EDGE or texture.get_height() > MAX_TEXTURE_EDGE:
		return "The supplied first-page texture has invalid or excessive dimensions."
	return ""

func _path_allowed(path: String) -> bool:
	if path.is_empty() or path.length() > 4096: return false
	for index in path.length():
		if path.unicode_at(index) < 32: return false
	if path.get_extension().to_lower() not in ["png", "jpg", "jpeg"]: return false
	if "://" in path and not path.begins_with("res://") and not path.begins_with("user://"): return false
	if not path.is_absolute_path() or path.begins_with("\\\\") or path.begins_with("//"): return false
	return ".." not in path.replace("\\", "/").split("/")

func _named_mesh(lid: Node3D, expected: String) -> MeshInstance3D:
	for child in lid.get_children():
		if child is MeshInstance3D and str(child.name).replace(".", "_") == expected:
			return child
	return null

func _source_bounds(part: MeshInstance3D, closed_lid: Transform3D) -> AABB:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var transform := closed_lid * part.transform
	for surface in part.mesh.get_surface_count():
		for vertex in part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var point: Vector3 = transform * vertex
			low = low.min(point)
			high = high.max(point)
	return AABB(low, high - low)

func _valid_solid_bounds(bounds: AABB) -> bool:
	return bounds.position.is_finite() and bounds.end.is_finite() and bounds.size.is_finite() and bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.size.z > 0.0

func _references_valid() -> bool:
	return is_instance_valid(root) and not root.is_queued_for_deletion() and is_instance_valid(_box) and not _box.is_queued_for_deletion() and is_instance_valid(_lid) and not _lid.is_queued_for_deletion() and _box.get("lid") == _lid and root.get_parent() == _lid and _box.is_ancestor_of(_lid)

func _fail(message: String) -> bool:
	last_error = message
	return false
