extends Node3D
## Display-only physical box with explicitly supplied local sleeve art. No ROMs or launches.
## The sleeve uses separate front/back/spine textures. Front is +Z; spine is -X.
## configure() is safe before or after add_child(); each call replaces the model.

const BOX_SIZE := Vector3(1.74, 2.44, 0.30)
const CORNER_RADIUS := 0.025
const SURFACE_OFFSET := 0.001
const LID_OPEN_DEGREES := 115.0

var item: Dictionary = {}
var item_id := "unavailable"
var title := "Capa indisponível"
var _built := false
var original_model: Node3D
var lid: Node3D
var cartridge: Node3D
var opened := false
var cartridge_out := false
var inside_pose := Transform3D(Basis(Vector3.RIGHT, -PI*0.5), Vector3(0,0.0135,0.036))

func _ready() -> void:
	if not _built:
		configure(item)

func configure(data: Dictionary) -> void:
	item = data.duplicate(true)
	item_id = str(data.get("id", "unavailable"))
	title = str(data.get("title", "Capa indisponível"))
	for child in get_children():
		remove_child(child)
		child.queue_free()
	original_model = null
	lid = null
	cartridge = null
	opened = false
	cartridge_out = false
	_built = true
	name = "LibraryBox_" + item_id
	set_meta("fictional", false)
	set_meta("artwork_source", str(data.get("artwork_source", "local, unverified")))
	set_meta("rom_present", false)
	set_meta("display_title", title)

	if _load_original(data): return
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color("152033")
	plastic.metallic = 0.12
	plastic.roughness = 0.29
	plastic.clearcoat_enabled = true
	plastic.clearcoat = 0.42
	plastic.clearcoat_roughness = 0.28
	plastic.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := MeshInstance3D.new()
	body.name = "RoundedPlasticShell"
	body.mesh = _rounded_box(BOX_SIZE, CORNER_RADIUS)
	body.material_override = plastic
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(body)

	_face("FrontArtwork", Vector2(1.64, 2.32), Vector3(0, 0, BOX_SIZE.z * 0.5 + SURFACE_OFFSET), Vector3.ZERO, _texture(data, "front"))
	_face("BackArtwork", Vector2(1.64, 2.32), Vector3(0, 0, -BOX_SIZE.z * 0.5 - SURFACE_OFFSET), Vector3(0, PI, 0), _texture(data, "back"))
	_face("SpineArtwork", Vector2(0.25, 2.32), Vector3(-BOX_SIZE.x * 0.5 - SURFACE_OFFSET, 0, 0), Vector3(0, -PI * 0.5, 0), _texture(data, "spine"))
	_face("TopArtwork", Vector2(1.64, 0.245), Vector3(0, BOX_SIZE.y * 0.5 + SURFACE_OFFSET, 0), Vector3(-PI * 0.5, 0, 0), _texture(data, "edge"))
	_face("BottomArtwork", Vector2(1.64, 0.245), Vector3(0, -BOX_SIZE.y * 0.5 - SURFACE_OFFSET, 0), Vector3(PI * 0.5, 0, PI), _texture(data, "edge"))

	# A real gap line and molded ribs make the thickness legible in profile.
	var groove := StandardMaterial3D.new()
	groove.albedo_color = Color("050c18")
	groove.roughness = 0.73
	_block("OpeningSeam", Vector3(0.002, 2.34, 0.009), Vector3(BOX_SIZE.x * 0.5 + 0.0005, 0, 0), groove)
	_block("TopSeam", Vector3(1.64, 0.002, 0.006), Vector3(0, BOX_SIZE.y * 0.5 + 0.002, 0), groove)
	_block("BottomSeam", Vector3(1.64, 0.002, 0.006), Vector3(0, -BOX_SIZE.y * 0.5 - 0.002, 0), groove)
	for y_position in [-0.99, -0.965, 0.965, 0.99]:
		_block("MoldedRib", Vector3(0.003, 0.006, 0.21), Vector3(BOX_SIZE.x * 0.5 + 0.001, y_position, 0), plastic)

