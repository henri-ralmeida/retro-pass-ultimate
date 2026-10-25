extends ConfirmationDialog
## Remapped confirm activates only the focused choice, NEVER implicit consent.
var profile
var _opening_event: InputEvent
var _opening_held := false

func arm_opening_event(event: InputEvent) -> void:
 _opening_event = event
 _opening_held = event != null and event.is_pressed() and (event is InputEventKey or event is InputEventJoypadButton)

func _matches_opening(event: InputEvent) -> bool:
 if _opening_event is InputEventKey and event is InputEventKey:
  var old_code: int = _opening_event.physical_keycode if _opening_event.physical_keycode else _opening_event.keycode
  var code: int = event.physical_keycode if event.physical_keycode else event.keycode
  return old_code == code
 if _opening_event is InputEventJoypadButton and event is InputEventJoypadButton:
  return _opening_event.device == event.device and _opening_event.button_index == event.button_index
 return false

func _input(event: InputEvent) -> void:
 if not visible or profile == null: return
 if _opening_held and _matches_opening(event):
  if not event.is_pressed(): _opening_held = false
  get_viewport().set_input_as_handled()
  return
 var action: String = profile.action_for(event)
 if action.is_empty() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: action = "back"
 if event is InputEventKey and event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]:
  get_viewport().set_input_as_handled()
  if not event.pressed or event.echo: return
  if action.is_empty(): action = "confirm"
 if action == "back":
  canceled.emit()
  hide()
  get_viewport().set_input_as_handled()
 elif action == "confirm":
  if get_cancel_button().has_focus():
   canceled.emit()
   hide()
  elif get_ok_button().has_focus():
   confirmed.emit()
   hide()
  get_viewport().set_input_as_handled()
 elif event is InputEventJoypadButton and event.button_index not in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]:
  # A non-mapped face button must not fall through as Godot ui_accept.
  get_viewport().set_input_as_handled()
