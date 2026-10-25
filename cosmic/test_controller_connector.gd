extends SceneTree
## Geometry/API tests, not a substitute for rendered visual inspection or OEM CAD.
const Connector = preload("res://cosmic/controller_connector.gd")
var failures: Array[String] = []
var assertions := 0

func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok:
  failures.append(message)
  push_error(message)

func _initialize() -> void:
 run.call_deferred()

func run() -> void:
 var connector := Connector.new()
 root.add_child(connector)
 var socket_bounds := AABB(Vector3(-0.010,-0.00425,-0.0005),Vector3(0.020,0.0085,0.001))
 var socket_transform := Transform3D(Basis.IDENTITY, Vector3(-0.019,0.0175,0.083075))
 check(connector.configure(socket_transform,socket_bounds), "Known socket dimensions configure")
 check(connector.get_child_count()==3, "Nose, molded housing and relief remain distinct")
 check(connector.get_socket_face_anchor().distance_to(Vector3(-0.019,0.0175,0.083575))<0.000001, "Socket mouth uses actual transformed front face")
 check(connector.get_outward_tangent().is_equal_approx(Vector3.BACK), "Cable leaves the socket toward positive Z")
 var bounds := connector.get_local_bounds()
 check(bounds.position.z < 0.0 and bounds.position.z >= -0.0007, "Nose modestly overlaps socket contact mouth")
 check(is_equal_approx(bounds.end.z, connector.cable_exit_local.z), "Precise exit anchor is the relief end plane")
 check(bounds.size.x < 0.024 and bounds.size.y < 0.012, "Visible shell fits original port region without neighboring contact")
 check(bounds.size.z < 0.045, "Plug length remains bounded")
 var nose := connector.get_node("InsertedConnectorNose") as MeshInstance3D
 var shell := connector.get_node("MoldedConnectorHousing") as MeshInstance3D
 var relief := connector.get_node("FlexibleStrainRelief") as MeshInstance3D
 check(nose.get_aabb().size.x<=socket_bounds.size.x and nose.get_aabb().size.y<=socket_bounds.size.y, "Inserted nose remains narrower than actual socket face")
 check(shell.get_aabb().position.z >= connector.recess_depth, "Wide housing begins beyond the original outer frame")
 check(nose.get_aabb().end.z > shell.get_aabb().position.z, "Nose and shell meet without daylight")
 check(relief.get_aabb().position.z < shell.get_aabb().end.z, "Relief meets shell without a gap")
 var triangle_count := 0
 for part in connector.get_children():
  var mesh: ArrayMesh = part.mesh
  var arrays := mesh.surface_get_arrays(0)
  var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
  var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
  triangle_count += indices.size()/3
  for i in vertices.size():
   if not vertices[i].is_finite() or not normals[i].is_finite() or absf(normals[i].length()-1.0)>0.001:
    check(false, "Every vertex and normal is finite, with unit normals")
  for index in indices:
   if index<0 or index>=vertices.size(): check(false, "Every triangle index is valid")
  var winding_ok := true
  for triangle in range(0, indices.size(), 3):
   var a := indices[triangle]
   var b := indices[triangle+1]
   var c := indices[triangle+2]
   var face := (vertices[c]-vertices[a]).cross(vertices[b]-vertices[a])
   if face.length_squared()<1e-22 or face.normalized().dot((normals[a]+normals[b]+normals[c]).normalized())<0.80:
    winding_ok = false
  check(winding_ok, "Closed loft triangles have finite area and consistent outward winding")
  var material := part.material_override as StandardMaterial3D
  check(material.albedo_color.r < 0.09 and material.roughness>=0.699, "Molded black material is not pale or metallic")
 check(triangle_count < 9000, "Connector stays below bounded geometry budget")
 check(connector.configure(socket_transform,socket_bounds), "Repeated configuration succeeds")
 check(connector.get_child_count()==3, "Repeated configuration replaces previous geometry")
 # Transform contract: rotation and nonuniform scale produce physical dimensions and
 # exit/tangent in caller space, not accidental global coordinates.
 var rotation := Basis.from_euler(Vector3(0.22,-0.81,0.12))
 var rotated := Transform3D(rotation.scaled(Vector3(1.1,0.9,1.2)), Vector3(0.4,0.7,-0.2))
 check(connector.configure(rotated,socket_bounds,0.0013,0.004), "Rotated scaled socket configures")
 var expected_face := rotated*Vector3(0,0,socket_bounds.end.z)
 check(connector.get_socket_face_anchor().distance_to(expected_face)<0.000001, "Arbitrary socket transform preserves face anchor")
 check(connector.get_outward_tangent().dot(rotated.basis.z.normalized())>0.99999, "Arbitrary socket transform preserves outward direction")
 check((connector.get_cable_exit_anchor()-expected_face).normalized().dot(connector.get_outward_tangent())>0.99999, "Exit and tangent are exactly collinear with plug axis")
 check(connector.get_parent_bounds().has_point(connector.get_cable_exit_anchor()-connector.get_outward_tangent()*0.00001), "Parent bounds contain the relief exit")
 check(not connector.configure(Transform3D.IDENTITY,AABB()), "Degenerate socket is rejected")
 check(connector.get_child_count()==0 and not connector.configuration_error.is_empty(), "Rejected configuration leaves no stale plug")
 check(not connector.configure(Transform3D.IDENTITY,socket_bounds,-0.001), "Negative cable radius is rejected")
 check(not connector.configure(Transform3D.IDENTITY,socket_bounds,0.0015,-0.001), "Negative recess is rejected")
 # Verify both original imported sockets, measured original outer frame and all of
 # the actual contact pin locations without changing any console geometry.
 var system = load("res://cosmic/master_system.tres")
 var console: Node3D = system.model.instantiate()
 root.add_child(console)
 for port in 2:
  var socket := console.find_child("Controller_port_socket_%d"%port,true,false) as MeshInstance3D
  var frame := console.find_child("Controller_port_open_frame_%d"%port,true,false) as MeshInstance3D
  var socket_in_root := socket.global_transform
  var frame_bounds: AABB = frame.global_transform*frame.get_aabb()
  var actual_bounds: AABB = socket_in_root*socket.get_aabb()
  var actual_recess := frame_bounds.end.z-actual_bounds.end.z
  check(connector.configure(socket_in_root,socket.get_aabb(),0.0015,actual_recess), "Original imported socket %d configures"%port)
  check(absf(actual_recess-0.0056)<0.00001, "Measured source recess is 5.6 mm")
  var connector_shell: MeshInstance3D = connector.get_node("MoldedConnectorHousing")
  var shell_in_root: AABB = connector.global_transform*connector_shell.get_aabb()
  check(shell_in_root.position.z>frame_bounds.end.z, "Original outer frame is never pierced by widened housing")
  var actual_nose := connector.get_node("InsertedConnectorNose") as MeshInstance3D
  var nose_bounds := actual_nose.get_aabb()
  var nose_arrays := actual_nose.mesh.surface_get_arrays(0)
  var nose_vertices: PackedVector3Array = nose_arrays[Mesh.ARRAY_VERTEX]
  var outline := PackedVector2Array()
  for side in Connector.RADIAL_SEGMENTS:
   var p := nose_vertices[Connector.RADIAL_SEGMENTS+side]
   outline.append(Vector2(p.x,p.y))
  var covered_contacts := 0
  var actual_face_center := actual_bounds.get_center()
  for contact in console.find_children("Socket_contact*", "MeshInstance3D", true, false):
   if absf(contact.global_position.x-actual_face_center.x)>actual_bounds.size.x*0.5: continue
   covered_contacts += 1
   var contact_bounds: AABB = connector.global_transform.affine_inverse()*contact.global_transform*contact.get_aabb()
   check(contact_bounds.position.z>nose_bounds.position.z and contact_bounds.end.z<nose_bounds.end.z, "Original contact is contained within insertion nose length")
   var enclosed := true
   for corner in 8:
    var p := contact_bounds.get_endpoint(corner)
    if not Geometry2D.is_point_in_polygon(Vector2(p.x,p.y),outline): enclosed = false
   check(enclosed, "Original contact is enclosed by the actual D-shaped nose silhouette")
  check(covered_contacts==9, "Exactly nine original contacts are concealed by this plug")
  print("CONNECTOR_PORT ",port," mouth=",connector.get_socket_face_anchor()," exit=",connector.get_cable_exit_anchor()," bounds=",connector.get_parent_bounds())
 print("CONNECTOR_TRIANGLES ",triangle_count)
 print("CONNECTOR_CONTRACT: ","PASS" if failures.is_empty() else "FAIL"," assertions=",assertions," failures=",failures.size())
 connector.queue_free()
 console.queue_free()
 await process_frame
 quit(0 if failures.is_empty() else 1)