func _load_original(data: Dictionary) -> bool:
	var path := str(data.get("model_path", "res://assets/library_models/master_system_box_cartridge.glb"))
	if path.is_empty() or not FileAccess.file_exists(path): return false
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(ProjectSettings.globalize_path(path), state) != OK: return false
	var scene := document.generate_scene(state)
	if not scene: return false
	var source_box := scene.find_child("SMS_BOX_ROOT", true, false) as Node3D
	var source_cartridge := scene.find_child("SMS_CARTRIDGE_ROOT", true, false) as Node3D
	if not source_box or not source_cartridge:
		scene.free()
		return false
	original_model = Node3D.new()
	original_model.name = "OriginalRoomAssembly"
	add_child(original_model)
	source_box.owner = null
	source_box.get_parent().remove_child(source_box)
	original_model.add_child(source_box)
	source_box.transform = Transform3D.IDENTITY
	source_cartridge.owner = null
	source_cartridge.get_parent().remove_child(source_cartridge)
	source_box.add_child(source_cartridge)
	cartridge = source_cartridge
	cartridge.transform = inside_pose
	lid = source_box.find_child("BOX_LID_HINGE", true, false) as Node3D
	_align_original_hinge_to_spine(source_box)
	scene.free()
	_restore_original_art(data)
	original_model.rotation.x = PI*0.5
	var bounds := _mesh_bounds()
	var factor := 2.44 / maxf(bounds.size.y, 0.001)
	original_model.scale = Vector3.ONE * factor
	bounds = _mesh_bounds()
	original_model.position -= bounds.get_center()
	set_meta("original_room_geometry", true)
	return true

func _align_original_hinge_to_spine(source_box: Node3D) -> void:
	# REV2's authored pivot is on the bottom of the case, 23 mm below the
	# actual joint. Rotating it there detaches the lid despite correct parenting.
	# Use the existing spine wall's outer top edge, already inside Lid_rim.
	# Source units are metres: Case_wall spans x=-.068..-.064, y=.001..-.023;
	# its bevel ends at x=-.0673 on the flat y=.023 top. That edge is the axis.
	# This shared axis keeps the original molded parts touching at every angle;
	# no invented hinge, remodeled shell, or floating artwork is introduced.
	if not is_instance_valid(lid): return
	var wall := source_box.find_child("Case_wall", true, false) as MeshInstance3D
	var rim := lid.find_child("Lid_rim", true, false) as MeshInstance3D
	if not wall or not rim or wall.get_parent() != source_box or rim.get_parent() != lid: return
	var points := PackedVector3Array()
	var top_y := -INF
	for surface in wall.mesh.get_surface_count():
		for vertex in wall.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var point: Vector3 = wall.transform * vertex
			points.append(point)
			top_y = maxf(top_y, point.y)
	var outer_x := INF
	for point in points:
		if absf(point.y - top_y) < 0.0000001:
			outer_x = minf(outer_x, point.x)
	if not is_finite(outer_x): return
	var joint := Vector3(outer_x, top_y, (wall.transform * wall.get_aabb()).get_center().z)
	if not rim.get_aabb().grow(0.0000001).has_point((lid.transform * rim.transform).affine_inverse() * joint): return
	var original_hinge := lid.transform
	var corrected_hinge := Transform3D(lid.basis, joint)
	var compensation := corrected_hinge.affine_inverse() * original_hinge
	# Preserve every closed-pose vertex, including the front sleeve and clips.
	for child in lid.get_children():
		if child is Node3D: child.transform = compensation * child.transform
	lid.transform = corrected_hinge
	set_meta("source_hinge_origin", original_hinge.origin)
	set_meta("corrected_hinge_origin", joint)
	set_meta("hinge_pivot_repaired", true)

