extends RefCounted
## Read-only, double-sided triangle picking for the actual HOME geometry.
## AABBs are ONLY a broad phase. The closest triangle wins, including non-pad
## occluders. Shared meshes, materials, UVs and transforms are never modified.
## Faces are cached by mesh identity until clear(); the host clears on rebuild.
var _faces: Dictionary = {}

func clear() -> void:
 _faces.clear()

func nearest_hit(roots: Array[Node3D], origin: Vector3, direction: Vector3, max_distance: float = INF, visible_layers: int = 0xFFFFF) -> Dictionary:
 if not origin.is_finite() or not direction.is_finite() or direction.length_squared() <= 0.000000000001: return {}
 if max_distance <= 0.0 or is_nan(max_distance): return {}
 var ray := direction.normalized()
 var nearest := max_distance
 var result: Dictionary = {}
 var seen: Dictionary = {}
 for root_node in roots:
  if not is_instance_valid(root_node): continue
  var meshes: Array[Node] = root_node.find_children("*","MeshInstance3D",true,false)
  if root_node is MeshInstance3D: meshes.append(root_node)
  for candidate in meshes:
   var mesh := candidate as MeshInstance3D
   if mesh == null or mesh.mesh == null or not mesh.is_visible_in_tree(): continue
   if (mesh.layers & visible_layers) == 0: continue
   var node_id := mesh.get_instance_id()
   if seen.has(node_id): continue
   seen[node_id] = true
   var frame := mesh.global_transform
   if not frame.is_finite() or absf(frame.basis.determinant()) <= 0.000000000001: continue
   var inverse := frame.affine_inverse()
   var local_origin := inverse * origin
   # Do not normalize this transformed vector: its t stays in world-ray meters
   # under nonuniform scale, negative scale, and rotation.
   var local_direction := inverse.basis * ray
   if not _ray_overlaps_bounds(local_origin,local_direction,mesh.get_aabb(),nearest): continue
   var mesh_id := mesh.mesh.get_instance_id()
   if not _faces.has(mesh_id):
    _faces[mesh_id] = {"resource":mesh.mesh,"faces":mesh.mesh.get_faces()}
   var faces: PackedVector3Array = _faces[mesh_id].faces
   for offset in range(0,faces.size()-2,3):
    var distance := _triangle_distance(local_origin,local_direction,faces[offset],faces[offset+1],faces[offset+2])
    if distance >= 0.0 and distance < nearest:
     nearest = distance
     result = {"mesh":mesh,"distance":distance,"position":origin+ray*distance}
 return result

static func _ray_overlaps_bounds(origin: Vector3, direction: Vector3, bounds: AABB, maximum: float) -> bool:
 var near := 0.0
 var far := maximum
 for axis in 3:
  if absf(direction[axis]) <= 0.000000000001:
   if origin[axis] < bounds.position[axis] or origin[axis] > bounds.end[axis]: return false
  else:
   var first := (bounds.position[axis]-origin[axis])/direction[axis]
   var last := (bounds.end[axis]-origin[axis])/direction[axis]
   near = maxf(near,minf(first,last))
   far = minf(far,maxf(first,last))
   if near > far: return false
 return far >= 0.0

static func _triangle_distance(origin: Vector3, direction: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
 var edge_1 := b-a
 var edge_2 := c-a
 var cross := direction.cross(edge_2)
 var determinant := edge_1.dot(cross)
 if absf(determinant) <= 0.000000000001: return -1.0
 var inverse := 1.0/determinant
 var from_a := origin-a
 var u := from_a.dot(cross)*inverse
 if u < 0.0 or u > 1.0: return -1.0
 var cross_2 := from_a.cross(edge_1)
 var v := direction.dot(cross_2)*inverse
 if v < 0.0 or u+v > 1.0: return -1.0
 var distance := edge_2.dot(cross_2)*inverse
 return distance if distance >= 0.0 else -1.0
