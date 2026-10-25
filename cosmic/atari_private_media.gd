extends RefCounted
## Explicit private-only GLB adapter. No directory discovery, downloads, or imported scripts.
## Caller must supply a local manifest path AND opt in. Empty/invalid input stays absent.
const SYSTEM_ID := "atari2600"
const MAX_MANIFEST_BYTES := 65536
const MAX_GLB_BYTES := 16777216
const MAX_JSON_BYTES := 2097152
const MAX_NODES := 512
const MAX_MESHES := 256
const MAX_IMAGES := 16
const MAX_VERTICES := 250000
const MAX_TEXTURE_EDGE := 2048
const MODEL_KEYS := ["console", "controller", "box", "cartridge", "manual"]
const CORE_KEYS := ["console", "controller", "box", "cartridge"]
var enabled := false
var manifest: Dictionary = {}
var directory := ""
var errors: Array[String] = []
var texture_cache: Dictionary = {}
var imported_model_count := 0

func configure(manifest_path: String = "", opted_in: bool = false) -> bool:
 enabled = false
 manifest.clear()
 errors.clear()
 texture_cache.clear()
 imported_model_count = 0
 directory = ""
 if not opted_in:
  errors.append("Mídia Atari privada não habilitada.")
  return false
 if manifest_path.is_empty() or manifest_path.get_extension().to_lower() != "json":
  errors.append("Manifesto local Atari não configurado.")
  return false
 var file := FileAccess.open(manifest_path, FileAccess.READ)
 if file == null or file.get_length() > MAX_MANIFEST_BYTES:
  errors.append("Manifesto local Atari ausente ou fora do limite.")
  return false
 var parsed = JSON.parse_string(file.get_as_text())
 if not parsed is Dictionary:
  errors.append("Manifesto Atari inválido.")
  return false
 if parsed.get("schema_version") != 1 or parsed.get("system_id") != SYSTEM_ID:
  errors.append("Manifesto não corresponde ao contrato Atari 2600.")
  return false
 if not parsed.get("models") is Dictionary or not parsed.get("game") is Dictionary:
  errors.append("Manifesto sem modelos ou identidade do jogo.")
  return false
 var game: Dictionary = parsed.game
 if str(game.get("id", "")).is_empty() or str(game.get("title", "")).is_empty():
  errors.append("Jogo sem identificação explícita.")
  return false
 directory = manifest_path.get_base_dir()
 manifest = parsed.duplicate(true)
 enabled = true
 return true

func model_path(key: String) -> String:
 if not enabled or key not in MODEL_KEYS:
  return ""
 var entry = manifest.models.get(key)
 if not entry is Dictionary:
  return ""
 return _local_file(str(entry.get("file", "")), ["glb"])

func manual_page_path(index: int) -> String:
 if not enabled:
  return ""
 var pages = manifest.get("manual_pages", [])
 if not pages is Array or index < 0 or index >= pages.size() or pages.size() > 64:
  return ""
 return _local_file(str(pages[index]), ["png", "jpg", "jpeg"])

func _local_file(filename: String, extensions: Array) -> String:
 # Manifest entries are basenames only, never URLs, parent traversal, or arbitrary paths.
 if filename.is_empty() or filename != filename.get_file():
  return ""
 if filename.contains(":") or filename.contains("\\") or filename.contains("/"):
  return ""
 if filename.get_extension().to_lower() not in extensions:
  return ""
 var path := directory.path_join(filename)
 return path if FileAccess.file_exists(path) else ""

func load_model(key: String) -> Node3D:
 var path := model_path(key)
 if path.is_empty():
  errors.append("Recurso Atari ausente: " + key + ".")
  return null
 if imported_model_count >= MODEL_KEYS.size():
  errors.append("Limite de cinco modelos residentes atingido.")
  return null
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null or file.get_length() < 28 or file.get_length() > MAX_GLB_BYTES:
  errors.append("Recurso Atari fora do limite: " + key + ".")
  return null
 var bytes := file.get_buffer(file.get_length())
 if not validate_glb(bytes):
  errors.append("GLB local inválido ou fora do orçamento: " + key + ".")
  return null
 var expected := str(manifest.models[key].get("sha256", ""))
 var hashing := HashingContext.new()
 hashing.start(HashingContext.HASH_SHA256)
 hashing.update(bytes)
 if expected.length() != 64 or hashing.finish().hex_encode() != expected:
  errors.append("Hash de recurso Atari não corresponde ao manifesto: " + key + ".")
  return null
 var document := GLTFDocument.new()
 var state := GLTFState.new()
 # append_from_buffer avoids a second file read; URIs were rejected before any import.
 var result := document.append_from_buffer(bytes, directory, state)
 if result != OK:
  errors.append("Importação Godot falhou: " + key + ".")
  return null
 var model := document.generate_scene(state) as Node3D
 if model == null:
  errors.append("Cena GLB ausente: " + key + ".")
  return null
 model.set_meta("atari_asset_key", key)
 model.set_meta("source_sha256", expected)
 model.set_meta("source_units", "meters")
 _bound_materials(model)
 imported_model_count += 1
 return model

