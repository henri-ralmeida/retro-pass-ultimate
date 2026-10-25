extends SceneTree
const Loader = preload("res://cosmic/sms_mechanical_loader.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures.append(message)
func fixture() -> Dictionary:
 var result := {"schema_version":1,"front_face":"gltf_ccw","units":"meters","coordinate_space":"source_node_local","floor_name":"Cartridge_well","floor_transform":[0.0,-0.02,0.0],"meshes":[]}
 for name in Loader.EXISTING + Loader.RETURNS:
  result.meshes.append({"name":name,"new":name in Loader.RETURNS,"surfaces":[{"POSITION":[[0,0,0],[1,0,0],[0,0,-1]],"NORMAL":[[0,1,0],[0,1,0],[0,1,0]],"TEXCOORD_0":[[0,0],[1,0],[0,1]]}]})
 return result
func _initialize() -> void:
 var loader := Loader.new()
 check(loader.validate_patch(fixture()),"Neutral valid geometry accepted")
 for malformed in [null,[],{},"text",1]: check(not loader.validate_patch(malformed),"Non-schema data rejected")
 for field in ["schema_version","front_face","units","coordinate_space"]:
  var invalid_header := fixture()
  invalid_header.erase(field)
  check(not loader.validate_patch(invalid_header),"Missing schema contract rejected: " + field)
 var wrong_winding := fixture()
 wrong_winding.front_face = "godot_cw"
 check(not loader.validate_patch(wrong_winding),"Already-converted winding rejected")
 var value := fixture()
 value.floor_transform = [0,0]
 check(not loader.validate_patch(value),"Short floor rejected")
 value = fixture(); value.floor_transform = [0,NAN,0]
 check(not loader.validate_patch(value),"Nonfinite floor rejected")
 value = fixture(); value.meshes[0].name = "OtherMesh"
 check(not loader.validate_patch(value),"Non-allowlisted mesh rejected")
 value = fixture(); value.meshes[1].name = value.meshes[0].name
 check(not loader.validate_patch(value),"Duplicate mesh rejected")
 value = fixture(); value.meshes[0].new = true
 check(not loader.validate_patch(value),"Wrong operation rejected")
 value = fixture(); value.meshes[0].surfaces[0].NORMAL.pop_back()
 check(not loader.validate_patch(value),"Attribute mismatch rejected")
 value = fixture(); value.meshes[0].surfaces[0].POSITION[0] = [INF,0,0]
 check(not loader.validate_patch(value),"Nonfinite vertex rejected")
 value = fixture(); value.meshes[0].surfaces[0].POSITION.append([0,0,0])
 check(not loader.validate_patch(value),"Nontriangle count rejected")
 value = fixture(); value.meshes[0].surfaces[0].NORMAL[0] = [0,0,0]
 check(not loader.validate_patch(value),"Zero normal rejected")
 check(loader.create_candidate("res://missing.tscn","res://missing.json","","").is_empty(),"Missing/hashless inputs fail closed")
 value = fixture(); value.meshes[0].surfaces[0].NORMAL[0] = [0,0.8,0]
 check(not loader.validate_patch(value),"Non-unit normals rejected without normalization")
 # Neutral synthetic source; verify meshes/materials of sibling instance unchanged.
 var source := Node3D.new()
 var material := StandardMaterial3D.new()
 var shared := BoxMesh.new()
 shared.material = material
 for name in Loader.EXISTING:
  var part := MeshInstance3D.new(); part.name = name; part.mesh = shared; source.add_child(part)
 for name in ["Cartridge_well","Cartridge_dust_door","Dust_door_hinge","Dust_door_hinge_001"]:
  var node := Node3D.new(); node.name = name; source.add_child(node)
 var sibling := source.duplicate() as Node3D
 var before := shared.get_rid()
 var result: Dictionary = loader._apply_candidate(source,fixture())
 check(not result.is_empty(),"Neutral candidate patched")
 check(shared.get_rid() == before and sibling.get_child(0).mesh == shared,"Sibling source mesh unchanged")
 check(shared.material == material,"Source material unchanged")
 check(source.get_child(0).mesh != shared,"Candidate owns fresh mesh")
 var arrays: Array = source.get_child(0).mesh.surface_get_arrays(0)
 check(arrays[Mesh.ARRAY_INDEX] == PackedInt32Array([0,2,1]),"glTF winding converted to Godot front faces")
 check(arrays[Mesh.ARRAY_TANGENT].size() == 12,"Tangents generated for preserved UV and normals")
 # ArrayMesh normal storage quantizes exact UP (observed z=-1/65535).
 # Compare against the engine's own first encode/decode, not a relaxed epsilon.
 var baseline_arrays: Array = []
 baseline_arrays.resize(Mesh.ARRAY_MAX)
 baseline_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
 baseline_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
 baseline_arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN])
 baseline_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1])
 var baseline := ArrayMesh.new()
 baseline.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,baseline_arrays)
 check(arrays[Mesh.ARRAY_NORMAL] == baseline.surface_get_arrays(0)[Mesh.ARRAY_NORMAL],"Normal storage matches raw ArrayMesh baseline; no regenerated normals")
 for normal in arrays[Mesh.ARRAY_NORMAL]: check(is_equal_approx(normal.length_squared(),1.0),"Stored normals remain unit length")
 check(result.movers.size() == 3,"Door and both hinges captured")
 check(result.movers[0].rest_local_to_console == Transform3D.IDENTITY,"Console-local rest captured without tree")
 check(source.find_child("Slot_internal_return_X0",true,false) != null,"Interior created only on candidate")
 check(sibling.find_child("Slot_internal_return_X0",true,false) == null,"Sibling has no interior mutation")
 source.free(); sibling.free()
 # Optional complete production loader contract, no ROM access.
 var patch := OS.get_environment("RETROPASS_SMS_MECHANICAL_PATCH")
 if not patch.is_empty():
  var scene := "res://assets/cosmic_console/MasterSystem_Console_Render.tscn"
  var dependencies := {}
  for path in ["res://assets/cosmic_console/MasterSystem_Console.glb","res://assets/cosmic_console/console_finish.gd"]: dependencies[path] = FileAccess.get_sha256(path)
  result = loader.create_candidate(scene,patch,FileAccess.get_sha256(scene),OS.get_environment("RETROPASS_SMS_MECHANICAL_PATCH_SHA256"),dependencies)
  check(not result.is_empty(),"Explicit private geometry hash contract loads: " + loader.last_error)
  if not result.is_empty(): result.root.free()
 for error in failures: push_error(error)
 print("SMS MECHANICAL LOADER: ",checks," checks, ",failures.size()," failures")
 quit(0 if failures.is_empty() else 1)
