extends SceneTree
## Synthetic local image fixture only. Never saves a catalog or represents a real manual.
var failures: Array[String] = []
var assertions := 0
func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var page := "user://synthetic_manual_integration.png"
 var image := Image.create(160,240,false,Image.FORMAT_RGBA8)
 image.fill(Color(0.15,0.4,0.55))
 image.save_png(page)
 var scene = load("res://cosmic/main.tscn").instantiate()
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene._focus_returned()
 scene.reduced_motion = true
 scene.cooldown = 0.0
 scene.enter_library()
 var view = scene.library_view
 var original: Dictionary = view.ITEMS[view.current_index].duplicate(true)
 var manifest := "user://synthetic_manual_manifest.json"
 FileAccess.open(manifest,FileAccess.WRITE).store_string(JSON.stringify({"items":[{"id":"synthetic_manual","title":"Synthetic fixture only","manual_pages":["synthetic_manual_integration.png"]}]}))
 view._load_items(manifest)
 check(view.ITEMS[0].manual_pages[0] == page,"Relative manual pages resolve next to explicit manifest")
 view.ITEMS[0] = original
 view._select(0)
 check(view.manual_button.disabled,"No supplied manual leaves button unavailable")
 check(not view.manual_reader.visible,"No synthetic manual appears in ordinary collection")
 view.ITEMS[view.current_index]["manual_pages"] = [page,page]
 view._refresh_manual_availability(view.ITEMS[view.current_index])
 check(not view.manual_button.disabled,"Explicit same-item image pages enable reader")
 view._open_manual()
 check(not view.manual_reader.visible,"Closed collection does not bypass presentation to open manual")
 view.confirm_selected()
 view._open_manual()
 check(view.manual_reader.visible,"Manual opens integrated modal")
 check(view.manual_button.visible and not view.confirm_button.visible,"Manual replaces redundant confirm action when contents are presented")
 var before_pose: Transform3D = view.box.cartridge.transform
 view._process(5.0)
 check(view.box.cartridge.transform.is_equal_approx(before_pose),"Reading pauses box presentation state")
 check(view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"3D viewport pauses behind reader")
 var before_index: int = view.current_index
 var before_yaw: float = view.yaw
 var right := InputEventKey.new()
 right.keycode = KEY_RIGHT
 right.pressed = true
 check(view.handle_event(right),"Reader consumes navigation before library")
 check(view.current_index == before_index and view.yaw == before_yaw,"Reader navigation never changes game or rotates box")
 view.manual_reader.dragging = true
 scene._focus_lost()
 check(view.manual_reader.visible,"Focus loss preserves visible manual")
 check(not view.manual_reader.dragging and not view.dragging,"Focus loss cancels both manual and box drags")
 scene._focus_returned()
 view.go_back()
 check(not view.manual_reader.visible and scene.library_state == "library","Back closes only reader, not collection")
 check(view.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,"Closing reader restores collection rendering")
 view.ITEMS[view.current_index]["manual_game_id"] = "different-game"
 view._open_manual()
 check(not view.manual_reader.visible and view.manual_button.disabled,"Mismatched manual identity stays unavailable")
 view.ITEMS[view.current_index].erase("manual_game_id")
 view._open_manual()
 view.close()
 check(not view.manual_reader.visible,"Closing library closes reader too")
 view.ITEMS[view.current_index] = original
 scene.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(page))
 DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest))
 print("MANUAL_INTEGRATION_TESTS ",JSON.stringify({"assertions":assertions,"passed":failures.is_empty(),"failures":failures}))
 quit(0 if failures.is_empty() else 1)
