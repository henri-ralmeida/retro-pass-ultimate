extends SceneTree
## Real host _input plus GUI propagation for the enabled library route.
## Synthetic input only: no physical controller, native focus or GPU claim.
const Profile = preload("res://cosmic/input_profile.gd")
const FIXTURE := "res://evidence/cosmic/library_propagation_fixture.cfg"
var assertions := 0
var failures: Array[String] = []
var scene: Node
var library: Control

func check(value: bool, message: String) -> void:
 assertions += 1
 if not value:
  failures.append(message)
  push_error(message)

func key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = pressed
 event.echo = echo
 return event

func pad(button: JoyButton, pressed: bool = true) -> InputEventJoypadButton:
 var event := InputEventJoypadButton.new()
 event.button_index = button
 event.device = 27
 event.pressed = pressed
 return event

func axis(axis_id: JoyAxis, value: float) -> InputEventJoypadMotion:
 var event := InputEventJoypadMotion.new()
 event.axis = axis_id
 event.axis_value = value
 event.device = 27
 return event

func mouse(position: Vector2, pressed: bool) -> InputEventMouseButton:
 var event := InputEventMouseButton.new()
 event.button_index = MOUSE_BUTTON_LEFT
 event.position = position
 event.global_position = position
 event.pressed = pressed
 return event

func send(event: InputEvent) -> void:
 root.push_input(event, true)
 await process_frame

func tap_key(code: Key) -> void:
 await send(key(code))
 await send(key(code, false))

func tap_pad(button: JoyButton) -> void:
 await send(pad(button))
 await send(pad(button, false))

func _initialize() -> void: run.call_deferred()

