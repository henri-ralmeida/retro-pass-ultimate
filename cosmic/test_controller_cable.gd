extends SceneTree
const Cable = preload("res://cosmic/controller_cable.gd")
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
 var cable := Cable.new()
 var fixtures := [
  {"start":Vector3(-0.0368,0.0105,0.095),"finish":Vector3(0.006,0.011,0.046425),"coil_center":Vector3(-0.13,0.004,0.245),"lead_out_guides":PackedVector3Array([Vector3(-0.23,0.004,0.35),Vector3(-0.005,0.004,0.35),Vector3(-0.005,0.008,0.12)])},
  {"start":Vector3(0.1732,0.0105,0.095),"finish":Vector3(0.038,0.011,0.046425),"coil_center":Vector3(0.16,0.004,0.245),"lead_out_guides":PackedVector3Array([Vector3(0.055,0.004,0.34),Vector3(0.025,0.004,0.20),Vector3(0.038,0.008,0.10)])}]
 var side_paths: Array[PackedVector3Array] = []
 var rear_paths: Array[PackedVector3Array] = []
 var models := ["res://assets/local_hardware_art/SMS_Controller_REV2_faithful_private.glb","res://assets/exhibit_models/SMS_Controller_neutral.glb"]
 var source_obstacles: Array[Array] = []
 var source_anchors: Array[PackedVector3Array] = []
 for model_path in models:
  var obstacles: Array = []
  var anchors := PackedVector3Array()
  if FileAccess.file_exists(model_path):
   for index in 2:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    check(document.append_from_file(model_path,state)==OK,"Original controller model imports read-only")
    var pad := document.generate_scene(state) as Node3D
    root.add_child(pad)
    pad.position = Vector3(-0.095 if index==0 else 0.115,0,0.105)
    var anchor := pad.find_child("ControllerCableAnchor",true,false) as Node3D
    anchors.append(anchor.global_position)
    var bounds := AABB()
    var first := true
    for mesh in pad.find_children("*","MeshInstance3D",true,false):
     var current: AABB = mesh.global_transform*mesh.get_aabb()
     bounds = current if first else bounds.merge(current)
     first = false
    obstacles.append(bounds)
    pad.queue_free()
  source_obstacles.append(obstacles)
  source_anchors.append(anchors)
 for index in fixtures.size():
  var options: Dictionary = fixtures[index].duplicate()
  options["target_length"] = 2.0
  options["obstacles"] = source_obstacles[0]
  if source_anchors[0].size()==2:
   check(options.start.distance_to(source_anchors[0][index])<0.00001,"Side-entry fixture matches the unchanged imported anchor")
  options["outer_radius_min"] = 0.045
  options["outer_radius_max"] = 0.100
  var ok := cable.build(options.start,Vector3.RIGHT,options.finish,Vector3.BACK,options)
  print("CABLE_FIXTURE ",index," OK=",ok," ",cable.diagnostics)
  check(ok,"Full-length fixture %d has a clear bounded route"%index)
  if ok:
   side_paths.append(cable.points.duplicate())
   check(absf(cable.diagnostics.actual_length-2.0)<0.002,"Cable is within 2 mm of nominal length")
   check(cable.points[0].distance_to(options.start)<0.000001 and cable.points[-1].distance_to(options.finish)<0.000001,"Cable endpoints are exact")
   check(cable.diagnostics.minimum_centerline_separation>=0.0045,"Nonlocal cable segments do not self-intersect")
   check(cable.diagnostics.minimum_bend_radius>=0.0075,"Cable stays above declared minimum bend radius")
   check(cable.diagnostics.bounds.size.x<0.35 and cable.diagnostics.bounds.size.z<0.40,"Cable coil remains compact")
 if side_paths.size()==2:
  var clearance := Cable.minimum_between_paths(side_paths[0],side_paths[1])
  print("SIDE_PAIR_CLEARANCE ",clearance)
  check(clearance>=0.0045,"Both separate controller lanes clear one another")
 for index in fixtures.size():
  var options: Dictionary = fixtures[index].duplicate()
  options["target_length"] = 2.0
  options["outer_radius_min"] = 0.045
  options["outer_radius_max"] = 0.100
  options["start"] = Vector3(-0.084 if index==0 else 0.126,0.0105,0.0785)
  options["lead_in_guides"] = PackedVector3Array([Vector3(-0.065,0.004,0.05),Vector3(-0.02,0.004,0.075),Vector3(-0.02,0.004,0.15)]) if index==0 else PackedVector3Array([Vector3(0.15,0.004,0.045),Vector3(0.21,0.004,0.075),Vector3(0.235,0.004,0.16)])
  options["obstacles"] = source_obstacles[1]
  if source_anchors[1].size()==2:
   check(options.start.distance_to(source_anchors[1][index])<0.00001,"Rear-entry fixture matches the unchanged imported anchor")
  var ok := cable.build(options.start,Vector3.FORWARD,options.finish,Vector3.BACK,options)
  print("REAR_FIXTURE ",index," OK=",ok," ",cable.diagnostics)
  check(ok,"Rear-entry fallback controller %d respects its actual departure tangent"%index)
  if ok: rear_paths.append(cable.points.duplicate())
 if rear_paths.size()==2:
  var clearance := Cable.minimum_between_paths(rear_paths[0],rear_paths[1])
  print("REAR_PAIR_CLEARANCE ",clearance)
  check(clearance>=0.0045,"Rear-entry controller lanes clear one another")
 # The helper must reject collisions, not quietly shorten, hide or teleport wire.
 var collision_options: Dictionary = fixtures[0].duplicate()
 collision_options["outer_radius_min"] = 0.045
 collision_options["obstacles"] = [AABB(Vector3(-1,-1,-1),Vector3(2,2,2))]
 check(not cable.build(collision_options.start,Vector3.RIGHT,collision_options.finish,Vector3.BACK,collision_options),"Protected obstacle collision is rejected")
 check(cable.error.contains("protected"),"Obstacle failure has the correct actionable reason")
 var crossing_options: Dictionary = fixtures[0].duplicate()
 crossing_options.erase("lead_out_guides")
 crossing_options["outer_radius_max"] = 0.13
 check(not cable.build(crossing_options.start,Vector3.RIGHT,crossing_options.finish,Vector3.BACK,crossing_options),"Lead crossing through the coil is rejected")
 # A rigid transform changes only the caller-space positions, not cable dimensions.
 var original_options: Dictionary = fixtures[1].duplicate()
 original_options["outer_radius_min"] = 0.045
 check(cable.build(original_options.start,Vector3.RIGHT,original_options.finish,Vector3.BACK,original_options),"Original fixture rebuilt for transform test")
 var baseline := cable.points.duplicate()
 var transform := Transform3D(Basis.from_euler(Vector3(0.15,-0.65,0.1)),Vector3(0.3,0.2,-0.4))
 var rotated_options: Dictionary = original_options.duplicate()
 rotated_options["coil_center"] = transform*original_options.coil_center
 rotated_options["coil_basis"] = transform.basis
 var guides := PackedVector3Array()
 for guide in original_options.lead_out_guides: guides.append(transform*guide)
 rotated_options["lead_out_guides"] = guides
 check(cable.build(transform*original_options.start,transform.basis*Vector3.RIGHT,transform*original_options.finish,transform.basis*Vector3.BACK,rotated_options),"Arbitrary coil orientation and caller space are supported")
 if not cable.points.is_empty():
  check(absf(cable.diagnostics.actual_length-2.0)<0.002,"Transformed cable retains its nominal length")
  check(cable.points[0].distance_to(transform*baseline[0])<0.00001 and cable.points[-1].distance_to(transform*baseline[-1])<0.00001,"Transformed endpoints remain exact")
 check(not cable.build(Vector3.ZERO,Vector3.RIGHT,Vector3.ONE,Vector3.BACK,{"coil_center":Vector3.ZERO,"target_length":0.1}),"Impossible short length is rejected rather than clipped")
 check(cable.points.is_empty() and not cable.error.is_empty(),"Failed build exposes an error and no misleading path")
 print("CONTROLLER_CABLE_CONTRACT: ","PASS" if failures.is_empty() else "FAIL"," assertions=",assertions," failures=",failures.size())
 await process_frame
 quit(0 if failures.is_empty() else 1)
