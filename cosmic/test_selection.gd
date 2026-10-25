extends SceneTree
var failures: Array[String] = []
var assertions := 0
var emitted: Array[String] = []
func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok: failures.append(message); push_error(message)
func _initialize() -> void:
 run.call_deferred()
func run() -> void:
 var scene = load("res://cosmic/main.tscn").instantiate()
 scene.library_enabled = false # Standalone selector fixture; route covered by test_library.gd.
 root.add_child(scene)
 await process_frame
 scene.system_selected.connect(func(id): emitted.append(id))
 check(scene.systems.size()==1,"Exactly one real system")
 check(scene.systems[0].system_id=="sega_master_system","Stable ID")
 check(scene.model!=null,"Model instantiated")
 check(scene.camera!=null,"Camera exists")
 check(scene.system_logo.texture!=null and scene.system_logo.visible,"Authentic sourced logo is displayed")
 check(scene.title.text=="Master System","Console name retained internally")
 check(not scene.title.visible,"No duplicate visible console name")
 check(scene.inspect_button is Button and scene.motion_button is Button,"Chosen contextual controls are real buttons")
 check(scene.inspect_button.custom_minimum_size.y>=48,"Comfortable mouse target")
 check(scene.ui.get_node_or_null("FooterHint")==null,"No duplicate legacy shortcut row")
 check(scene.get_node_or_null("InteractionRoom")==null,"No room dependency")
 scene.hovering=true
 for i in range(3): await process_frame
 check(emitted.is_empty(),"Hover never confirms")
 scene.cooldown=0
 scene.confirm_selection("test_click")
 scene.confirm_selection("test_double_click")
 check(emitted.size()==1,"Double clicks deduplicated")
 check(emitted[0]=="sega_master_system","Correct selection payload")
 scene.cooldown=0
 var echo = InputEventKey.new()
 echo.keycode=KEY_ENTER; echo.pressed=true; echo.echo=true
 scene._input(echo)
 check(emitted.size()==1,"Key echo rejected")
 scene.console_button.grab_focus()
 var enter = InputEventKey.new()
 enter.keycode=KEY_ENTER; enter.pressed=true
 scene._input(enter)
 check(emitted.size()==2,"Keyboard confirms exactly once")
 scene.navigate(1);scene.navigate(-1)
 check(scene.current_index==0 and not scene.transition_busy,"Single system navigation is inert")
 scene.toggle_motion()
 check(scene.reduced_motion,"Reduced motion enabled")
 var before=scene.elapsed
 scene._process(1.0)
 check(is_equal_approx(before,scene.elapsed),"Reduced motion stops animation time")
 check(scene.presentation.position==Vector3.ZERO,"Reduced motion resets floating")
 scene.set_scene_active(false)
 scene.cooldown=0;scene.confirm_selection("inactive")
 scene._process(1.0)
 check(emitted.size()==2,"Inactive scene cannot confirm")
 check(scene.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Inactive viewport stops rendering")
 scene.set_scene_active(true)
 scene._focus_lost()
 scene.confirm_selection("focus_lost")
 check(emitted.size()==2,"Lost focus blocks selection")
 scene._focus_returned()
 scene.confirm_selection("focus_returned")
 check(emitted.size()==2,"Return focus guard rejects carried input")
 scene.cooldown=0
 scene.confirm_selection("new_deliberate_action")
 check(emitted.size()==3,"New deliberate action accepted after guard")
 scene.toggle_inspection()
 check(scene.inspect_mode and not scene.history_open,"Inspection toggle opens separate 3D mode")
 scene.toggle_inspection()
 check(not scene.inspect_mode and not scene.history_open,"Inspection restores framing without opening history")
 # Fixture only, not shipped catalog data or a second displayed console.
 var fixture=scene.systems[0].duplicate()
 fixture.system_id="test_fixture_only"
 scene.systems.append(fixture)
 scene.navigate(1)
 check(scene.current_index==1,"Data-driven next system")
 scene.navigate(1)
 check(scene.current_index==0,"Circular wrap")
 scene.navigate(-1)
 check(scene.current_index==1,"Circular reverse wrap")
 scene.toggle_motion()
 check(not scene.reduced_motion,"Animated navigation mode restored")
 scene.navigate(1)
 var locked_index=scene.current_index
 scene.navigate(1)
 check(scene.transition_busy and scene.current_index==locked_index,"Repeated navigation locked during animated transition")
 scene._focus_lost()
 check(not scene.transition_busy,"Lost focus cancels transition lock")
 scene._focus_returned()
 scene.navigate(1)
 await create_timer(0.3).timeout
 check(not scene.transition_busy,"Animated transition releases lock")
 scene.inspect_button.grab_focus()
 var a = InputEventJoypadButton.new()
 a.button_index=JOY_BUTTON_A; a.pressed=true
 scene.cooldown=0
 var previous_count=emitted.size()
 scene._input(a)
 check(scene.inspect_mode and not scene.history_open and emitted.size()==previous_count,"Mapped gamepad A opens 3D inspection without selecting or opening history")
 scene.motion_button.grab_focus()
 scene._input(a)
 check(scene.reduced_motion and emitted.size()==previous_count,"Mapped gamepad A respects motion focus")
 scene.systems.pop_back();scene.current_index=0
 scene.queue_free()
 await process_frame
 var result={"assertions":assertions,"failures":failures,"passed":failures.is_empty(),"engine":Engine.get_version_info().string,"mode":"headless behavioral checks; NOT visual or physical controller QA"}
 var f=FileAccess.open("res://evidence/cosmic/headless_tests.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(result,"  "))
 print("COSMIC_TESTS ",JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