static func validate_glb(bytes: PackedByteArray) -> bool:
 if bytes.size() < 28 or bytes.size() > MAX_GLB_BYTES:
  return false
 if bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2:
  return false
 if bytes.decode_u32(8) != bytes.size() or bytes.decode_u32(16) != 0x4e4f534a:
  return false
 var length := bytes.decode_u32(12)
 if length > MAX_JSON_BYTES or length < 2 or length % 4 != 0 or 28 + length > bytes.size():
  return false
 var data = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
 if not data is Dictionary:
  return false
 for pair in [["nodes", MAX_NODES], ["meshes", MAX_MESHES], ["images", MAX_IMAGES]]:
  var entries = data.get(pair[0], [])
  if not entries is Array or entries.size() > pair[1]:
   return false
 # glTF external URI resolution must never read another local file or make a request.
 for collection in [data.get("buffers", []), data.get("images", [])]:
  if not collection is Array:
   return false
  for item in collection:
   if not item is Dictionary or item.has("uri"):
    return false
 var required = data.get("extensionsRequired", [])
 if not required is Array or not required.is_empty():
  return false
 var bin_start := 20 + length
 if bytes.decode_u32(bin_start + 4) != 0x004e4942:
  return false
 var bin_length := bytes.decode_u32(bin_start)
 if bin_start + 8 + bin_length != bytes.size():
  return false
 var buffers = data.get("buffers", [])
 if buffers.size() != 1 or int(buffers[0].get("byteLength", -1)) < 0 or int(buffers[0].get("byteLength", -1)) > bin_length:
  return false
 var views = data.get("bufferViews", [])
 if not views is Array:
  return false
 for view in views:
  if not view is Dictionary:
   return false
  var start := int(view.get("byteOffset", 0))
  var size := int(view.get("byteLength", -1))
  if int(view.get("buffer", 0)) != 0 or start < 0 or size < 0 or start + size > bin_length:
   return false
 var accessors = data.get("accessors", [])
 if not accessors is Array:
  return false
 var vertices := 0
 for mesh in data.get("meshes", []):
  if not mesh is Dictionary or not mesh.get("primitives") is Array:
   return false
  for primitive in mesh.primitives:
   if not primitive is Dictionary or not primitive.get("attributes") is Dictionary:
    return false
   var position := int(primitive.attributes.get("POSITION", -1))
   if position < 0 or position >= accessors.size() or not accessors[position] is Dictionary:
    return false
   var count := int(accessors[position].get("count", -1))
   if count < 0:
    return false
   vertices += count
 return vertices <= MAX_VERTICES

func _bound_materials(node: Node) -> void:
 if node is AnimationPlayer:
  node.stop()
  node.active = false # Archived animation is not the interactive state machine.
 if node is MeshInstance3D and node.mesh != null:
  for surface in node.mesh.get_surface_count():
   var original = node.get_active_material(surface)
   if not original is StandardMaterial3D:
    continue
   var material := original.duplicate() as StandardMaterial3D
   material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
   for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL,
     BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC,
     BaseMaterial3D.TEXTURE_EMISSION, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]:
    var texture := material.get_texture(slot)
    if texture == null:
     continue
    # Keep already-budgeted imported textures intact: no GPU readback, CPU
    # image copy or second upload is needed merely to choose a sampler filter.
    if maxi(texture.get_width(), texture.get_height()) <= MAX_TEXTURE_EDGE:
     continue
    var cache_key := texture.get_instance_id()
    if not texture_cache.has(cache_key):
     var original_image := texture.get_image()
     if original_image == null or original_image.is_empty():
      continue
     var image := original_image.duplicate() as Image
     if image.is_compressed() and image.decompress() != OK:
      continue
     var edge := maxi(image.get_width(), image.get_height())
     if edge > MAX_TEXTURE_EDGE:
      var factor := float(MAX_TEXTURE_EDGE) / float(edge)
      image.resize(maxi(1, roundi(image.get_width() * factor)),
        maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
     image.generate_mipmaps()
     texture_cache[cache_key] = ImageTexture.create_from_image(image)
    material.set_texture(slot, texture_cache[cache_key])
   # Runtime GLTF imports own ArrayMeshes; replace their material rather than
   # retain both original and resized textures through a surface override.
   if node.mesh is ArrayMesh:
    node.mesh.surface_set_material(surface, material)
    node.set_surface_override_material(surface, null)
   else:
    node.set_surface_override_material(surface, material)
 for child in node.get_children():
  _bound_materials(child)
