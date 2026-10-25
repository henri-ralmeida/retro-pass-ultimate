extends SceneTree
var failures: Array[String] = []
var assertions := 0
func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var scene = load("res://cosmic/main.tscn").instantiate()
 scene.library_enabled = false # Standalone selector fixture; route covered by test_library.gd.
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene.toggle_inspection()
 scene.rotate_inspection(Vector2(140,60))
 scene.zoom_inspection(0.2)
 var angle = scene.inspection_pivot.rotation
 var zoom = scene.inspection_zoom
 scene.inspection_dragging = true
 scene.dwell_elapsed = 7.9
 scene._focus_lost()
 check(not scene.inspection_dragging,"Focus loss cancels held drag")
 check(is_zero_approx(scene.dwell_elapsed),"Focus loss cancels dwell")
 check(scene.viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"Visible unfocused scene retains active 3D target")
 check(scene.model.visible and scene.viewport_container.visible,"Model and container stay visible")
 check(scene.inspection_pivot.rotation.is_equal_approx(angle),"Focus loss preserves orientation")
 check(is_equal_approx(scene.inspection_zoom,zoom),"Focus loss preserves zoom")
 var mouse = InputEventMouseMotion.new()
 mouse.relative=Vector2(60,40)
 scene._input(mouse)
 check(scene.inspection_pivot.rotation.is_equal_approx(angle),"Unfocused input cannot rotate")
 scene._focus_returned()
 check(scene.inspect_mode and not scene.inspection_dragging,"Return preserves mode without sticky drag")
 scene._input(mouse)
 check(scene.inspection_pivot.rotation.is_equal_approx(angle),"Pointer movement on return does not rotate without new press")
 scene.inspection_dragging=true
 scene.hovering=true
 scene._pointer_left_window()
 check(not scene.inspection_dragging and not scene.hovering,"Pointer exit cancels drag and hover")
 check(scene.viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"Pointer exit retains rendering")
 scene.close_inspection()
 scene.open_history()
 scene.history_transition.custom_step(0.12)
 var blend=scene.history_blend
 scene._focus_lost()
 check(is_equal_approx(scene.history_blend,blend),"History pose is preserved during focus loss")
 check(not scene.history_transition.is_running(),"History animation pauses while unfocused")
 scene._focus_returned()
 check(scene.history_transition.is_running(),"History animation resumes on return")
 scene.history_transition.custom_step(1.0)
 check(is_equal_approx(scene.history_blend,1.0),"Resumed history reaches correct final state")
 scene.toggle_motion()
 scene._focus_lost()
 scene._focus_returned()
 check(scene.reduced_motion,"Focus cycling preserves reduced-motion preference")
 scene.set_scene_active(false)
 scene._focus_lost()
 scene._focus_returned()
 check(scene.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Explicitly inactive scene remains disabled")
 scene.set_scene_active(true)
 check(scene.viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"Reactivated scene renders again")
 check(scene.selection_count==0,"No focus or inspection action selected a console")
 var result={"assertions":assertions,"failures":failures,"passed":failures.is_empty(),"mode":"headless state checks; does not reproduce OS-specific compositor behavior"}
 FileAccess.open("res://evidence/cosmic/focus_visibility_tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("FOCUS_VISIBILITY_TESTS ",JSON.stringify(result))
 scene.queue_free()
 await process_frame
 quit(0 if failures.is_empty() else 1)
