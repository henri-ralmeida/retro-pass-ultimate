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
 check(is_equal_approx(exhibit.game_box.lid.rotation.z,deg_to_rad(90.0)),"Non-rendered bounds proxy retains stable 90-degree layout envelope")
 check(exhibit.relative_transform(exhibit.game_box.original_model).basis.get_scale().is_equal_approx(Vector3.ONE),"Background box uses exact native scale")
 check(exhibit.relative_transform(exhibit.inserted_cartridge).basis.get_scale().is_equal_approx(Vector3.ONE),"Inserted cartridge uses same native scale")
 var cover: MeshInstance3D = exhibit.game_box.find_child("Box_FRONT",true,false)
 var base: MeshInstance3D = exhibit.game_box.find_child("Case_back",true,false)
 var lid_mesh: MeshInstance3D = exhibit.game_box.find_child("Case_lid",true,false)
 var base_normal: Vector3 = (exhibit.relative_transform(base).basis*Vector3.UP).normalized()
 var lid_normal: Vector3 = (exhibit.relative_transform(lid_mesh).basis*Vector3.DOWN).normalized()
 check(base_normal.dot(exhibit.presentation_basis.z)<-0.10 and lid_normal.dot(exhibit.presentation_basis.z)<-0.10,"Both opened exterior surfaces face presentation camera")
 check(exhibit.find_child("BackgroundMatchingCartridge",true,false)==null,"HOME preserves only the seated cartridge")
 check(exhibit.projected_horizontal_span(exhibit.game_box).y+0.017<exhibit.projected_horizontal_span(scene.model).x,"Open box is fully left of console without projected overlap")
 var cover_center: Vector3 = exhibit.relative_transform(cover)*cover.get_aabb().get_center()
 check((cover_center-exhibit.bounds_of(scene.model).get_center()).dot(exhibit.presentation_basis.z)<-0.15,"Open box cover is behind console in camera depth")
 check(exhibit.inserted_cartridge.get_meta("selected_game_id")==exhibit.selected_item.id,"Inserted cartridge retains selected identity")
 check(not exhibit.manual_available,"No fictitious manual pages")
 var actual_missing: bool = exhibit.hardware_art_missing
 exhibit.hardware_art_missing = true
 scene._sync_exhibit_visibility()
 check(scene.status.visible and scene.status.text=="Texturas do controle indisponíveis · sem emulação","Fallback hardware displays compact honest status")
 exhibit.hardware_art_missing = false
 scene._sync_exhibit_visibility()
 check(not scene.status.visible,"Faithful private hardware leaves normal UI uncluttered")
 exhibit.hardware_art_missing = actual_missing
 scene._sync_exhibit_visibility()
 check(exhibit.slot_ready and exhibit.slot_surfaces.size()==2,"Bounded clipping covers exactly two original shell surfaces")
 var console_inverse: Transform3D = exhibit.relative_transform(scene.model).affine_inverse()
 var native_seated: AABB = console_inverse*exhibit.bounds_of(exhibit.inserted_cartridge)
 check(is_equal_approx(native_seated.end.y-exhibit.original_slot_top,0.026),"Reference-fit exposed height is approximately 26 mm")
 check(native_seated.position.y>exhibit.slot_clip_min.y and native_seated.end.y>exhibit.slot_clip_max.y,"Slot cutout contains inserted body but not exposed upper band")
 check(exhibit.slot_clip_min.y>-0.0245+0.001,"Original exterior bottom remains outside clipping prism")
 for cap_y in [0.0245,-0.0075,-0.0085]:
  check(cap_y>exhibit.slot_clip_min.y and cap_y<exhibit.slot_clip_max.y,"Audited solid cap lies inside reversible cutout")
 check(not exhibit.dust_door.visible,"Original dust flap is hidden only while inserted")
 for record in exhibit.slot_surfaces:
  check(record.mesh.mesh==record.original_mesh,"Clipping preserves original mesh resource")
  check(record.mesh.get_surface_override_material(record.surface)==record.display_material,"Display clipping material active")
  check(record.display_material.get_shader_parameter("abs_color")==record.source_material.albedo_color,"Display clipping retains original ABS color")
  check(record.display_material.get_shader_parameter("normal_map")==record.source_material.normal_texture,"Display clipping retains original ABS normal map")
 check(exhibit.connectors.size()==2,"Both cables have molded plug housings")
 check(exhibit.cable_diagnostics.size()==2,"Two nominal-length cable routes report diagnostics")
 for diagnostics in exhibit.cable_diagnostics:
  check(absf(diagnostics.actual_length-2.0)<0.002,"Each cable follows nominal 2 m assembly within display tolerance")
  check(diagnostics.minimum_centerline_separation>=0.0045,"Full cable route has no self-crossing")
 for index in exhibit.cable_paths.size():
  var points: PackedVector3Array = exhibit.cable_paths[index]
  check(points[-1].distance_to(exhibit.connectors[index].get_cable_exit_anchor())<0.00001,"Cable meets molded relief endpoint")
  var outward: Vector3 = exhibit.connectors[index].get_outward_tangent()
  check((points[-2]-points[-1]).normalized().dot(outward)>0.9,"Cable enters plug along outward relief tangent")
  for point_index in range(1,points.size()-1):
   for pad in exhibit.pads:
    check(not exhibit.bounds_of(pad).grow(-0.001).has_point(points[point_index]),"Slack route avoids controller body")
   for connector in exhibit.connectors:
    check(not connector.get_parent_bounds().grow(-0.0005).has_point(points[point_index]),"Slack route avoids molded plug body")
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
  var low := Vector2(INF,INF)
  var high := Vector2(-INF,-INF)
  var points: PackedVector3Array = exhibit.get_visible_world_corners()
  check(not points.is_empty(),"Normal fit uses actual visible mesh corners")
  for world in points:
   var projected: Vector2 = scene.camera.unproject_position(world)/Vector2(scene.viewport.size)
   low = low.min(projected)
   high = high.max(projected)
   check(projected.x>=0.04 and projected.x<=0.96 and projected.y>=0.04 and projected.y<=0.96,"Actual visible geometry fits viewport at "+str(size)+": "+str(projected))
  check(((low+high)*0.5).distance_to(Vector2(0.5,0.5))<0.001,"Actual projected group is centered")
  check(maxf((high-low).x,(high-low).y)>0.90,"Useful projected group fills frame rather than imaginary AABB corners")
  check(scene.camera.basis.is_equal_approx(exhibit.presentation_basis),"Normal framing retains approved view basis")
 scene.toggle_inspection()
 check(not exhibit.visible,"Dedicated inspection hides extras")
 check(exhibit.dust_door.transform==original_door,"Inspection restores exact dust-door transform")
 check(exhibit.dust_door.visible==exhibit.dust_door_was_visible,"Inspection restores exact dust-door visibility")
 check(exhibit.slot_well.transform==exhibit.well_rest,"Inspection restores original well floor transform")
 for record in exhibit.slot_surfaces:
  check(record.mesh.get_surface_override_material(record.surface)==record.original_override,"Inspection restores original material reference")
  check(record.mesh.mesh==record.original_mesh,"Inspection retains original geometry reference")
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
 var fit_position: Vector3 = scene.camera.position
 var fit_basis: Basis = scene.camera.basis
 var fit_size: float = scene.camera.size
 scene.enter_library()
 scene._apply_entry(0.0)
 check(scene.camera.position.is_equal_approx(fit_position),"Animated entry starts at fitted camera position without a jump")
 check(scene.camera.basis.is_equal_approx(fit_basis),"Animated entry starts at fitted camera orientation without a jump")
 check(is_equal_approx(scene.camera.size,fit_size),"Animated entry starts at fitted camera size without a jump")
 check(scene.exhibit.visible,"Animated entry retains extras before veil covers scene")
 scene._apply_entry(0.94)
 check(not scene.exhibit.visible and scene.entry_veil.color.a>=0.99,"Animated entry hides extras only behind opaque veil")
 scene.leave_library()
 check(scene.exhibit.visible,"Interrupted entry restores selected exhibit")
 check(scene.camera.position.is_equal_approx(fit_position) and scene.camera.basis.is_equal_approx(fit_basis) and is_equal_approx(scene.camera.size,fit_size),"Interrupted entry restores exact fitted camera")
 check(scene.exhibit.presentation_basis.is_equal_approx(fit_basis),"Return rebuild uses approved view basis, not transient entry basis")
 scene.exhibit.set_exhibit_visible(false)
 check(scene.exhibit.dust_door.transform==scene.exhibit.dust_door_rest,"Explicit hiding restores door")
 var restored_records: Array = scene.exhibit.slot_surfaces.duplicate()
 var restored_well: MeshInstance3D = scene.exhibit.slot_well
 var restored_well_transform: Transform3D = scene.exhibit.well_rest
 var restored_door: Node3D = scene.exhibit.dust_door
 var restored_door_visible: bool = scene.exhibit.dust_door_was_visible
 scene.exhibit.set_exhibit_visible(true)
 scene.exhibit.queue_free()
 await process_frame
 check(restored_well.transform==restored_well_transform,"Freeing active exhibit restores original well")
 check(restored_door.visible==restored_door_visible,"Freeing active exhibit restores original door visibility")
 for record in restored_records:
  check(record.mesh.get_surface_override_material(record.surface)==record.original_override,"Freeing active exhibit restores original material reference")
 var lower_shell: MeshInstance3D = scene.model.find_child("Lower_molded_shell",true,false)
 var lower_original: Material = lower_shell.get_surface_override_material(0)
 var unsupported := ShaderMaterial.new()
 lower_shell.set_surface_override_material(0,unsupported)
 var failed_exhibit = load("res://cosmic/exhibit_scene.gd").new()
 scene.presentation.add_child(failed_exhibit)
 check(not failed_exhibit.configure_extras(scene.model,scene.library_view.ITEMS[scene.library_view.current_index]),"Unsupported shell material refuses insertion safely")
 check(not failed_exhibit.slot_ready and failed_exhibit.slot_surfaces.is_empty(),"Failed seat clears partial clipping records")
 check(failed_exhibit.inserted_cartridge==null and is_instance_valid(failed_exhibit.game_box.cartridge),"Failed seat leaves original cartridge in box")
 check(failed_exhibit.game_box.cartridge.transform==failed_exhibit.game_box.inside_pose,"Failed seat restores exact original cartridge pose")
 check(failed_exhibit.game_box.cartridge.get_parent().name=="SMS_BOX_ROOT","Failed seat restores exact original cartridge parent")
 check(lower_shell.get_surface_override_material(0)==unsupported,"Failed seat preserves pre-existing unsupported material reference")
 check(restored_well.transform==restored_well_transform and restored_door.visible==restored_door_visible,"Failed seat preserves original well and door state")
 failed_exhibit.queue_free()
 await process_frame
 lower_shell.set_surface_override_material(0,lower_original)
 scene.queue_free()
 await process_frame
 print("EXHIBIT_INTEGRATION: ","PASS" if failures.is_empty() else "FAIL"," assertions=",assertions," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
