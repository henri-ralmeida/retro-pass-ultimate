extends SceneTree
## Synthetic geometry/state regression. Does not replace visual or hardware QA.
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
 var scene = load("res://cosmic/main.tscn").instantiate()
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene._focus_returned()
 scene.reduced_motion = true
 var exhibit: Node3D = scene.exhibit
 check(is_instance_valid(exhibit), "Default collection builds floating exhibit")
 if not is_instance_valid(exhibit):
  quit(1)
  return
 check(exhibit.get_parent()==scene.presentation, "Extras are siblings of inspection pivot")
 check(scene.model.find_children("*","MeshInstance3D",true,false).size()==184,"Approved console remains 184 meshes")
 check(exhibit.selected_item==scene.library_view.ITEMS[scene.library_view.current_index],"Exhibit uses actual current catalog entry")
 check(exhibit.inserted_cartridge != null,"Same-game cartridge seated in top well")
 check(exhibit.game_box.cartridge==null,"Open box has no duplicate cartridge")
 check(exhibit.inserted_cartridge.get_meta("selected_game_id")==exhibit.selected_item.id,"Inserted cartridge retains selected identity")
 check(not exhibit.manual_available,"No fictitious manual pages")
 var original_bounds: AABB = scene.model_bounds
 var original_door: Transform3D = exhibit.dust_door_rest
 var cartridge_bounds: AABB = exhibit.bounds_of(exhibit.inserted_cartridge)
 var well: MeshInstance3D = scene.model.find_child("Cartridge_well",true,false)
 var well_bounds: AABB = exhibit.relative_transform(well)*well.get_aabb()
 check(cartridge_bounds.position.y>=well_bounds.end.y,"Cartridge does not pierce solid well floor")
 check(cartridge_bounds.position.x>=well_bounds.position.x and cartridge_bounds.end.x<=well_bounds.end.x,"Cartridge fits slot width")
 check(cartridge_bounds.position.z>=well_bounds.position.z and cartridge_bounds.end.z<=well_bounds.end.z,"Cartridge fits slot depth")
 for size in [Vector2i(1152,648), Vector2i(1024,768)]:
  root.size = size
  await process_frame
  scene._layout()
  var bounds: AABB = exhibit.get_combined_bounds()
  for index in 8:
   var world: Vector3 = scene.presentation.to_global(bounds.get_endpoint(index))
   var projected: Vector2 = scene.camera.unproject_position(world)/Vector2(scene.viewport.size)
   check(projected.x>=0.04 and projected.x<=0.96 and projected.y>=0.04 and projected.y<=0.96,"Normal combined exhibit fits viewport at "+str(size)+": "+str(projected))
 scene.toggle_inspection()
 check(not exhibit.visible,"Dedicated inspection hides extras")
 check(exhibit.dust_door.transform==original_door,"Inspection restores exact dust-door transform")
 check(scene.model_bounds==original_bounds,"Inspection bounds remain unchanged")
 scene.rotate_inspection(Vector2(540,270))
 scene.zoom_inspection(4)
 check(not exhibit.visible,"Rotation/zoom never reactivates extras")
 scene.close_inspection()
 check(exhibit.visible,"Closing inspection returns selected exhibit")
 scene.open_history(false)
 check(not exhibit.visible,"History hides extras")
 check(exhibit.dust_door.transform==original_door,"History restores original console")
 scene.close_history()
 check(exhibit.visible,"Closing history returns exhibit")
 scene.enter_library()
 check(not exhibit.visible,"Library transition hides extras")
 check(exhibit.dust_door.transform==original_door,"Library transition restores original door")
 scene.leave_library()
 check(scene.exhibit.visible,"Returning from collection rebuilds exhibit")
 check(scene.exhibit.selected_item==scene.library_view.ITEMS[scene.library_view.current_index],"Returning uses current selection, not a hard-coded game")
 scene.history_open = false
 scene.history_blend = 0.5
 scene._sync_exhibit_visibility()
 check(not scene.exhibit.visible,"Closing history keeps extras hidden while panel is sliding")
 scene.history_blend = 0.0
 scene._layout()
 check(scene.exhibit.visible,"Settled history return restores extras")
 scene.reduced_motion = false
 scene.enter_library()
 check(scene.exhibit.visible,"Animated entry retains extras before veil covers scene")
 scene._apply_entry(0.94)
 check(not scene.exhibit.visible and scene.entry_veil.color.a>=0.99,"Animated entry hides extras only behind opaque veil")
 scene.leave_library()
 check(scene.exhibit.visible,"Interrupted entry restores selected exhibit")
 scene.exhibit.set_exhibit_visible(false)
 check(scene.exhibit.dust_door.transform==scene.exhibit.dust_door_rest,"Explicit hiding restores door")
 scene.queue_free()
 await process_frame
 print("EXHIBIT_INTEGRATION: ","PASS" if failures.is_empty() else "FAIL"," assertions=",assertions," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
