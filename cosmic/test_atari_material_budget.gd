extends SceneTree
const Media = preload("res://cosmic/atari_private_media.gd")
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _expect(ok: bool, message: String) -> void:
 if not ok: failures.append(message)
func _texture(width: int, height: int) -> ImageTexture:
 var image := Image.create(width,height,false,Image.FORMAT_RGBA8)
 image.fill(Color.WHITE)
 return ImageTexture.create_from_image(image)
func _mesh(material: StandardMaterial3D) -> MeshInstance3D:
 var arrays := []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
 var mesh := ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 mesh.surface_set_material(0,material)
 var node := MeshInstance3D.new()
 node.mesh = mesh
 return node
func _run() -> void:
 var loader := Media.new()
 var group := Node3D.new()
 var small := _texture(64,32)
 var large := _texture(2050,4)
 var small_material := StandardMaterial3D.new()
 small_material.albedo_texture = small
 var large_material := StandardMaterial3D.new()
 large_material.albedo_texture = large
 var small_node := _mesh(small_material)
 var large_node := _mesh(large_material)
 var shared_node := _mesh(large_material)
 group.add_child(small_node)
 group.add_child(large_node)
 group.add_child(shared_node)
 loader._bound_materials(group)
 var retained := small_node.mesh.surface_get_material(0) as StandardMaterial3D
 var bounded := large_node.mesh.surface_get_material(0) as StandardMaterial3D
 var shared := shared_node.mesh.surface_get_material(0) as StandardMaterial3D
 _expect(retained.albedo_texture == small,"In-budget imported texture retained by identity")
 _expect(loader.texture_cache.size() == 1,"Only oversized texture enters replacement cache")
 _expect(bounded.albedo_texture != large,"Oversized texture replaced")
 _expect(bounded.albedo_texture.get_width() == Media.MAX_TEXTURE_EDGE,"Oversized texture bounded to 2048")
 _expect(shared.albedo_texture == bounded.albedo_texture,"Shared oversized texture reuses cached replacement")
 _expect(large.get_width() == 2050,"Source texture remains unchanged")
 _expect(large_material.albedo_texture == large,"Source material remains unchanged")
 for node in [small_node,large_node,shared_node]:
  _expect(node.get_surface_override_material(0) == null,"Mesh owns replacement without retaining override")
 _expect(retained.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,"Sampling policy preserved")
 loader._bound_materials(group)
 _expect((large_node.mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture == bounded.albedo_texture,"Repeated bounding does not copy budgeted texture")
 _expect(loader.texture_cache.size() == 1,"Repeated bounding does not grow cache")
 group.free()
 for failure in failures: push_error(failure)
 print("ATARI MATERIAL BUDGET FAILURES: ", failures.size())
 quit(0 if failures.is_empty() else 1)