func _restore_original_art(data: Dictionary) -> void:
	var uv_path := str(data.get("uv_path", "res://assets/library_models/original_uv.json"))
	var uv_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(uv_path)) if FileAccess.file_exists(uv_path) else {}
	if not uv_data is Dictionary: uv_data = {}
	for mesh in original_model.find_children("*", "MeshInstance3D", true, false):
		if uv_data.has(str(mesh.name)) and mesh.mesh.get_surface_count() == 1:
			var arrays: Array = mesh.mesh.surface_get_arrays(0)
			var coords: Array = uv_data[str(mesh.name)]["uv"]
			var positions: Array = uv_data[str(mesh.name)]["positions"]
			if coords.size() == arrays[Mesh.ARRAY_VERTEX].size():
				var uvs := PackedVector2Array()
				for vertex in arrays[Mesh.ARRAY_VERTEX]:
					var nearest := 0
					var distance := INF
					for index in positions.size():
						var point := Vector3(positions[index][0],positions[index][1],positions[index][2])
						if vertex.distance_squared_to(point) < distance:
							nearest = index
							distance = vertex.distance_squared_to(point)
					uvs.append(Vector2(coords[nearest][0], coords[nearest][1]))
				arrays[Mesh.ARRAY_TEX_UV] = uvs
				var restored := ArrayMesh.new()
				restored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				restored.surface_set_material(0, mesh.mesh.surface_get_material(0))
				mesh.mesh = restored
		var face: String = {"Box_FRONT":"front", "Box_BACK":"back", "Box_LEFT_SPINE":"spine"}.get(str(mesh.name), "")
		# Independent scraped/local faces fill their own UV rectangle, not the full
		# original wraparound atlas. Missing faces stay neutral, never inherit a game.
		var supplied_label := false
		if mesh.mesh.get_surface_count() == 1:
			var material_name: String = mesh.mesh.surface_get_material(0).resource_name
			var label_field: String = {"SLOT_CART_LABEL":"cartridge_label", "SLOT_CART_TOP":"cartridge_top"}.get(material_name, "")
			supplied_label = not label_field.is_empty() and not str(data.get(label_field, "")).is_empty()
		if (not face.is_empty() or supplied_label) and mesh.mesh.get_surface_count() == 1:
			var arrays: Array = mesh.mesh.surface_get_arrays(0)
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var low := Vector2(INF,INF)
			var high := Vector2(-INF,-INF)
			for uv in uvs:
				low = low.min(uv)
				high = high.max(uv)
			var span := high-low
			for index in uvs.size():
				uvs[index] = (uvs[index]-low)/Vector2(maxf(span.x,0.001),maxf(span.y,0.001))
				if face == "back": uvs[index] = Vector2.ONE-uvs[index]
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			var normalized := ArrayMesh.new()
			normalized.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			normalized.surface_set_material(0,mesh.mesh.surface_get_material(0))
			mesh.mesh = normalized
		for surface in mesh.mesh.get_surface_count():
			var material = mesh.mesh.surface_get_material(surface)
			if material is StandardMaterial3D and material.resource_name.begins_with("SLOT_"):
				var copy: StandardMaterial3D = material.duplicate()
				var path := str(data.get("art_root", "")).path_join(material.resource_name)
				var texture := load_artwork(path + ".png") if not str(data.get("art_root", "")).is_empty() else null
				if texture == null and not str(data.get("art_root", "")).is_empty(): texture = load_artwork(path + ".jpg")
				if not face.is_empty(): texture = _texture(data,face)
				var cartridge_field: String = {"SLOT_CART_LABEL":"cartridge_label", "SLOT_CART_TOP":"cartridge_top"}.get(material.resource_name, "")
				if not cartridge_field.is_empty() and not str(data.get(cartridge_field, "")).is_empty():
					texture = load_artwork(str(data[cartridge_field]))
				copy.albedo_texture = texture
				copy.albedo_color = Color.WHITE if texture else Color("27313d")
				mesh.set_surface_override_material(surface, copy)

func _mesh_bounds() -> AABB:
	var result := AABB()
	var first := true
	for mesh in find_children("*", "MeshInstance3D", true, false):
		var transform := Transform3D.IDENTITY
		var node: Node3D = mesh
		while node != self:
			transform = node.transform * transform
			node = node.get_parent()
		var bounds: AABB = transform * mesh.get_aabb()
		result = bounds if first else result.merge(bounds)
		first = false
	return result

func can_open() -> bool:
	return is_instance_valid(lid)

func set_lid_angle(angle_degrees: float) -> void:
	# Immediate, bounded pose setter shared by inspection, QA, and animation.
	# Opening/closing state and cartridge ownership remain with their callers.
	if can_open() and is_finite(angle_degrees):
		lid.rotation.z = deg_to_rad(clampf(angle_degrees, 0.0, LID_OPEN_DEGREES))

