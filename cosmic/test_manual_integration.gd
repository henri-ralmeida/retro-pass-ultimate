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
 view.ITEMS[0] = original.duplicate(true)
 view.ITEMS[0].erase("manual_pages")
 view.ITEMS[0].erase("manual_item_id")
 view._select(0)
 check(view.manual_button.disabled,"No supplied manual leaves button unavailable")
 check(not view.manual_reader.visible,"No synthetic manual appears in ordinary collection")
 view.ITEMS[view.current_index]["manual_pages"] = [page,page]
 view.ITEMS[view.current_index]["manual_item_id"] = str(view.ITEMS[view.current_index].id)
 view._select(view.current_index)
 view._refresh_manual_availability(view.ITEMS[view.current_index])
 check(not view.manual_button.disabled,"Explicit same-item image pages enable reader")
 view._open_manual()
 check(not view.manual_reader.visible,"Closed collection does not bypass presentation to open manual")
 view.confirm_selected()
 view._open_manual()
 if not view.manual_reader.visible: print("MANUAL_ENDPOINT_DIAGNOSTICS ",view.manual_release_diagnostics)
 check(view.manual_reader.visible,"Manual opens integrated modal")
 if not view.manual_release_diagnostics.is_empty():
  var endpoint: Dictionary = view.manual_release_diagnostics.back()
  check(bool(endpoint.get("clear",false)) and bool(endpoint.get("inside",false)),"Handoff endpoint is fully visible and clear of cartridge in screen space")
 check(view.manual_button.visible and not view.confirm_button.visible,"Manual replaces redundant confirm action when contents are presented")
 var before_pose: Transform3D = view.box.cartridge.transform
 view._process(5.0)
 check(view.box.cartridge.transform.is_equal_approx(before_pose),"Reading pauses box presentation state")
 check(view.viewport.render_target_update_mode in [SubViewport.UPDATE_ONCE,SubViewport.UPDATE_DISABLED],"3D viewport refreshes hidden source once, then pauses behind reader")
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
 # Voluntary physical release is interruptible and focus-paused. No lid/clip moves.
 scene.reduced_motion = false
 view._open_manual()
 check(view.manual_release_direction == 1 and not view.manual_reader.visible,"Real source leaves clips before reader appears")
 view._advance_manual_release(0.20)
 var release_before: float = view.manual_release_progress
 var source_pose: Transform3D = view.box.manual_book.root.transform
 scene._focus_lost()
 view._process(1.0)
 check(is_equal_approx(view.manual_release_progress,release_before) and view.box.manual_book.root.transform.is_equal_approx(source_pose),"Focus loss pauses physical release without hiding source")
 scene._focus_returned()
 view.go_back()
 check(view.manual_release_direction == -1,"Back reverses an unfinished physical release")
 view._advance_manual_release(2.0)
 check(view.manual_release_direction == 0 and view.manual_release == null and not view.manual_reader.visible,"Interrupted extraction restores source without entering reader")
 view._open_manual()
 view._advance_manual_release(2.0)
 check(view.manual_reader.visible,"Released manual enters reader only after clearance path completes")
 view.manual_reader.finish_close()
 check(view.manual_release_direction == -1,"Reader return restores free source then reverses release")
 view._advance_manual_release(2.0)
 check(view.manual_release == null,"Return restores exact original booklet meshes")
 scene.reduced_motion = true
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
