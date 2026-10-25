extends SceneTree
const Library = preload("res://cosmic/atari_library_view.gd")
const Profile = preload("res://cosmic/input_profile.gd")
class InputHost extends Node:
 var input_profile = Profile.new()
var failures: Array[String] = []
var exits := 0
func _initialize() -> void: _run.call_deferred()
func _expect(ok: bool, message: String) -> void:
 if not ok: failures.append(message)
func _key(code: int, physical: bool = false) -> InputEventKey:
 var event := InputEventKey.new()
 event.pressed = true
 if physical: event.physical_keycode = code
 else: event.keycode = code
 return event
func _pad(code: int) -> InputEventJoypadButton:
 var event := InputEventJoypadButton.new()
 event.pressed = true
 event.button_index = code
 return event
func _run() -> void:
 var host := InputHost.new()
 root.add_child(host)
 var view := Library.new()
 root.add_child(view)
 view.configure(host)
 view.exit_requested.connect(func(): exits += 1)
 view.open()
 await process_frame
 # Pure input regression: enable two real controls even without private geometry.
 view.action_buttons.box.disabled = false
 view.action_buttons.cartridge.disabled = false
 view.back_button.grab_focus()
 var before: Vector3 = view.pivot.rotation
 _expect(view.handle_event(_key(KEY_RIGHT)), "Collection arrow consumed for navigation")
 _expect(root.gui_get_focus_owner() == view.action_buttons.box, "Collection arrow moves focus off Back")
 _expect(view.pivot.rotation == before, "Collection arrow never rotates model")
 view.handle_event(_pad(JOY_BUTTON_DPAD_RIGHT))
 _expect(root.gui_get_focus_owner() == view.action_buttons.cartridge, "D-pad advances focus")
 view.back_button.grab_focus()
 view.handle_event(_key(KEY_X, true))
 _expect(exits == 1, "Physical default confirm activates focused Back")
 view.handle_event(_key(KEY_Z, true))
 _expect(exits == 2, "Physical default Back is routed")
 view.handle_event(_pad(JOY_BUTTON_B))
 _expect(exits == 3, "Gamepad Back is routed")
 host.input_profile.rebind("back", KEY_Q, false)
 view.handle_event(_key(KEY_Q, true))
 _expect(exits == 4, "Remapped physical Back is routed")
 var echo := _key(KEY_X, true)
 echo.echo = true
 _expect(view.handle_event(echo), "Held binding consumed")
 _expect(exits == 4, "Held confirm does not repeat activation")
 view.state = "inspection"
 view.inspection_role = "manual"
 view.action_buttons.next.show()
 view.action_buttons.next.disabled = false
 view.back_button.grab_focus()
 view.handle_event(_pad(JOY_BUTTON_DPAD_LEFT))
 _expect(root.gui_get_focus_owner() == view.action_buttons.next, "D-pad can reach contextual page action in inspection")
 for index in 100: view.handle_event(_key(KEY_UP))
 _expect(is_equal_approx(view.pivot.rotation.x,-1.3), "Inspection rotation remains bounded")
 view.handle_event(_pad(JOY_BUTTON_RIGHT_STICK))
 _expect(view.pivot.rotation.is_zero_approx(), "Gamepad reset clears inspection rotation")
 view.handle_event(_pad(JOY_BUTTON_B))
 _expect(view.state == "collection" and exits == 4, "Inspection Back returns only to collection")
 view.close()
 _expect(not view.handle_event(_pad(JOY_BUTTON_B)), "Closed view ignores controller")
 view.free()
 host.free()
 for failure in failures: push_error(failure)
 print("ATARI LIBRARY INPUT FAILURES: ", failures.size())
 quit(0 if failures.is_empty() else 1)
