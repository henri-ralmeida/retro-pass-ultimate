extends SceneTree
## Deterministic behavior checks for the console-history inspection feature.
## Run: godot --headless --path . --script cosmic/test_history.gd
## This is not visual QA, RetroBat integration QA, or a physical-controller test.

var failures: Array[String] = []
var assertions := 0
var emitted: Array[String] = []

func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok:
  failures.append(message)
  push_error(message)

func _initialize() -> void:
 run.call_deferred()

func _has_property(instance: Object, property_name: String) -> bool:
 for property in instance.get_property_list():
  if property.name == property_name: return true
 return false

func _key(code: Key) -> InputEventKey:
 var event := InputEventKey.new()
 event.keycode = code
 event.pressed = true
 return event

func _gamepad_a() -> InputEventJoypadButton:
 var event := InputEventJoypadButton.new()
 event.button_index = JOY_BUTTON_A
 event.pressed = true
 return event

func _baseline(scene: Node) -> void:
 if scene.inspect_mode: scene.close_inspection()
 if scene.history_open: scene.close_history()
 scene.set_scene_active(true)
 scene._focus_returned()
 scene.cooldown = 0.0
 scene.transition_busy = false
 scene.hovering = false
 scene._input(_key(KEY_TAB))
 scene.inspect_button.grab_focus()
 scene.console_button.grab_focus()
 scene.reset_dwell()
 # An explicit fixture baseline, not an assertion about rearming behavior.
 scene.auto_history_armed = true

func _no_selection(scene: Node, before: int, message: String) -> void:
 check(scene.selection_count == before and emitted.size() == before, message)

