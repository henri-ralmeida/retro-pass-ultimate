extends Node3D
## Original, fictional display box. Presentation only: no files, ROMs or launches.
## The sleeve uses separate front/back/spine textures. Front is +Z; spine is -X.
## configure() is safe before or after add_child(); each call replaces the model.

const BOX_SIZE := Vector3(1.74, 2.44, 0.30)
const CORNER_RADIUS := 0.025
const SURFACE_OFFSET := 0.001
const ASSET_ROOT := "res://assets/library_templates/"
const KNOWN_IDS := ["alex_kidd", "wonder_boy"]

var item: Dictionary = {}
var item_id := "alex_kidd"
var title := "Alex Kidd"
var _built := false

func _ready() -> void:
	if not _built:
		configure(item)

func configure(data: Dictionary) -> void:
	item = data.duplicate(true)
	item_id = str(data.get("id", "alex_kidd")).to_lower().replace(" ", "_")
	if item_id not in KNOWN_IDS:
		item_id = "alex_kidd"
	title = str(data.get("title", "Alex Kidd" if item_id == "alex_kidd" else "Wonder Boy"))
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_built = true
	name = "FictionalBox_" + item_id
	set_meta("fictional", true)
	set_meta("official_artwork", false)
	set_meta("rom_present", false)
	set_meta("display_title", title)

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

func get_local_bounds() -> AABB:
	# Includes the small relief ribs and skin; independent of selected item.
	var extent := BOX_SIZE * 0.5 + Vector3.ONE * 0.004
	return AABB(-extent, extent * 2.0)

func _texture(data: Dictionary, face: String) -> Texture2D:
	var supplied: Variant = data.get("cover_" + face, null)
	if supplied is Texture2D:
		return supplied as Texture2D
	if supplied is String and str(supplied).begins_with("res://") and ResourceLoader.exists(str(supplied)):
		var resource: Resource = load(str(supplied))
		if resource is Texture2D:
			return resource as Texture2D
	var path := ASSET_ROOT + item_id + "_" + face + ".svg"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	# Useful on the first editor import; retains deterministic art without a cache.
	var source := FileAccess.get_file_as_string(path)
	var image := Image.new()
	if not source.is_empty() and image.load_svg_from_string(source) == OK:
		image.generate_mipmaps()
		return ImageTexture.create_from_image(image)
	return null

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
	# keeps the warning and spine readable under the existing cosmic lighting.
	material.roughness = 0.76
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	material.metallic_specular = 0.22
	material.emission_enabled = true
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
