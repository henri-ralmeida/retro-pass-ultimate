extends SceneTree
## Asset-independent synthetic picker checks; does not load main or GLB assets.
const Picker = preload("res://cosmic/controller_home_picker.gd")
var assertions := 0
var failures: Array[String] = []
func _initialize() -> void:
 run.call_deferred()
func check(value: bool, message: String) -> void:
 assertions += 1
 if not value:
  failures.append(message)
  push_error(message)
func triangle() -> MeshInstance3D:
 var mesh := MeshInstance3D.new()
 var arrays: Array = []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1,-1,0),Vector3(1,-1,0),Vector3(0,1,0)])
 var geometry := ArrayMesh.new()
 geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 mesh.mesh = geometry
 return mesh

func test_triangle_occlusion() -> void:
 var picker := Picker.new()
 var world := Node3D.new()
 root.add_child(world)
 var pad := triangle()
 world.add_child(pad)
 var source_mesh := pad.mesh
 var source_faces := pad.mesh.get_faces()
 var hit: Dictionary = picker.nearest_hit([world],Vector3(0,0,2),Vector3.FORWARD)
 check(hit.get("mesh") == pad and is_equal_approx(hit.get("distance",0.0),2.0),"Triangle hit returns actual nearest surface")
 check(picker.nearest_hit([world],Vector3(0.9,0.9,2),Vector3.FORWARD).is_empty(),"Empty part of mesh AABB cannot select a controller")
 var occluder := triangle()
 occluder.position.z = 1.0
 world.add_child(occluder)
 check(picker.nearest_hit([world],Vector3(0,0,2),Vector3.FORWARD).get("mesh") == occluder,"Closer console/cable geometry occludes controller")
 occluder.hide()
 check(picker.nearest_hit([world],Vector3(0,0,2),Vector3.FORWARD).get("mesh") == pad,"Hidden surfaces do not occlude")
 occluder.show()
 occluder.layers = 0
 check(picker.nearest_hit([world],Vector3(0,0,2),Vector3.FORWARD).get("mesh") == pad,"Non-rendered perspective bounds proxy does not occlude")
 pad.transform = Transform3D(Basis(Vector3.UP,0.6).scaled(Vector3(-2,0.7,1.8)),Vector3(0.2,0.1,-0.4))
 var center := pad.to_global(Vector3.ZERO)
 var normal := (pad.global_basis.inverse().transposed()*Vector3.BACK).normalized()
 hit = picker.nearest_hit([world],center+normal*3.0,-normal)
 check(hit.get("mesh") == pad and is_equal_approx(hit.get("distance",0.0),3.0),"Ray distance survives mirrored/nonuniform transformed mesh")
 check(pad.mesh == source_mesh and pad.mesh.get_faces() == source_faces,"Picker never edits shared geometry")
 check(picker.nearest_hit([world],Vector3.ZERO,Vector3.ZERO).is_empty(),"Degenerate ray fails closed")
 world.free()

func run() -> void:
 test_triangle_occlusion()
 print(JSON.stringify({"suite":"controller_home_picker","assertions":assertions,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
