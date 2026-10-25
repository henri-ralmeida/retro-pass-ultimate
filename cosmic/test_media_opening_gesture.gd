extends SceneTree
## Opening-gesture consent regression. Synthetic Window input, not physical pad.
## Metadata refers to an absent synthetic file. A sentinel blocks ALL worker starts,
## including a faulty consent path, so this test never reads any media bytes.
const Host = preload("res://cosmic/media_optin_host.gd")
const Profile = preload("res://cosmic/input_profile.gd")
class MainProbe:
 extends "res://cosmic/main.gd"
 var observed := 0
 func _ready() -> void: pass
 func _observe_input_device(_event: InputEvent) -> void: observed += 1
var assertions := 0
var failures := 0
var start_attempts := 0
var confirmed_count := 0
var cancelled_count := 0
var token := ""
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
func _initialize() -> void: run.call_deferred()
func run_case(label: String, opening: InputEvent, release: InputEvent, echo: InputEvent = null, lose_focus := false) -> void:
 start_attempts = 0
 confirmed_count = 0
 cancelled_count = 0
 var probe := MainProbe.new()
 root.add_child(probe)
 probe.set_process(false)
 var host := Host.new()
 host.profile = Profile.new()
 host.profile.rebind("confirm",KEY_C,false)
 host.profile.rebind("back",KEY_V,false)
 host.profile.rebind("confirm",JOY_BUTTON_Y,true)
 host.profile.rebind("back",JOY_BUTTON_X,true)
 host.store.path = "user://opening_gesture_%s_%s_settings.json" % [token,label]
 host.catalog_getter = func(): return [{"id":"synthetic-exact-edition", "system":"master_system", "media_metadata":{"cover_front":{"relative_path":"never-created.png","status":"present"}}}]
 root.add_child(host)
 host.set_process(false)
 host.panel.journal_path = "user://opening_gesture_%s_%s_queue.json" % [token,label]
 host.panel.before_start = func(_plan: Dictionary) -> Error:
  start_attempts += 1
  return ERR_UNAUTHORIZED
 var dialog = host.panel.confirm_dialog
 dialog.confirmed.connect(func(): confirmed_count += 1)
 dialog.canceled.connect(func(): cancelled_count += 1)
 probe.media_host = host
 host.open_panel()
 host.panel.system_picker.select(0)
 host.panel.root_input.text = ProjectSettings.globalize_path("user://absent_opening_fixture_" + token)
 host.panel.categories.covers.button_pressed = true
 await process_frame
 host.panel.start_button.grab_focus()
 # Full root Window pipeline: main._input -> host.route_input OR native button GUI.
 root.push_input(opening)
 await process_frame
 var opened_on_press: bool = dialog.visible
 var opening_delivery: InputEvent = opening
 if not opened_on_press:
  # Native Button action-on-release is also a single opening gesture.
  root.push_input(release)
  opening_delivery = release
  await process_frame
 check(dialog.visible, label + ": review opens through real main/GUI pipeline")
 check(start_attempts == 0 and confirmed_count == 0, label + ": opening itself never grants consent")
 check(probe.observed == 0, label + ": input never reaches background observation")
 if dialog.visible:
  # Focus intentionally on OK: safety must not depend on absent/delayed focus.
  dialog.get_ok_button().grab_focus()
  dialog.push_input(opening_delivery)
  await process_frame
  check(start_attempts == 0 and confirmed_count == 0 and dialog.visible, label + ": same opening event cannot confirm its own dialog")
  if echo != null:
   dialog.push_input(echo)
   await process_frame
   check(start_attempts == 0 and confirmed_count == 0, label + ": opening hold echo cannot confirm")
  if lose_focus:
   # Synthetic focus notifications; the OS-side release is deliberately NOT
   # delivered to this Window, modeling a key/button released in another app.
   dialog.focus_exited.emit()
   await process_frame
   dialog.focus_entered.emit()
   await process_frame
   dialog.get_ok_button().grab_focus()
   dialog.push_input(opening)
   await process_frame
   check(dialog.visible and start_attempts == 0 and confirmed_count == 0, label + ": missed outside release/focus return cannot authorize")
   # Escape or remapped Back must remain an escape hatch despite a held gate.
   dialog.push_input(key(KEY_ESCAPE) if opening is InputEventJoypadButton else key(KEY_V))
   await process_frame
   check(not dialog.visible and cancelled_count == 1 and confirmed_count == 0, label + ": Back/Escape closes after missed release")
   # A new review gets a NEW gesture gate, not a permanent lock from last time.
   host.panel.start_button.grab_focus()
   root.push_input(opening.duplicate())
   await process_frame
   check(dialog.visible and confirmed_count == 0, label + ": next review opens without inherited authorization")
   dialog.get_ok_button().grab_focus()
   dialog.push_input(release)
   await process_frame
   check(dialog.visible and confirmed_count == 0, label + ": fresh review release only arms consent")
   dialog.push_input(opening.duplicate())
   await process_frame
   check(confirmed_count == 1 and start_attempts == 1, label + ": independent next gesture works after focus interruption")
   check(host.panel.service.poll().status == "idle", label + ": sentinel still blocks all media bytes")
   probe.media_host = null
   probe.free()
   host.free()
   return
  dialog.push_input(release)
  await process_frame
  check(start_attempts == 0 and confirmed_count == 0 and dialog.visible, label + ": opening release cannot confirm")
  if dialog.visible:
   # After opening/hold/release, selecting Cancel remains usable and exclusive.
   dialog.get_cancel_button().grab_focus()
   dialog.push_input(pad(JOY_BUTTON_Y) if opening is InputEventJoypadButton else key(KEY_C))
   await process_frame
   check(cancelled_count == 1 and confirmed_count == 0 and start_attempts == 0 and not dialog.visible, label + ": Cancel after opening hold never starts media")
 check(host.panel.service.poll().status == "idle" and not FileAccess.file_exists(host.panel.journal_path), label + ": no worker or journal before independent consent")
 probe.media_host = null
 probe.free()
 host.free()
func run() -> void:
 token = str(Time.get_ticks_usec())
 await run_case("remapped_key",key(KEY_C),key(KEY_C,false),key(KEY_C,true,true))
 await run_case("remapped_pad",pad(JOY_BUTTON_Y),pad(JOY_BUTTON_Y,false))
 await run_case("native_enter",key(KEY_ENTER),key(KEY_ENTER,false),key(KEY_ENTER,true,true))
 await run_case("native_space",key(KEY_SPACE),key(KEY_SPACE,false),key(KEY_SPACE,true,true))
 await run_case("focus_lost_key",key(KEY_C),key(KEY_C,false),key(KEY_C,true,true),true)
 await run_case("focus_lost_pad",pad(JOY_BUTTON_Y),pad(JOY_BUTTON_Y,false),null,true)
 print("MEDIA_OPENING_GESTURE: %d assertions; %d failures" % [assertions,failures])
 quit(0 if failures == 0 else 1)
