extends SceneTree
## Explicit-focus consent gate, synthetic keys/pad events; no physical gamepad.
const Dialog = preload("res://cosmic/media_confirmation_dialog.gd")
const Profile = preload("res://cosmic/input_profile.gd")
var confirmed_count := 0
var canceled_count := 0
var assertions := 0
var failures := 0
var dialog
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func key(code: int, pressed := true, echo := false) -> InputEventKey:
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = pressed
 event.echo = echo
 return event
func pad(code: int, pressed := true) -> InputEventJoypadButton:
 var event := InputEventJoypadButton.new()
 event.button_index = code
 event.pressed = pressed
 return event
func show_choice(cancel: bool) -> void:
 dialog.popup_centered(Vector2i(420,200))
 await process_frame
 if cancel: dialog.get_cancel_button().grab_focus()
 else: dialog.get_ok_button().grab_focus()
 check(dialog.get_cancel_button().has_focus() if cancel else dialog.get_ok_button().has_focus(), "Intended consent choice owns focus")
func _initialize() -> void: run.call_deferred()
func run() -> void:
 dialog = Dialog.new()
 dialog.profile = Profile.new()
 dialog.profile.rebind("confirm", KEY_C, false)
 dialog.profile.rebind("back", KEY_V, false)
 dialog.profile.rebind("confirm", JOY_BUTTON_Y, true)
 dialog.profile.rebind("back", JOY_BUTTON_X, true)
 root.add_child(dialog)
 dialog.confirmed.connect(func(): confirmed_count += 1)
 dialog.canceled.connect(func(): canceled_count += 1)
 for event in [key(KEY_C),pad(JOY_BUTTON_Y),key(KEY_ENTER),key(KEY_KP_ENTER),key(KEY_SPACE)]:
  await show_choice(true)
  var before := canceled_count
  dialog.push_input(event)
  await process_frame
  check(confirmed_count == 0 and canceled_count == before + 1 and not dialog.visible, "Focused Cancel never authorizes through remapped/Enter/Space input")
  dialog._input(event)
  check(confirmed_count == 0 and canceled_count == before + 1, "Repeated delivery after dismiss has no second action")
 for event in [key(KEY_V),pad(JOY_BUTTON_X)]:
  await show_choice(false)
  var before := canceled_count
  dialog.push_input(event)
  await process_frame
  check(confirmed_count == 0 and canceled_count == before + 1 and not dialog.visible, "Remapped back cancels even with OK focused")
 await show_choice(false)
 for event in [key(KEY_C,true,true),key(KEY_ENTER,true,true),key(KEY_SPACE,true,true),key(KEY_C,false),key(KEY_ENTER,false),pad(JOY_BUTTON_Y,false),pad(JOY_BUTTON_A),pad(JOY_BUTTON_B)]:
  dialog.push_input(event)
  await process_frame
  check(confirmed_count == 0 and dialog.visible, "Echo/release/unmapped face cannot authorize")
 dialog.get_ok_button().release_focus()
 dialog._input(key(KEY_C))
 check(confirmed_count == 0 and dialog.visible, "No focused choice means no implicit consent")
 dialog.hide()
 for event in [key(KEY_C),pad(JOY_BUTTON_Y),key(KEY_ENTER),key(KEY_SPACE)]:
  await show_choice(false)
  var before := confirmed_count
  dialog.push_input(event)
  await process_frame
  check(confirmed_count == before + 1 and not dialog.visible, "Focused OK authorizes exactly once")
  dialog._input(event)
  dialog.push_input(event)
  await process_frame
  check(confirmed_count == before + 1, "Duplicate direct/GUI event cannot authorize twice")
 for code in [KEY_ENTER,KEY_SPACE]:
  dialog.profile.rebind("back",code,false)
  await show_choice(false)
  var before_confirm := confirmed_count
  var before_cancel := canceled_count
  dialog.push_input(key(code))
  await process_frame
  check(confirmed_count == before_confirm and canceled_count == before_cancel + 1 and not dialog.visible, "Mapped Back takes precedence over native Enter/Space accept")
 dialog.profile.rebind("back",KEY_V,false)
 dialog.profile.rebind("reset",KEY_ENTER,false)
 await show_choice(false)
 var before_confirm := confirmed_count
 var before_cancel := canceled_count
 dialog.push_input(key(KEY_ENTER))
 await process_frame
 check(confirmed_count == before_confirm and canceled_count == before_cancel and dialog.visible, "Enter mapped to reset cannot authorize or cancel")
 dialog.hide()
 dialog.free()
 print("MEDIA_CONFIRMATION_CONSENT: %d assertions; %d failures" % [assertions,failures])
 quit(0 if failures == 0 else 1)
