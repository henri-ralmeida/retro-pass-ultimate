extends Node3D
## Original authored visual approximation of a molded Master System controller plug.
## Coordinates/meters: local +Z leaves the console; local z=0 is socket contact mouth.
## Input transform and returned anchor/tangent are in this node's parent's space.
## The helper never modifies the console. Pass the measured recess depth to its outer
## frame: the current source model has a 5.6 mm recess, not a flush connector.
## Reference silhouette: local evidence/reference_photos/master_system_inserted_sonic.jpg.
## Additional original hardware photographs (not distributed with this geometry):
## https://retroreiz.de/shop/sega/master-system/zubehoer-master-system/sega-2x-originale-master-system-controller-model-3020/
## https://www.ebay.com/itm/363906759513 (earlier, more rectangular revision differs).
## Shell dimensions and rib count are estimated from photos, not measured OEM CAD.
## No trademarks, fictitious lettering, textures, exposed pins or screw hardware.

const RADIAL_SEGMENTS := 48
const DEFAULT_CABLE_RADIUS := 0.0015
const DEFAULT_RECESS_DEPTH := 0.0056
const REFERENCE_NOTE := "Photo-informed molded plug approximation; dimensions and relief ribs estimated, not OEM metrology."

var cable_exit_local := Vector3.ZERO
var socket_face_local := Vector3.ZERO
var insertion_overlap := 0.0
var recess_depth := 0.0
var dimensions: Dictionary = {}
var configuration_error := ""
var _local_bounds := AABB()

func configure(socket_transform: Transform3D, socket_local_bounds: AABB, cable_radius: float = DEFAULT_CABLE_RADIUS, measured_recess_depth: float = DEFAULT_RECESS_DEPTH) -> bool:
 _clear()
 if not socket_transform.is_finite() or not socket_local_bounds.position.is_finite() or not socket_local_bounds.size.is_finite():
  return _fail("Socket transform and bounds must be finite")
 var axis_lengths := Vector3(socket_transform.basis.x.length(), socket_transform.basis.y.length(), socket_transform.basis.z.length())
 if axis_lengths.x < 0.000001 or axis_lengths.y < 0.000001 or axis_lengths.z < 0.000001 or absf(socket_transform.basis.determinant()) < 0.00000001:
  return _fail("Socket transform must have a non-degenerate basis")
 var width := socket_local_bounds.size.x * axis_lengths.x
 var height := socket_local_bounds.size.y * axis_lengths.y
 if width <= 0.0 or height <= 0.0 or socket_local_bounds.size.z < 0.0 or not is_finite(cable_radius) or cable_radius <= 0.0:
  return _fail("Positive socket face dimensions and cable radius are required")
 if not is_finite(measured_recess_depth) or measured_recess_depth < 0.0:
  return _fail("Measured socket recess depth must be non-negative")
 # Bounded to this family of miniature controller plugs, not arbitrary giant sockets.
 if width < 0.012 or width > 0.040 or height < 0.004 or height > 0.020 or cable_radius > height * 0.35 or measured_recess_depth > width:
  return _fail("Dimensions lie outside the supported controller plug envelope")
 var outward := socket_transform.basis.z.normalized()
 var right := socket_transform.basis.x.normalized()
 var up := outward.cross(right).normalized()
 right = up.cross(outward).normalized()
 var mouth := socket_local_bounds.get_center()
 mouth.z = socket_local_bounds.end.z
 transform = Transform3D(Basis(right, up, outward), socket_transform * mouth)
 socket_face_local = Vector3.ZERO
 recess_depth = measured_recess_depth
 insertion_overlap = minf(width * 0.03, 0.0007)
 var shell_width := width * 1.14
 var shell_height := height * 1.30
 var shell_length := width * 1.16
 var relief_length := width * 0.44
 var shoulder := recess_depth + 0.00025
 var end_shell := shoulder + shell_length
 var neck_radius := maxf(cable_radius * 1.8, height * 0.30)
 cable_exit_local = Vector3(0, 0, end_shell + relief_length)
 dimensions = {"socket_width": width, "socket_height": height, "shell_width": shell_width, "shell_height": shell_height, "shell_length": shell_length, "relief_length": relief_length, "recess_depth": recess_depth, "insertion_overlap": insertion_overlap, "cable_radius": cable_radius, "outward_length": cable_exit_local.z}
 set_meta("reference_note", REFERENCE_NOTE)
 var shell_material := StandardMaterial3D.new()
 shell_material.albedo_color = Color("121315")
 shell_material.roughness = 0.70
 shell_material.metallic_specular = 0.35
 var relief_material := StandardMaterial3D.new()
 relief_material.albedo_color = Color("0b0c0d")
 relief_material.roughness = 0.86
 relief_material.metallic_specular = 0.23
 # Narrow D-shaped insertion nose remains within the unmodified socket/frame opening.
 # z < 0 seats into the socket; no wide shell is allowed behind the outside frame.
 var nose_profiles: Array[Vector4] = [
  Vector4(-insertion_overlap, width*0.485, height*0.475, 0.48),
  Vector4(0.0, width*0.495, height*0.49, 0.46),
  Vector4(shoulder+0.00035, width*0.495, height*0.49, 0.46)]
 _add_part("InsertedConnectorNose", _loft(nose_profiles, 0.12), shell_material)
 # Rounded rectangular grip changing into a narrower, rounded rear. Successive
 # profiles form an actual tapered silhouette instead of a stretched cuboid.
 var shell_profiles: Array[Vector4] = [
  Vector4(shoulder, shell_width*0.475, shell_height*0.46, 0.52),
  Vector4(shoulder+shell_length*0.045, shell_width*0.50, shell_height*0.50, 0.48),
  Vector4(shoulder+shell_length*0.18, shell_width*0.50, shell_height*0.50, 0.46),
  Vector4(shoulder+shell_length*0.47, shell_width*0.49, shell_height*0.49, 0.48),
  Vector4(shoulder+shell_length*0.65, shell_width*0.45, shell_height*0.47, 0.56),
  Vector4(shoulder+shell_length*0.79, shell_width*0.36, shell_height*0.43, 0.66),
  Vector4(shoulder+shell_length*0.91, shell_width*0.24, shell_height*0.37, 0.82),
  Vector4(end_shell, neck_radius, neck_radius, 1.0)]
 _add_part("MoldedConnectorHousing", _loft(shell_profiles), shell_material)
 # Relief has shallow molded ribs, a continuous tapered core, and a tangent-aligned
 # cable exit. The cable should begin exactly at this anchor, not in bare contacts.
 var relief_profiles: Array[Vector4] = []
 const RELIEF_STEPS := 72
 for sample in RELIEF_STEPS+1:
  var t := float(sample)/RELIEF_STEPS
  var radius := lerpf(neck_radius*0.98, cable_radius, t)
  var rib_envelope := sin(PI*t)
  var rib := pow(maxf(0.0, sin(t*TAU*5.0)), 2.0) * cable_radius*0.16 * rib_envelope
  radius += rib
  relief_profiles.append(Vector4(end_shell-0.00015+(relief_length+0.00015)*t, radius, radius, 1.0))
 _add_part("FlexibleStrainRelief", _loft(relief_profiles), relief_material)
 return true

