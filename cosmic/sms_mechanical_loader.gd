extends RefCounted
## Explicit, hash-bound private geometry override. No assets embedded or fetched.
## The caller owns the returned root. Source resources/materials remain readonly.
const EXISTING := ["Upper_faceted_shell", "Lower_molded_shell"]
const RETURNS := ["Slot_internal_return_X0", "Slot_internal_return_X1", "Slot_internal_return_Z0", "Slot_internal_return_Z1"]
const MOVERS := ["Cartridge_dust_door", "Dust_door_hinge", "Dust_door_hinge.001"]
const MAX_PATCH_BYTES := 16 * 1024 * 1024
const MAX_VERTICES := 100000
var last_error := ""

func create_candidate(scene_path: String, patch_path: String, scene_sha256: String, patch_sha256: String, source_dependencies: Dictionary = {}) -> Dictionary:
 last_error = ""
 if not _hash_matches(scene_path,scene_sha256) or not _hash_matches(patch_path,patch_sha256):
  return _fail("Source or private geometry hash is missing or mismatched.")
 if scene_path == "res://assets/cosmic_console/MasterSystem_Console_Render.tscn":
  for path in ["res://assets/cosmic_console/MasterSystem_Console.glb", "res://assets/cosmic_console/console_finish.gd"]:
   if not source_dependencies.has(path): return _fail("Source dependency hash contract is incomplete.")
 for path in source_dependencies:
  if not path is String or not source_dependencies[path] is String or not _hash_matches(path,source_dependencies[path]): return _fail("Source dependency hash differs.")
 var file := FileAccess.open(patch_path,FileAccess.READ)
 if file == null or file.get_length() > MAX_PATCH_BYTES:
  return _fail("Private geometry is unreadable or exceeds the size limit.")
 var parsed: Variant = JSON.parse_string(file.get_as_text())
 file.close()
 if not validate_patch(parsed): return {}
 var packed: Variant = load(scene_path)
 if not packed is PackedScene: return _fail("Source is not a PackedScene.")
 var root: Variant = packed.instantiate()
 if not root is Node3D:
  if is_instance_valid(root): root.free()
  return _fail("Source root must be Node3D.")
 var result := _apply_candidate(root,parsed)
 if result.is_empty():
  root.free()
  return {}
 result.source_sha256 = scene_sha256.to_lower()
 result.patch_sha256 = patch_sha256.to_lower()
 return result

func validate_patch(value: Variant) -> bool:
 last_error = ""
 if not value is Dictionary: return _invalid("Private geometry must be an object.")
 if value.get("schema_version") != 1 or value.get("front_face") != "gltf_ccw" or value.get("units") != "meters" or value.get("coordinate_space") != "source_node_local":
  return _invalid("Unsupported geometry schema, winding, units or coordinate space.")
 if value.get("floor_name") != "Cartridge_well" or not _vector(value.get("floor_transform"),3):
  return _invalid("Invalid floor contract.")
 var meshes: Variant = value.get("meshes")
 if not meshes is Array or meshes.size() != 6: return _invalid("Exactly six permitted mesh overrides are required.")
 var seen := {}
 var total := 0
 for entry in meshes:
  if not entry is Dictionary: return _invalid("Invalid mesh record.")
  var name: Variant = entry.get("name")
  if not name is String or name not in EXISTING + RETURNS or seen.has(name): return _invalid("Unexpected or duplicate mesh name.")
  seen[name] = true
  if not entry.get("new") is bool or entry.new != (name in RETURNS): return _invalid("Invalid new-mesh marker.")
  var surfaces: Variant = entry.get("surfaces")
  if not surfaces is Array or surfaces.is_empty() or surfaces.size() > 16: return _invalid("Invalid surface count.")
  for surface in surfaces:
   if not surface is Dictionary: return _invalid("Invalid surface record.")
   var positions: Variant = surface.get("POSITION")
   var normals: Variant = surface.get("NORMAL")
   var uv: Variant = surface.get("TEXCOORD_0")
   if not positions is Array or positions.is_empty() or positions.size() % 3 != 0: return _invalid("Positions must be nonempty unindexed triangles.")
   total += positions.size()
   if total > MAX_VERTICES: return _invalid("Geometry exceeds vertex budget.")
   if not normals is Array or not uv is Array or normals.size() != positions.size() or uv.size() != positions.size(): return _invalid("Attribute counts differ.")
   for index in positions.size():
    if not _vector(positions[index],3) or not _vector(normals[index],3) or not _vector(uv[index],2): return _invalid("Invalid or nonfinite vertex attribute.")
    var normal := _vec3(normals[index])
    if absf(normal.length_squared()-1.0) > 0.0001: return _invalid("Invalid normal length.")
 return true

