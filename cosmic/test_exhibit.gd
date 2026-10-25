extends SceneTree
## Geometry/integration contract only; not a substitute for visual QA.
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
 var exhibit = load("res://cosmic/exhibit_scene.gd").new()
 root.add_child(exhibit)
 var system = load("res://cosmic/master_system.tres")
 check(exhibit.configure(system), "Exhibit configures without missing anchors")
 await process_frame
 check(exhibit.pads.size() == 2, "Two instances of neutral controller")
 check(exhibit.cables.size() == 2, "Two independent runtime cables")
 check(not exhibit.manual_available, "Missing manual is explicit")
 check(exhibit.game_box == null, "No invented selected game")
 for index in exhibit.cable_paths.size():
  var points: PackedVector3Array = exhibit.cable_paths[index]
  var anchor: Node3D = exhibit.pads[index].find_child("ControllerCableAnchor", true, false)
  check(points[0].distance_to(exhibit.relative_transform(anchor).origin)<0.0001,"Cable starts at actual pad anchor")
  check(points[-1].distance_to(exhibit.socket_positions[index])<0.0001,"Cable ends at actual console socket")
  check((points[1]-points[0]).normalized().dot(exhibit.relative_transform(anchor).basis.x.normalized())>0.90,"Cable respects verified rear-entry tangent")
  for point in points:
   check(point.is_finite() and point.y>=0.0015,"Cable stays finite and above invisible presentation plane")
 var bounds: AABB = exhibit.get_local_bounds()
 print("EXHIBIT_BOUNDS ",bounds)
 print("EXHIBIT_SOCKETS ",exhibit.socket_positions)
 check(bounds.size.x<=0.801 and bounds.size.z<=0.521,"Assembly remains inside invisible layout footprint")
 check(exhibit.configure(system), "Repeated configuration replaces rather than duplicates")
 check(exhibit.pads.size()==2 and exhibit.cables.size()==2,"Repeated configuration resets component arrays")
 var console_mesh_count: int = exhibit.console.find_children("*", "MeshInstance3D", true, false).size()
 var extras = load("res://cosmic/exhibit_scene.gd").new()
 root.add_child(extras)
 var selected := {"id":"test_selected_game", "title":"Selected game fixture"}
 check(extras.configure_extras(exhibit.console, selected), "Extras attach to existing console without ownership change")
 check(exhibit.console.find_children("*", "MeshInstance3D", true, false).size()==console_mesh_count,"Extras never become console descendants")
 check(extras.game_box.item_id=="test_selected_game", "Box retains selected game identity")
 check(extras.game_box.opened and extras.inserted_cartridge != null,"Original open box and matching cartridge retained without duplication")
 check(extras.selected_item==selected,"Selected item data is preserved")
 print("EXHIBIT_COMBINED_WITH_BOX ",extras.get_combined_bounds())
 extras.queue_free()
 exhibit.queue_free()
 await process_frame
 print("EXHIBIT_CONTRACT: ", "PASS" if failures.is_empty() else "FAIL", " assertions=",assertions," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
