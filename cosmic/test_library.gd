extends SceneTree
## Integration route coverage, unlike standalone selector fixtures.
var failures: Array[String] = []
var assertions := 0
func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func key(code: Key) -> InputEventKey:
 var e := InputEventKey.new()
 e.keycode=code; e.physical_keycode=code; e.pressed=true
 return e
func run() -> void:
 var scene = load("res://cosmic/main.tscn").instantiate()
 scene.input_profile.config_path="res://evidence/cosmic/library_fixture.cfg"
 root.add_child(scene)
 await process_frame
 check(scene.library_enabled and scene.library_state=="system","Real route enabled by default")
 scene.open_history(true)
 await create_timer(0.55).timeout
 scene._focus_lost()
 await create_timer(0.10).timeout
 scene._focus_returned()
 scene.close_history()
 await create_timer(0.55).timeout
 scene.confirm_selection("after_history")
 check(scene.library_state=="entering","History close and focus return allow deliberate entry")
 scene.go_back()
 var original_model=scene.model
 var original_camera=scene.camera.position
 scene.cooldown=0
 scene.confirm_selection("integration")
 check(scene.library_state=="entering" and scene.selection_count==2,"Selection begins cinematic once")
 scene.confirm_selection("duplicate")
 check(scene.selection_count==2,"Repeated entry rejected")
 scene.open_history(true); scene.toggle_inspection()
 check(not scene.history_open and not scene.inspect_mode,"Transition excludes competing modes")
 await create_timer(0.25).timeout
 var progress=scene.entry_progress
 check(progress>0 and progress<1,"Camera transition progresses")
 scene._focus_lost()
 await create_timer(0.15).timeout
 check(is_equal_approx(scene.entry_progress,progress),"Focus loss pauses entry without disappearing")
 scene._focus_returned()
 scene.go_back()
 check(scene.library_state=="system" and scene.ui.visible and scene.viewport_container.visible,"Back cancels transition")
 check(scene.camera.position.is_equal_approx(original_camera),"Cancel restores camera exactly")
 await create_timer(1.3).timeout
 check(scene.library_state=="system","Cancelled callback cannot reopen library")
 scene.reduced_motion=true
 for i in range(8):
  scene.cooldown=0;scene.confirm_selection("repeat")
  check(scene.library_state=="library" and scene.library_view.visible,"Reduced motion entry immediate")
  check(not scene.viewport_container.visible and not scene.ui.visible,"Console hidden while library active")
  scene._advance_dwell(100)
  check(not scene.history_open,"No history while browsing boxes")
  scene._focus_lost();scene._focus_returned()
  check(scene.library_state=="library" and scene.library_view.visible,"Library preserved over focus loss")
  scene.go_back()
  check(scene.library_state=="system" and scene.model==original_model,"Return preserves approved console instance")
  check(not scene.auto_history_armed,"No immediate history after return")
 scene.reduced_motion=false
 scene.cooldown=0;scene.confirm_selection("complete")
 await create_timer(1.65).timeout
 check(scene.library_state=="library" and scene.library_view.visible,"Animated entry completes")
 check(not scene.entry_veil.visible,"Transition veil removed")
 scene.set_scene_active(false)
 check(scene.library_state=="system","Deactivation safely closes route")
 scene.set_scene_active(true)
 check(scene.viewport_container.visible and scene.model==original_model,"Reactivation has original console")
 scene.queue_free();await process_frame
 var result={"passed":failures.is_empty(),"assertions":assertions,"failures":failures,"mode":"headless integration; not GPU or physical controller QA"}
 FileAccess.open("res://evidence/cosmic/library_tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("COSMIC_LIBRARY_TESTS ",JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