func _apply_candidate(root: Node3D, patch: Dictionary) -> Dictionary:
 var shell := root.find_child(EXISTING[0],true,false) as MeshInstance3D
 var floor_node := root.find_child("Cartridge_well",true,false) as Node3D
 if shell == null or shell.mesh == null or shell.mesh.get_surface_count() == 0 or floor_node == null:
  return _fail("Source shell or floor missing.")
 var interior: Material = shell.get_active_material(0)
 if interior == null: return _fail("Source interior material missing.")
 var movers: Array[Dictionary] = []
 for name in MOVERS:
  var node := _moving_node(root,name)
  if node == null: return _fail("Source moving part missing: " + name)
  movers.append({"node":node,"rest_local_to_console":_relative(root,node),"rest_transform":node.transform})
 # Validate every target before changing the new candidate.
 for entry in patch.meshes:
  var target := root.find_child(entry.name,true,false) as MeshInstance3D
  if entry.new:
   if target != null or entry.surfaces.size() != 1: return _fail("New interior target already exists or has multiple surfaces.")
  else:
   if target == null or target.mesh == null or target.mesh.get_surface_count() != entry.surfaces.size(): return _fail("Source target/surface layout changed.")
   for index in target.mesh.get_surface_count():
    if target.get_active_material(index) == null: return _fail("Source surface material missing.")
 for entry in patch.meshes:
  var target := root.find_child(entry.name,true,false) as MeshInstance3D
  var materials: Array[Material] = []
  if entry.new:
   target = MeshInstance3D.new()
   target.name = entry.name
   root.add_child(target)
   materials.append(interior)
  else:
   for index in target.mesh.get_surface_count(): materials.append(target.get_active_material(index))
  var mesh := ArrayMesh.new()
  for surface in entry.surfaces:
   var arrays: Array = []
   arrays.resize(Mesh.ARRAY_MAX)
   var vertices := PackedVector3Array()
   var normals := PackedVector3Array()
   var uv := PackedVector2Array()
   for point in surface.POSITION: vertices.append(_vec3(point))
   for normal in surface.NORMAL: normals.append(_vec3(normal))
   for point in surface.TEXCOORD_0: uv.append(Vector2(point[0],point[1]))
   arrays[Mesh.ARRAY_VERTEX] = vertices
   arrays[Mesh.ARRAY_NORMAL] = normals
   arrays[Mesh.ARRAY_TEX_UV] = uv
   # Private patch uses native glTF CCW. Godot imported fronts are clockwise.
   # Preserve position/normal/UV arrays; reverse only triangle index order.
   var indices := PackedInt32Array()
   for index in range(0,vertices.size(),3): indices.append_array(PackedInt32Array([index,index+2,index+1]))
   arrays[Mesh.ARRAY_INDEX] = indices
   mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  # Match the importer tangents without regenerating source vertex normals.
  var with_tangents := ArrayMesh.new()
  for index in mesh.get_surface_count():
   var surface_tool := SurfaceTool.new()
   surface_tool.create_from(mesh,index)
   surface_tool.generate_tangents()
   surface_tool.commit(with_tangents)
  target.mesh = with_tangents
  for index in materials.size(): target.set_surface_override_material(index,materials[index])
 floor_node.position = _vec3(patch.floor_transform)
 return {"root":root,"movers":movers}

func _moving_node(root: Node3D, name: String) -> Node3D:
 var found := root.find_child(name,true,false) as Node3D
 if found != null or name != "Dust_door_hinge.001": return found
 # Godot sanitizes imported periods; only accept one unambiguous second hinge.
 var alternatives: Array[Node3D] = []
 for node in root.find_children("Dust_door_hinge*","Node3D",true,false):
  if str(node.name) != "Dust_door_hinge": alternatives.append(node)
 return alternatives[0] if alternatives.size() == 1 else null

static func _relative(root: Node3D, node: Node3D) -> Transform3D:
 var result := node.transform
 var parent := node.get_parent()
 while parent != root:
  if parent is Node3D: result = parent.transform * result
  parent = parent.get_parent()
 return result

static func _hash_matches(path: String, expected: String) -> bool:
 if expected.length() != 64 or not FileAccess.file_exists(path): return false
 for c in expected.to_lower():
  if c not in "0123456789abcdef": return false
 return FileAccess.get_sha256(path).to_lower() == expected.to_lower()

static func _vector(value: Variant, size: int) -> bool:
 if not value is Array or value.size() != size: return false
 for component in value:
  if not (component is int or component is float) or not is_finite(float(component)): return false
 return true

static func _vec3(value: Array) -> Vector3:
 return Vector3(value[0],value[1],value[2])

func _invalid(reason: String) -> bool:
 last_error = reason
 return false

func _fail(reason: String) -> Dictionary:
 last_error = reason
 return {}