func run() -> void:
 var packed = load("res://cosmic/main.tscn")
 if packed == null:
  check(false, "Main scene loads")
  _finish()
  return
 var scene = packed.instantiate()
 root.add_child(scene)
 await process_frame
 # Avoid frame time and window focus events influencing the simulated clock.
 scene.set_process(false)
 scene.system_selected.connect(func(id): emitted.append(id))
 var contract_ok := true
 for method in ["open_history", "close_history", "_advance_dwell", "reset_dwell", "toggle_inspection"]:
  var exists: bool = scene.has_method(method)
  check(exists, "History API provides " + method)
  contract_ok = contract_ok and exists
 for property_name in ["history_open", "history_blend", "dwell_elapsed", "dwell_seconds", "auto_history_armed", "dwell_uses_mouse"]:
  var exists := _has_property(scene, property_name)
  check(exists, "History state provides " + property_name)
  contract_ok = contract_ok and exists
 if not contract_ok:
  scene.queue_free()
  await process_frame
  _finish()
  return

 check(is_equal_approx(scene.dwell_seconds, 8.0), "Default dwell is eight seconds")
 check(not scene.history_open, "History starts closed")
 check(scene.inspect_button is Button, "Inspection is a real accessible button")
 check("inspecionar" in scene.inspect_button.accessibility_name.to_lower(), "Button explicitly says Inspecionar")
 check(scene.inspect_button.custom_minimum_size.y >= 48, "Inspection keeps a comfortable click target")

 # The console can reveal history, never select a system, merely by lingering.
 _baseline(scene)
 scene._advance_dwell(7.9)
 check(not scene.history_open, "7.9 seconds of console focus does not open history")
 check(is_equal_approx(scene.dwell_elapsed, 7.9), "Eligible focus accumulates dwell")
 scene._advance_dwell(0.1)
 check(scene.history_open, "Eight seconds of console focus opens history")
 check(not scene.systems[0].history_text.is_empty(), "The real console has authored history data")
 check(not scene.systems[0].history_credits.is_empty(), "The real console has history attribution")
 check(scene.systems[0].history_text in scene.history_body.text, "History panel uses the selected console's history")
 check(scene.systems[0].history_credits in scene.history_body.text, "History panel includes the source attribution")
 _no_selection(scene, 0, "Automatic history does not select a system")

 # Closing must not make the same unchanged hover/focus immediately reopen it.
 scene.close_history()
 check(not scene.history_open, "Close dismisses history")
 check(not scene.auto_history_armed, "Close disarms automatic history")
 check(is_zero_approx(scene.dwell_elapsed), "Close clears the countdown")
 scene._advance_dwell(30.0)
 check(not scene.history_open, "Unchanged console focus does not reopen after close")
 _no_selection(scene, 0, "Closing and remaining idle do not select")
 scene.inspect_button.grab_focus()
 scene.console_button.grab_focus()
 check(scene.auto_history_armed, "Leaving and deliberately returning focus rearms history")
 scene._advance_dwell(8.0)
 check(scene.history_open, "New console-focus episode can reveal history again")

 # Hover works without keyboard focus, including a new hover after dismissal.
 _baseline(scene)
 scene.console_button.release_focus()
 scene._input(InputEventMouseMotion.new())
 scene.console_button.mouse_entered.emit()
 scene._advance_dwell(7.9)
 check(not scene.history_open, "7.9 seconds of console hover does not open history")
 scene._advance_dwell(0.1)
 check(scene.history_open, "Eight seconds of console hover opens history")
 scene.close_history()
 scene._advance_dwell(20.0)
 check(not scene.history_open, "Unchanged console hover stays closed after dismissal")
 scene.console_button.mouse_exited.emit()
 scene.console_button.mouse_entered.emit()
 check(not scene.auto_history_armed, "Geometric hover reentry without mouse movement stays disarmed")
 scene._advance_dwell(20.0)
 check(not scene.history_open, "A sliding hitbox cannot reopen history beneath a stationary pointer")
 scene._input(InputEventMouseMotion.new())
 check(scene.auto_history_armed, "Real mouse movement while back over the console rearms history")
 scene._advance_dwell(8.0)
 check(scene.history_open, "New hover episode can reveal history again")
 _no_selection(scene, 0, "Hover-driven history never selects")

 # Footer controls and the empty background are not dwell targets.
 for control in [scene.inspect_button, scene.motion_button]:
  _baseline(scene)
  control.grab_focus()
  scene._advance_dwell(20.0)
  check(not scene.history_open, "%s focus is not an automatic-history target" % control.name)
  check(is_zero_approx(scene.dwell_elapsed), "%s focus does not accumulate dwell" % control.name)
 _baseline(scene)
 scene.console_button.release_focus()
 scene._advance_dwell(20.0)
 check(not scene.history_open and is_zero_approx(scene.dwell_elapsed), "No hover or focus means no automatic history")

 # Losing eligible focus or mouse hover resets rather than retains partial time.
 _baseline(scene)
 scene._advance_dwell(7.9)
 scene.inspect_button.grab_focus()
 scene._advance_dwell(0.1)
 check(is_zero_approx(scene.dwell_elapsed), "Moving focus to a control resets partial dwell")
 scene.console_button.grab_focus()
 scene._advance_dwell(0.1)
 check(not scene.history_open, "Returning focus cannot complete the previous countdown")
 _baseline(scene)
 scene.console_button.release_focus()
 scene._input(InputEventMouseMotion.new())
 scene.console_button.mouse_entered.emit()
 scene._advance_dwell(7.9)
 scene.console_button.mouse_exited.emit()
 scene._advance_dwell(0.1)
 check(is_zero_approx(scene.dwell_elapsed), "Leaving console hover resets partial dwell")
 scene.reset_dwell()
 check(is_zero_approx(scene.dwell_elapsed), "Explicit reset clears dwell")

 # Mouse intent supersedes stale keyboard focus after leaving the console.
 _baseline(scene)
 scene._input(InputEventMouseMotion.new())
 scene.console_button.mouse_entered.emit()
 scene._advance_dwell(7.9)
 scene.console_button.mouse_exited.emit()
 check(scene.console_button.has_focus(), "Mouse-exit fixture retains console keyboard focus")
 scene._advance_dwell(20.0)
 check(not scene.history_open and is_zero_approx(scene.dwell_elapsed), "Mouse leaving console blocks dwell despite stale console focus")
 scene._input(_key(KEY_TAB))
 scene.inspect_button.grab_focus()
 scene.console_button.grab_focus()
 scene._advance_dwell(7.9)
 check(not scene.history_open, "Returning to keyboard focus requires a new full dwell")
 scene._advance_dwell(0.1)
 check(scene.history_open, "Deliberate keyboard-focus return opens after a new eight seconds")

 # Paused/unfocused scenes cannot accumulate dwell or reveal history.
 _baseline(scene)
 scene._advance_dwell(7.9)
 scene.set_scene_active(false)
 check(is_zero_approx(scene.dwell_elapsed), "Scene deactivation resets partial dwell immediately")
 scene._advance_dwell(20.0)
 check(not scene.history_open and is_zero_approx(scene.dwell_elapsed), "Inactive scene pauses automatic history")
 check(scene.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Inactive scene stops viewport rendering")
 scene.open_history()
 check(not scene.history_open, "Manual history is blocked while scene is inactive")
 scene.set_scene_active(true)
 scene._advance_dwell(0.1)
 check(not scene.history_open, "Reactivating scene cannot complete stale dwell")
 _baseline(scene)
 scene._advance_dwell(7.9)
 scene._focus_lost()
 check(is_zero_approx(scene.dwell_elapsed), "Window focus loss resets partial dwell immediately")
 scene._advance_dwell(20.0)
 check(not scene.history_open and is_zero_approx(scene.dwell_elapsed), "Unfocused window pauses automatic history")
 scene.open_history()
 check(not scene.history_open, "Manual history is blocked while the application is unfocused")
 scene._focus_returned()
 scene._advance_dwell(0.1)
 check(not scene.history_open, "Returning to the window cannot complete stale dwell")
 _no_selection(scene, 0, "Pause and focus changes never select a system")

 # Explicit interaction aborts the partial countdown.
 _baseline(scene)
 scene._advance_dwell(7.9)
 scene._input(_key(KEY_M))
 check(is_zero_approx(scene.dwell_elapsed), "Motion-control interaction aborts partial dwell")
 check(not scene.history_open, "Motion-control interaction does not reveal history")
 scene._advance_dwell(0.1)
 check(not scene.history_open, "A fresh interval is needed after motion-control interaction")
 _baseline(scene)
 scene._advance_dwell(7.9)
 scene._input(_key(KEY_RIGHT))
 check(is_zero_approx(scene.dwell_elapsed), "Navigation interaction aborts partial dwell even with one system")
 scene._advance_dwell(0.1)
 check(not scene.history_open, "Navigation cannot complete stale dwell")
 _baseline(scene)
 scene._advance_dwell(7.9)
 scene._input(InputEventMouseMotion.new())
 check(is_zero_approx(scene.dwell_elapsed), "Mouse movement aborts partial dwell")
 scene._advance_dwell(0.1)
 check(not scene.history_open, "Mouse movement cannot complete stale dwell")
 _baseline(scene)
 scene.transition_busy = true
 scene._advance_dwell(20.0)
 check(not scene.history_open and is_zero_approx(scene.dwell_elapsed), "Navigation transition blocks automatic history")
 scene.open_history()
 check(not scene.history_open, "Navigation transition blocks manual history")
 scene.transition_busy = false

 # Inspection controls are intentionally separate from automatic history.
 _baseline(scene)
 scene.auto_history_armed = false
 scene.inspect_button.grab_focus()
 scene.inspect_button.pressed.emit()
 check(scene.inspect_mode and not scene.history_open, "Inspecionar button opens 3D inspection, not history")
 _no_selection(scene, 0, "Inspecionar button does not select")
 scene.inspect_button.pressed.emit()
 check(not scene.inspect_mode and not scene.history_open, "Inspection button closes 3D inspection without opening history")
 scene._input(_key(KEY_I))
 check(scene.inspect_mode and not scene.history_open, "I shortcut opens 3D inspection, not history")
 scene._input(_key(KEY_I))
 check(not scene.inspect_mode and not scene.history_open, "I shortcut closes 3D inspection without opening history")
 check("inspecionar" in scene.inspect_button.accessibility_name.to_lower(), "Closing restores the Inspecionar label")

 # Reduced motion jumps to the final state without transitional sliding.
 _baseline(scene)
 if not scene.reduced_motion: scene.toggle_motion()
 scene.open_history()
 check(scene.history_open and is_equal_approx(scene.history_blend, 1.0), "Reduced-motion opening applies final history blend immediately")
 scene.close_history()
 check(not scene.history_open and is_zero_approx(scene.history_blend), "Reduced-motion closing applies final default blend immediately")
 _no_selection(scene, 0, "Reduced-motion inspection never selects")

 # Interrupting an animated opening leaves a stable closed or paused state.
 _baseline(scene)
 if scene.reduced_motion: scene.toggle_motion()
 scene.open_history()
 scene.history_transition.custom_step(0.2)
 check(scene.history_blend > 0.0 and scene.history_blend < 1.0, "Animated opening has an intermediate blend")
 scene.close_history()
 scene.history_transition.custom_step(1.0)
 check(not scene.history_open and is_zero_approx(scene.history_blend), "Closing during opening reaches the default blend")
 check(not scene.history_panel.visible, "Closing during opening hides the history panel")
 _baseline(scene)
 scene.open_history()
 scene.history_transition.custom_step(0.1)
 var interrupted_blend = scene.history_blend
 scene._focus_lost()
 check(is_equal_approx(scene.history_blend, interrupted_blend), "Focus loss preserves interrupted history animation")
 check(not scene.history_transition.is_running(), "Focus loss stops the history tween")
 _baseline(scene)
 scene.open_history()
 scene.history_transition.custom_step(0.1)
 scene.set_scene_active(false)
 check(is_equal_approx(scene.history_blend, 1.0), "Scene deactivation settles interrupted history animation")
 check(not scene.history_transition.is_running(), "Inactive scene stops the history tween")
 _baseline(scene)
 scene.open_history()
 scene.history_transition.custom_step(0.1)
 scene.toggle_motion()
 check(scene.reduced_motion and is_equal_approx(scene.history_blend, 1.0), "Enabling reduced motion during opening settles immediately")

 # History is only informational, including when selection APIs receive input.
 _baseline(scene)
 scene.open_history()
 scene.console_button.grab_focus()
 scene._input(_key(KEY_ENTER))
 scene.console_button.pressed.emit()
 scene.confirm_selection("history_guard_test")
 _no_selection(scene, 0, "Open history blocks keyboard, click, and API selection")
 scene._input(_key(KEY_ESCAPE))
 check(not scene.history_open, "Escape dismisses history")
 scene._advance_dwell(20.0)
 check(not scene.history_open, "Escape dismissal does not immediately reopen history")

 # Accept only deliberate selection of the console; footer A/Enter are not it.
 _baseline(scene)
 scene.inspect_button.grab_focus()
 scene._input(_gamepad_a())
 check(scene.inspect_mode and not scene.history_open, "Gamepad A on Inspecionar opens 3D inspection, not history")
 _no_selection(scene, 0, "Gamepad A respects the inspection button focus")
 scene.motion_button.grab_focus()
 scene._input(_gamepad_a())
 _no_selection(scene, 0, "Gamepad A respects the movement button focus")
 scene._input(_key(KEY_ENTER))
 _no_selection(scene, 0, "Enter away from the console does not select")
 _baseline(scene)
 scene.console_button.release_focus()
 scene._input(_gamepad_a())
 _no_selection(scene, 0, "Gamepad A with no focused console does not select")
 _baseline(scene)
 var before_selection: int = scene.selection_count
 scene._input(_key(KEY_ENTER))
 check(scene.selection_count == before_selection + 1 and emitted.size() == before_selection + 1 and emitted.back() == "sega_master_system", "Deliberate Enter on the console selects exactly once")
 scene.cooldown = 0.0
 scene.console_button.pressed.emit()
 check(scene.selection_count == before_selection + 2 and emitted.size() == before_selection + 2, "Deliberate central button activation selects exactly once")
 scene.cooldown = 0.0
 scene._input(_gamepad_a())
 check(scene.selection_count == before_selection + 3 and emitted.size() == before_selection + 3, "Deliberate gamepad A on the console selects exactly once")

 # Use actual viewport mouse dispatch, not only emitted hover signals, for the
 # footer exclusion. A stale console keyboard focus must not override it.
 if not scene.reduced_motion: scene.toggle_motion()
 var before_controls: int = scene.selection_count
 for control in [scene.inspect_button, scene.motion_button]:
  _baseline(scene)
  var motion := InputEventMouseMotion.new()
  motion.position = control.get_global_rect().get_center()
  motion.global_position = motion.position
  root.push_input(motion, true)
  await process_frame
  check(control.is_hovered(), "%s receives real viewport hover" % control.name)
  scene._advance_dwell(20.0)
  check(not scene.history_open and is_zero_approx(scene.dwell_elapsed), "%s hover never opens automatic history" % control.name)
  _no_selection(scene, before_controls, "%s hover never selects" % control.name)
 var outside_motion := InputEventMouseMotion.new()
 outside_motion.position = Vector2(-100, -100)
 outside_motion.global_position = outside_motion.position
 root.push_input(outside_motion, true)
 await process_frame
 scene._advance_dwell(20.0)
 check(not scene.history_open, "Pointer outside all controls does not open despite retained console focus")

 scene.queue_free()
 await process_frame
 _finish()

func _finish() -> void:
 var result := {
  "assertions": assertions,
  "failures": failures,
  "passed": failures.is_empty(),
  "engine": Engine.get_version_info().string,
  "mode": "headless deterministic history behavior; NOT visual, RetroBat integration, or physical-controller QA"
 }
 DirAccess.make_dir_recursive_absolute("res://evidence/cosmic")
 var file = FileAccess.open("res://evidence/cosmic/history_tests.json", FileAccess.WRITE)
 if file:
  file.store_string(JSON.stringify(result, "  "))
 else:
  push_error("Could not write history_tests.json: " + error_string(FileAccess.get_open_error()))
 print("COSMIC_HISTORY_TESTS ", JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