func run() -> void:
 DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
 scene = load("res://cosmic/main.tscn").instantiate()
 scene.input_profile = Profile.new()
 scene.input_profile.config_path = FIXTURE
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene.application_focused = true
 scene.reduced_motion = true
 scene.input_profile.rebind("confirm", KEY_C, false)
 scene.input_profile.rebind("back", KEY_V, false)
 scene.input_profile.rebind("inspect", KEY_Q, false)
 scene.input_profile.rebind("confirm", JOY_BUTTON_LEFT_SHOULDER, true)
 scene.input_profile.rebind("back", JOY_BUTTON_RIGHT_SHOULDER, true)
 scene._refresh_controls()
 var original_model: Node3D = scene.model
 scene.console_button.grab_focus()
 scene.cooldown = 0.0

 # The event opening the library must not also activate its newly focused button.
 await tap_key(KEY_C)
 library = scene.library_view
 check(scene.library_state == "library" and scene.selection_count == 1, "Remapped keyboard confirmation enters the real library route exactly once")
 check(not library.inspect_mode, "The opening key does not fall through to the newly focused library action")
 await send(key(KEY_C, true, true))
 check(not library.inspect_mode and scene.selection_count == 1, "Held opening confirmation cannot activate the new scene")
 await send(key(KEY_C, false))
 await tap_key(KEY_X)
 await tap_key(KEY_I)
 check(not library.inspect_mode, "Old unmapped keyboard confirm and inspect keys do nothing in the library")

 # Mapped actions and built-in alternatives activate once, not once per route.
 await tap_key(KEY_C)
 check(library.inspect_mode and scene.selection_count == 1, "Mapped confirmation approaches and opens the selected box exactly once")
 await send(key(KEY_C, true, true))
 check(library.inspect_mode, "Mapped confirmation echo cannot toggle inspection again")
 await send(key(KEY_C, false))
 await tap_key(KEY_ENTER)
 check(library.inspect_mode and library.presentation.state == &"presented", "Enter on focused Confirm is idempotent, not an inspection toggle")
 await send(key(KEY_ENTER, true, true))
 check(library.inspect_mode and library.presentation.state == &"presented", "Enter echo is consumed before native GUI activation")
 await send(key(KEY_ENTER, false))
 await tap_key(KEY_SPACE)
 check(library.inspect_mode, "Space remains a single-activation library alternative")

 # One held cancel exits a nested mode only, not both inspection and library.
 await send(key(KEY_ESCAPE))
 check(not library.inspect_mode and scene.library_state == "library", "Escape first exits only box inspection")
 await send(key(KEY_ESCAPE, true, true))
 check(scene.library_state == "library", "Held Escape cannot also exit the collection")
 await send(key(KEY_ESCAPE, false))
 await tap_key(KEY_Q)
 check(library.inspect_mode, "Remapped inspection key opens box inspection")
 await send(key(KEY_V))
 await send(key(KEY_V, true, true))
 check(not library.inspect_mode and scene.library_state == "library", "Held remapped back exits only the nested inspection mode")
 await send(key(KEY_V, false))

 # Shoulder mappings take priority over their default previous/next shortcuts.
 library.inspect_button.grab_focus()
 var selected_index: int = library.current_index
 await tap_pad(JOY_BUTTON_A)
 check(not library.inspect_mode and scene.library_state == "library", "Old unmapped controller A cannot accept through native GUI fallback")
 await tap_pad(JOY_BUTTON_LEFT_SHOULDER)
 check(library.inspect_mode and library.current_index == selected_index, "Remapped controller confirmation wins over shoulder navigation")
 await tap_pad(JOY_BUTTON_B)
 check(library.inspect_mode and scene.library_state == "library", "Old unmapped controller back cannot close inspection")
 await tap_pad(JOY_BUTTON_RIGHT_SHOULDER)
 check(not library.inspect_mode and library.current_index == selected_index, "Remapped controller back wins over shoulder navigation")
 var axis_index: int = (int(library.current_index) + 1) % library.ITEMS.size()
 await send(axis(JOY_AXIS_LEFT_X, 0.8))
 check(library.current_index == axis_index, "Analog navigation changes the cover once beyond its threshold")
 await send(axis(JOY_AXIS_LEFT_X, 0.95))
 check(library.current_index == axis_index, "A held analog stick does not navigate again before returning to neutral")
 await send(axis(JOY_AXIS_LEFT_X, 0.0))
 await send(axis(JOY_AXIS_LEFT_X, -0.9))
 check(library.current_index == selected_index, "Analog navigation re-arms after a neutral sample")
 await send(axis(JOY_AXIS_LEFT_X, 0.0))

 # Tab and pointer events must still reach actual GUI controls.
 if library.ITEMS.size() > 1: library.next_button.grab_focus()
 else: library.motion_button.grab_focus()
 var expected_index: int = (int(library.current_index) + 1) % library.ITEMS.size()
 await tap_key(KEY_ENTER)
 check(library.current_index == expected_index, "Focused next button receives Enter exactly once")
 var before_tab: Control = root.gui_get_focus_owner()
 var expected_focus: Node = before_tab.get_node(before_tab.focus_next)
 await tap_key(KEY_TAB)
 check(root.gui_get_focus_owner() == expected_focus, "Tab propagates to the library's explicit focus ring")
 if library.ITEMS.size() > 1:
  var target_index: int = (int(library.current_index) + 1) % library.ITEMS.size()
  var target_position: Vector2 = library.cards[target_index].get_global_rect().get_center()
  await send(mouse(target_position, true))
  await send(mouse(target_position, false))
  check(library.current_index == target_index, "Pointer clicks still select real collection cards through GUI propagation")
 else:
  check(not library.cards[0].visible and library.scan_button.is_visible_in_tree(), "Single-entry collection avoids redundant cards and keeps real scan control")

 # This section isolates input propagation at reduced-motion endpoints. The
 # focused motion-button check above may have enabled animated presentation;
 # intermediate transition timing is covered in test_library_presentation.
 scene.reduced_motion = true
 # Focus loss cancels drag and cached analog motion; input cannot leak to GUI.
 await tap_key(KEY_Q)
 check(library.inspect_mode, "Inspection opens before lifecycle input checks")
 await send(axis(JOY_AXIS_LEFT_X, 0.9))
 await send(axis(JOY_AXIS_RIGHT_Y, -0.8))
 check(not library.rotate_axis.is_zero_approx() and not is_zero_approx(library.zoom_axis), "Synthetic controller axes reach active box inspection")
 scene._joy_connection_changed(27, false)
 check(library.rotate_axis.is_zero_approx() and is_zero_approx(library.zoom_axis), "Disconnecting the active controller clears cached library axes")
 library.dragging = true
 library.rotate_axis = Vector2(0.8, 0.4)
 library.zoom_axis = 0.7
 scene._focus_lost()
 check(not library.dragging and library.rotate_axis.is_zero_approx() and is_zero_approx(library.zoom_axis), "Focus loss clears box drag, rotation and zoom")
 library.inspect_button.grab_focus()
 await tap_key(KEY_SPACE)
 await tap_key(KEY_ESCAPE)
 check(library.inspect_mode and scene.library_state == "library", "Unfocused keys cannot activate library controls or cancel through GUI propagation")
 scene._focus_returned()
 await tap_key(KEY_ESCAPE)
 check(not library.inspect_mode and scene.library_state == "library", "Inspection remains usable after focus returns")
 var exit_position: Vector2 = library.back_button.get_global_rect().get_center()
 await send(mouse(exit_position, true))
 await send(mouse(exit_position, false))
 check(scene.library_state == "system" and scene.model == original_model, "Mouse Back returns to the original console instance")
 check(root.gui_get_focus_owner() == scene.console_button, "Returning from library restores console keyboard focus")
 check(scene.selection_count == 1, "No library control or pointer action accidentally confirms the hidden console")

 # Animated entry consumes competing actions and honors only deliberate cancel.
 scene.reduced_motion = false
 scene.cooldown = 0.0
 await tap_key(KEY_C)
 check(scene.library_state == "entering" and scene.selection_count == 2, "Mapped input starts animated entry through the real event route")
 await tap_key(KEY_Q)
 await tap_key(KEY_ENTER)
 await tap_pad(JOY_BUTTON_A)
 await tap_pad(JOY_BUTTON_B)
 check(scene.library_state == "entering" and scene.selection_count == 2 and not scene.inspect_mode, "Transition consumes competing actions and old unmapped cancel")
 await send(pad(JOY_BUTTON_RIGHT_SHOULDER, false))
 check(scene.library_state == "entering", "Releasing mapped back does not cancel the transition")
 await tap_pad(JOY_BUTTON_RIGHT_SHOULDER)
 check(scene.library_state == "system" and scene.model == original_model, "Remapped controller Back cancels animated entry")
 await create_timer(1.3).timeout
 check(scene.library_state == "system" and not library.visible, "Cancelled transition cannot reopen via a delayed callback")

 scene.cooldown = 0.0
 scene.console_button.grab_focus()
 await tap_key(KEY_ENTER)
 check(scene.library_state == "entering" and scene.selection_count == 3, "Built-in Enter still starts one new transition")
 await tap_key(KEY_ESCAPE)
 check(scene.library_state == "system" and scene.ui.visible and scene.viewport_container.visible, "Escape cancels the animated route and restores selector visibility")
 scene.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
 var result := {"assertions": assertions, "failures": failures, "passed": failures.is_empty(), "mode": "headless Viewport.push_input keyboard, synthetic gamepad, pointer and GUI propagation; no physical controller, OS focus or GPU validation"}
 FileAccess.open("res://evidence/cosmic/library_propagation_tests.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("LIBRARY_PROPAGATION_TESTS ", JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