func toggle_lid() -> void:
	if not can_open(): return
	opened = not opened
	if not opened:
		cartridge_out = false
		cartridge.transform = inside_pose
	set_lid_angle(LID_OPEN_DEGREES if opened else 0.0)

func toggle_cartridge() -> void:
	if not can_open(): return
	if not opened: toggle_lid()
	cartridge_out = not cartridge_out
	cartridge.transform = inside_pose
	if cartridge_out: cartridge.position.y += 0.13

func reset_parts() -> void:
	if opened: toggle_lid()

func get_local_bounds() -> AABB:
	if is_instance_valid(original_model): return _mesh_bounds()
	# Includes the small relief ribs and skin; independent of selected item.
	var extent := BOX_SIZE * 0.5 + Vector3.ONE * 0.004
	return AABB(-extent, extent * 2.0)

static func load_artwork(supplied: Variant) -> Texture2D:
	if supplied is Texture2D:
		return supplied as Texture2D
	if not supplied is String or str(supplied).is_empty():
		return null
	var path := str(supplied)
	# Runtime decoding also works without Godot import caches for local/private art.
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(ProjectSettings.globalize_path(path)) == OK:
			image.generate_mipmaps()
			return ImageTexture.create_from_image(image)
	return null

func _texture(data: Dictionary, face: String) -> Texture2D:
	# Never substitute invented artwork, another game, or the front for a missing back.
	return load_artwork(data.get("cover_" + face, null))

func _face(node_name: String, dimensions: Vector2, location: Vector3, angles: Vector3, artwork: Texture2D) -> void:
	var panel := MeshInstance3D.new()
	panel.name = node_name
	var quad := QuadMesh.new()
	quad.size = dimensions
	panel.mesh = quad
	panel.position = location
	panel.rotation = angles
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_texture = artwork
	material.albedo_color = Color.WHITE if artwork != null else Color("14293b")
	# Matte printed sleeve: directional lighting still shapes it, gentle emission
	# keeps the supplied sleeve readable under the existing cosmic lighting.
	material.roughness = 0.76
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	material.metallic_specular = 0.22
	material.emission_enabled = artwork != null
	material.emission = Color.WHITE
	material.emission_texture = artwork
	material.emission_energy_multiplier = 0.16
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.cull_mode = BaseMaterial3D.CULL_BACK
	panel.material_override = material
	add_child(panel)

func _block(node_name: String, dimensions: Vector3, location: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	part.mesh = mesh
	part.position = location
	part.material_override = material
	add_child(part)

func _rounded_box(dimensions: Vector3, radius: float) -> ArrayMesh:
	var half := dimensions * 0.5
	var inner := half - Vector3.ONE * radius
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Six separately tessellated patches share analytic rounded-corner normals.
	# Only the narrow bevel is subdivided; the large planar faces stay inexpensive.
	for axis in range(3):
		var u_axis := (axis + 1) % 3
		var v_axis := (axis + 2) % 3
		var u_values := _bevel_samples(half[u_axis], radius)
		var v_values := _bevel_samples(half[v_axis], radius)
		for sign_value in [-1.0, 1.0]:
			for u_index in range(u_values.size() - 1):
				for v_index in range(v_values.size() - 1):
					var corners: Array[Vector3] = []
					for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
						var point := Vector3.ZERO
						point[axis] = half[axis] * sign_value
						point[u_axis] = u_values[u_index + offset.x]
						point[v_axis] = v_values[v_index + offset.y]
						corners.append(point)
					var indices := [0, 2, 1, 0, 3, 2] if sign_value > 0.0 else [0, 1, 2, 0, 2, 3]
					for corner_index in indices:
						var point: Vector3 = corners[corner_index]
						var clamped := point.clamp(-inner, inner)
						var normal := (point - clamped).normalized()
						surface.set_normal(normal)
						surface.add_vertex(clamped + normal * radius)
	surface.index()
	return surface.commit()

func _bevel_samples(half_size: float, radius: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for index in range(5):
		values.append(-half_size + radius * float(index) / 4.0)
	for index in range(5):
		values.append(half_size - radius + radius * float(index) / 4.0)
	return values