func get_cable_exit_anchor() -> Vector3:
 return transform * cable_exit_local

func get_outward_tangent() -> Vector3:
 return transform.basis.z.normalized()

func get_socket_face_anchor() -> Vector3:
 return transform.origin

func get_local_bounds() -> AABB:
 return _local_bounds

func get_parent_bounds() -> AABB:
 return transform * _local_bounds

func _clear() -> void:
 for child in get_children():
  remove_child(child)
  child.queue_free()
 configuration_error = ""
 dimensions.clear()
 cable_exit_local = Vector3.ZERO
 socket_face_local = Vector3.ZERO
 insertion_overlap = 0.0
 recess_depth = 0.0
 _local_bounds = AABB()
 transform = Transform3D.IDENTITY

func _fail(message: String) -> bool:
 configuration_error = message
 return false

func _add_part(part_name: String, mesh: ArrayMesh, material: StandardMaterial3D) -> void:
 var part := MeshInstance3D.new()
 part.name = part_name
 part.mesh = mesh
 part.material_override = material
 add_child(part)
 _local_bounds = mesh.get_aabb() if get_child_count() == 1 else _local_bounds.merge(mesh.get_aabb())

func _profile_point(profile: Vector4, side: int, lower_taper: float) -> Vector3:
 var angle := TAU * float(side)/RADIAL_SEGMENTS
 var cx := cos(angle)
 var sy := sin(angle)
 var x := signf(cx) * pow(absf(cx), profile.w) * profile.y
 var y := signf(sy) * pow(absf(sy), profile.w) * profile.z
 # Physical D orientation: lower corners narrower than the top, never wider.
 if y < 0.0: x *= 1.0-lower_taper*(-y/profile.z)
 return Vector3(x, y, profile.x)

func _loft(profiles: Array[Vector4], lower_taper: float = 0.0) -> ArrayMesh:
 var vertices := PackedVector3Array()
 var normals := PackedVector3Array()
 var indices := PackedInt32Array()
 for row in profiles.size():
  for side in RADIAL_SEGMENTS:
   var p := _profile_point(profiles[row], side, lower_taper)
   var across := _profile_point(profiles[row], (side+1)%RADIAL_SEGMENTS, lower_taper)-_profile_point(profiles[row], (side+RADIAL_SEGMENTS-1)%RADIAL_SEGMENTS, lower_taper)
   var along := _profile_point(profiles[mini(row+1, profiles.size()-1)], side, lower_taper)-_profile_point(profiles[maxi(row-1, 0)], side, lower_taper)
   vertices.append(p)
   normals.append(across.cross(along).normalized())
 for row in profiles.size()-1:
  for side in RADIAL_SEGMENTS:
   var next := (side+1)%RADIAL_SEGMENTS
   var a := row*RADIAL_SEGMENTS+side
   var b := (row+1)*RADIAL_SEGMENTS+side
   var c := (row+1)*RADIAL_SEGMENTS+next
   var d := row*RADIAL_SEGMENTS+next
   indices.append_array(PackedInt32Array([a,b,c,a,c,d]))
 # Flat caps use their own normals, avoiding a seam caused by averaging cap normals.
 for at_end in [false, true]:
  var row := profiles.size()-1 if at_end else 0
  var cap_start := vertices.size()
  var normal := Vector3.BACK if at_end else Vector3.FORWARD
  vertices.append(Vector3(0,0,profiles[row].x))
  normals.append(normal)
  for side in RADIAL_SEGMENTS:
   vertices.append(_profile_point(profiles[row], side, lower_taper))
   normals.append(normal)
  for side in RADIAL_SEGMENTS:
   var a := cap_start+1+side
   var b := cap_start+1+(side+1)%RADIAL_SEGMENTS
   indices.append_array(PackedInt32Array([cap_start,b,a] if at_end else [cap_start,a,b]))
 var arrays: Array = []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = vertices
 arrays[Mesh.ARRAY_NORMAL] = normals
 arrays[Mesh.ARRAY_INDEX] = indices
 var mesh := ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
 return mesh
