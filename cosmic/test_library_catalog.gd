extends SceneTree
var failures: Array[String] = []
var assertions := 0
func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 # Isolate persistence and scan fixtures from any real collection.
 var catalog := "user://collection_catalog.json"
 var previous := FileAccess.get_file_as_bytes(catalog) if FileAccess.file_exists(catalog) else PackedByteArray()
 DirAccess.remove_absolute(ProjectSettings.globalize_path(catalog))
 OS.set_environment("RETROPASS_BOX_ART_MANIFEST", "")
 var folder := "user://library_scan_fixture"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
 FileAccess.open(folder+"/Local Fixture.sms",FileAccess.WRITE).store_string("test fixture, not a playable ROM")
 var scene = load("res://cosmic/main.tscn").instantiate()
 scene.input_profile.config_path = "user://library_catalog_controls.cfg"
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene._focus_returned()
 scene.reduced_motion = true
 scene.cooldown = 0.0
 scene.confirm_selection("catalog_test")
 var view = scene.library_view
 view._choose_scan_folder()
 check(view.scan_dialog.visible,"Scan opens an explicit directory chooser")
 var escape := InputEventKey.new()
 escape.keycode = KEY_ESCAPE
 escape.pressed = true
 check(not view.handle_event(escape),"Modal chooser input is not consumed by library navigation")
 view.scan_dialog.hide()
 view._scan_folder(ProjectSettings.globalize_path(folder))
 check(view.scan_button.text == "Cancelar leitura","Scan control becomes explicit cancellation instead of permitting duplicate requests")
 while view.scan_thread != null: await process_frame
 check(view.ITEMS.size() == 1 and view.ITEMS[0].title == "Local Fixture","Completed scan replaces collection with actual filename item")
 check(view.box.get_meta("original_room_geometry",false),"Scanned entry uses original articulated geometry, not simplified shell")
 check(view.box.can_open(),"Scanned entry retains original lid and cartridge")
 check(view.box.item.get("art_root", "").is_empty(),"Scan never inherits previous game's art root")
 check(view.card_textures[0].texture == null,"Absent scan cover remains unavailable")
 check("não configurado" in view.disclosure.text,"Unconfigured internet provider is explicit")
 check(view.neighbor_boxes.is_empty(),"Single game does not invent duplicate carousel boxes")
 var front = view.box.find_child("Box_FRONT",true,false)
 check(front != null and front.get_surface_override_material(0).albedo_texture == null,"Original front mesh remains neutral without supplied cover")
 view.toggle_inspection()
 view.confirm_selected()
 check(view.box.opened and view.box.cartridge_out,"Generic scanned item supports opening and cartridge extraction")
 # Every visible articulated mesh stays safely inside the perspective frame.
 for yaw in [0.0,0.8,PI,4.0]:
  view.yaw = yaw
  view.pitch = 0.4
  view.zoom = view.ZOOM_MAX
  view._apply_rotation()
  for mesh in view.box.find_children("*", "MeshInstance3D", true, false):
   if not mesh.mesh or not mesh.is_visible_in_tree(): continue
   for index in 8:
    var p: Vector2 = view.camera.unproject_position(mesh.to_global(mesh.get_aabb().get_endpoint(index)))/Vector2(view.viewport.size)
    check(p.x >= 0.049 and p.x <= 0.951 and p.y >= 0.049 and p.y <= 0.951,"Opened box/cartridge visible mesh corners stay framed")
 var saved_bytes := FileAccess.get_file_as_bytes(catalog)
 view._cancel_scan()
 check(view._scan_was_cancelled(),"Cancellation flag is explicitly observable across threads")
 var cancelled: Dictionary = view.scanner.scan_folder(ProjectSettings.globalize_path(folder),{"cancelled":view._scan_was_cancelled})
 check(cancelled.status == "cancelled","Scanner honors the UI cancellation callback")
 check(view.scanner.save_catalog(cancelled) != OK,"Cancelled result cannot replace catalog")
 check(FileAccess.get_file_as_bytes(catalog) == saved_bytes and view.ITEMS[0].title == "Local Fixture","Cancellation preserves saved and displayed collection")
 view.close()
 scene.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(folder+"/Local Fixture.sms"))
 DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
 if previous.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(catalog))
 else: FileAccess.open(catalog,FileAccess.WRITE).store_buffer(previous)
 var result := {"passed":failures.is_empty(),"assertions":assertions,"failures":failures,"mode":"headless explicit folder scan, catalog integration, original articulated geometry; no network or physical controller"}
 FileAccess.open("res://evidence/cosmic/library_catalog_tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("LIBRARY_CATALOG_TESTS ",JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
