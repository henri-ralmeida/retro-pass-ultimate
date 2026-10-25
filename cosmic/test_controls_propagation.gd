extends SceneTree
## Exercise _input plus Godot GUI propagation, not only direct handler calls.
const Profile = preload("res://cosmic/input_profile.gd")
const FIXTURE := "res://evidence/cosmic/controls_propagation_fixture.cfg"
var assertions := 0
var failures: Array[String] = []
var scene: Node

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

func send(event: InputEvent) -> void:
 root.push_input(event, true)
 await process_frame

func _initialize() -> void: run.call_deferred()

func run() -> void:
 DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
 scene = load("res://cosmic/main.tscn").instantiate()
 scene.library_enabled = false # Standalone selector fixture; route covered by test_library.gd.
 scene.input_profile = Profile.new()
 scene.input_profile.config_path = FIXTURE
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene.application_focused = true

 # The actual GUI must not receive fallthrough acceptance while unfocused.
 scene.motion_button.grab_focus()
 var previous_motion: bool = scene.reduced_motion
 scene._focus_lost()
 await send(key(KEY_SPACE))
 await send(key(KEY_SPACE, false))
 check(scene.reduced_motion == previous_motion, "Unfocused Space cannot activate the focused motion button through GUI propagation")
 scene._focus_returned()
 scene.set_scene_active(false)
 await send(key(KEY_ENTER))
 await send(key(KEY_ENTER, false))
 check(scene.reduced_motion == previous_motion, "Inactive Enter cannot activate the focused motion button through GUI propagation")
 scene.set_scene_active(true)
 await send(key(KEY_SPACE))
 await send(key(KEY_SPACE, false))
 check(scene.reduced_motion != previous_motion, "Focused active GUI activation remains functional after restoration")

 # One held cancel must only cancel capture, never close its containing dialog.
 scene.toggle_control_settings()
 await process_frame
 await process_frame
 var panel_bounds: Rect2 = scene.settings_panel.get_global_rect()
 var viewport_bounds := root.get_visible_rect()
 check(panel_bounds.position.x >= viewport_bounds.position.x and panel_bounds.position.y >= viewport_bounds.position.y and panel_bounds.end.x <= viewport_bounds.end.x and panel_bounds.end.y <= viewport_bounds.end.y, "First settings opening fits the viewport after layout settles")
 scene._begin_rebind("confirm")
 await send(key(KEY_ESCAPE))
 check(scene.capture_action.is_empty() and scene.settings_panel.visible, "Escape cancels capture but keeps settings open")
 await send(key(KEY_ESCAPE, true, true))
 check(scene.settings_panel.visible, "Held Escape does not close settings after canceling capture")
 await send(key(KEY_ESCAPE, false))
 scene._begin_rebind("inspect")
 await send(key(KEY_F1))
 check(scene.capture_action.is_empty() and scene.settings_panel.visible, "F1 cancels capture but keeps settings open")
 await send(key(KEY_F1, true, true))
 check(scene.settings_panel.visible, "Held F1 does not close settings after canceling capture")
 await send(key(KEY_F1, false))

 # Real event routing captures and persists remaps without activating the scene.
 scene._begin_rebind("confirm")
 await send(key(KEY_C))
 await send(key(KEY_C, false))
 check(scene.input_profile.keys.confirm == KEY_C and scene.capture_action.is_empty(), "GUI-routed keyboard capture stores the new binding")
 check(scene.selection_count == 0, "Capturing confirmation does not select the underlying console")
 scene._begin_rebind("confirm")
 await send(pad(JOY_BUTTON_LEFT_SHOULDER))
 await send(pad(JOY_BUTTON_LEFT_SHOULDER, false))
 check(scene.input_profile.buttons.confirm == JOY_BUTTON_LEFT_SHOULDER, "GUI-routed gamepad capture stores the new binding")
 var restored := Profile.new()
 restored.config_path = FIXTURE
 restored.load_settings()
 check(restored.keys.confirm == KEY_C and restored.buttons.confirm == JOY_BUTTON_LEFT_SHOULDER, "Both keyboard and controller remaps survive reload")
 scene.toggle_control_settings()
 scene.console_button.grab_focus()
 scene.cooldown = 0.0
 await send(key(KEY_X))
 await send(key(KEY_X, false))
 await send(pad(JOY_BUTTON_A))
 await send(pad(JOY_BUTTON_A, false))
 check(scene.selection_count == 0, "Old unmapped confirmation keys do not select through native GUI fallthrough")
 await send(key(KEY_C))
 await send(key(KEY_C, false))
 check(scene.selection_count == 1, "Remapped keyboard confirmation selects exactly once")
 scene.cooldown = 0.0
 await send(key(KEY_C, true, true))
 check(scene.selection_count == 1, "Held remapped confirmation does not select again")
 await send(key(KEY_C, false))
 await send(pad(JOY_BUTTON_LEFT_SHOULDER))
 await send(pad(JOY_BUTTON_LEFT_SHOULDER, false))
 check(scene.selection_count == 2, "Remapped controller confirmation selects exactly once")

 # PopupMenu owns a separate window route; exercise its connected signal explicitly.
 # This checks the custom handler, not OS event delivery or native popup navigation.
 scene.toggle_control_settings()
 scene.input_profile.rebind("back", JOY_BUTTON_RIGHT_SHOULDER, true)
 var popup: PopupMenu = scene.family_selector.get_popup()
 scene.family_selector.show_popup()
 await process_frame
 popup.set_focused_item(2)
 popup.window_input.emit(pad(JOY_BUTTON_A))
 check(popup.visible and scene.input_profile.family_override == "auto", "Popup ignores the old unmapped controller confirmation")
 popup.window_input.emit(pad(JOY_BUTTON_LEFT_SHOULDER, false))
 check(popup.visible, "Controller release does not accept the family popup")
 scene._set_input_device("keyboard")
 popup.window_input.emit(pad(JOY_BUTTON_LEFT_SHOULDER))
 await process_frame
 check(not popup.visible and scene.family_selector.selected == 2 and scene.input_profile.family_override == "playstation", "Remapped controller confirmation accepts the focused family through the popup signal")
 check(scene.input_device == "gamepad" and scene.active_pad == 27, "Popup controller input updates active-device prompts")
 restored = Profile.new()
 restored.config_path = FIXTURE
 restored.load_settings()
 check(restored.family_override == "playstation" and restored.buttons.confirm == JOY_BUTTON_LEFT_SHOULDER and restored.buttons.back == JOY_BUTTON_RIGHT_SHOULDER, "Popup family selection persists alongside remapped controller bindings")
 scene.family_selector.show_popup()
 await process_frame
 popup.set_focused_item(1)
 popup.window_input.emit(pad(JOY_BUTTON_B))
 check(popup.visible, "Popup ignores the old unmapped controller back button")
 popup.window_input.emit(pad(JOY_BUTTON_RIGHT_SHOULDER))
 await process_frame
 check(not popup.visible and scene.family_selector.selected == 2 and scene.input_profile.family_override == "playstation" and scene.settings_panel.visible, "Remapped back cancels only the family popup without changing its selection")
 scene.family_selector.show_popup()
 await process_frame
 popup.set_focused_item(1)
 scene.scene_active = false
 popup.window_input.emit(pad(JOY_BUTTON_LEFT_SHOULDER))
 check(popup.visible and scene.input_profile.family_override == "playstation", "Inactive custom popup confirmation is blocked")
 scene.scene_active = true
 popup.hide()

 # Restoring defaults must work through the same focused-control activation path.
 scene.input_profile.family_override = "playstation"
 scene.family_selector.select(2)
 var restore_button: Button
 for candidate in scene.settings_panel.find_children("*", "Button", true, false):
  if candidate.text == "Restaurar controles padrão": restore_button = candidate
 check(restore_button != null, "Settings expose a restore-defaults button")
 if restore_button:
  restore_button.grab_focus()
  await send(key(KEY_C))
  await send(key(KEY_C, false))
 check(scene.input_profile.keys == Profile.KEYS and scene.input_profile.buttons == Profile.BUTTONS, "Restore-defaults activation restores all keyboard and controller bindings")
 check(scene.input_profile.family_override == "auto" and scene.family_selector.selected == 0, "Restore defaults resets the family override and selector")
 check(scene.capture_action.is_empty() and scene.settings_panel.visible and scene.selection_count == 2, "Restoring controls leaves the dialog open without selecting behind it")
 restored = Profile.new()
 restored.config_path = FIXTURE
 restored.load_settings()
 check(restored.keys == Profile.KEYS and restored.buttons == Profile.BUTTONS and restored.family_override == "auto", "Restored defaults survive reload")

 scene.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE))
 var result := {"assertions": assertions, "failures": failures, "passed": failures.is_empty(), "mode": "headless Viewport.push_input GUI propagation and explicit popup window_input signals; no physical controller, OS focus or native popup navigation validation"}
 FileAccess.open("res://evidence/cosmic/controls_propagation_tests.json", FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
 print("CONTROLS_PROPAGATION_TESTS ", JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
