extends SceneTree
## Headless GUI dispatch, synthetic events. Not rendered visual QA or physical input.
const ControllerPanel = preload("res://cosmic/controller_mapping_panel.gd")
const Capture = preload("res://cosmic/controller_capture_session.gd")
const Store = preload("res://cosmic/controller_profile_store.gd")
var assertions := 0
var failures: Array[String] = []
var host: Node
var panel
var background: Button
var background_presses := 0

class Host extends Node:
 var modal
 func _input(event: InputEvent) -> void:
  if is_instance_valid(modal) and modal.is_open():
   if modal.route_input(event): get_viewport().set_input_as_handled()
   return

class UIProfile extends RefCounted:
 func action_for(event: InputEvent) -> String:
  if event is InputEventJoypadButton and event.pressed:
   if event.button_index == JOY_BUTTON_A: return "confirm"
   if event.button_index == JOY_BUTTON_B: return "back"
  return ""

func _initialize() -> void:
 run.call_deferred()

func check(value: bool, message: String) -> void:
 assertions += 1
 if not value:
  failures.append(message)
  push_error(message)

func key(code: int, pressed: bool) -> InputEventKey:
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = pressed
 return event

func dispatch(event: InputEvent) -> void:
 root.push_input(event, true)
 await process_frame

func click(control: Control, double_click := false) -> void:
 var scroll := panel.column.get_parent() as ScrollContainer
 scroll.ensure_control_visible(control)
 await process_frame
 await process_frame
 var point := control.get_global_rect().get_center()
 var motion := InputEventMouseMotion.new()
 motion.position = point
 motion.global_position = point
 await dispatch(motion)
 for pressed in [true, false]:
  var event := InputEventMouseButton.new()
  event.position = point
  event.global_position = point
  event.button_index = MOUSE_BUTTON_LEFT
  event.pressed = pressed
  event.double_click = double_click and pressed
  await dispatch(event)

func run() -> void:
 root.size = Vector2i(1152,648)
 host = Host.new()
 root.add_child(host)
 background = Button.new()
 background.text = "HOME behind modal"
 background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 background.pressed.connect(func(): background_presses += 1)
 host.add_child(background)
 panel = ControllerPanel.new()
 panel.load_model = false
 panel.store = Store.new("user://gui-%d/profiles.json" % Time.get_ticks_usec())
 panel.snapshot.poll_physical = false
 panel.device_provider = func(): return [27]
 panel.mapped_devices[27] = true
 panel.device_names[27] = "Synthetic Xbox"
 host.add_child(panel)
 host.modal = panel
 panel.setup_host(UIProfile.new())
 panel.set_process(false)
 check(panel.open_player(0, background), "Modal opens over focusable HOME control")
 panel.advance(0.2)
 await process_frame
 await process_frame
 check(panel.hint.text.contains("Escolha um comando") and not panel.hint.text.contains("Pressione e solte"), "Browsing hints select a command rather than falsely announcing capture")
 await click(panel.rows.button_1, true)
 check(panel.session.state == Capture.State.BROWSING, "Second HOME double-click cannot start a mapping in the newly opened modal")
 await click(panel.rows.button_1)
 check(panel.session.state == Capture.State.ARMING, "Real GUI mouse release selects textual command")
 check(panel.hint.text.contains("Solte a entrada"), "Arming hint explains release of the opening gesture")
 panel.advance(0.2)
 check(panel.session.state == Capture.State.CAPTURING, "Mouse opening gesture has genuinely released")
 check(panel.hint.text.contains("Pressione e solte"), "Only active capture asks for a physical key")
 await click(panel.cancel_capture_button)
 check(panel.session.state == Capture.State.RELEASE_GATE, "Mouse Cancel reaches modal GUI during raw capture")
 panel.advance(0.2)
 await click(panel.rows.button_1)
 panel.advance(0.2)
 await dispatch(key(KEY_C, true))
 await dispatch(key(KEY_C, false))
 panel.advance(0.2)
 check(panel.session.draft.bindings.keyboard.button_1.code == KEY_C, "Key dispatch is captured instead of activating GUI/background")
 await click(panel.save_button)
 panel.advance(0.2)
 check(panel.session.live.bindings.keyboard.button_1.code == KEY_C and not panel.session.dirty(), "Mouse Save reaches GUI and commits through actual disk writer")
 await click(panel.rows.button_1)
 panel.advance(0.2)
 await dispatch(key(KEY_X, true))
 await dispatch(key(KEY_X, false))
 check(panel.session.state == Capture.State.CONFLICT, "Dispatched existing key opens conflict")
 await click(panel.conflict_cancel_button)
 panel.advance(0.2)
 check(panel.session.draft.bindings.keyboard.button_1.code == KEY_C, "Mouse conflict cancellation preserves binding")
 await click(panel.close_button)
 panel.advance(0.2)
 check(not panel.is_open(), "Mouse close finishes only after neutral gate")
 check(root.gui_get_focus_owner() == background, "Prior focus restored after close")
 check(background_presses == 0, "Every dispatched modal click/key is isolated from HOME")
 check(Store.new(panel.store.config_path).load_profiles().profiles[0].bindings.keyboard.button_1.code == KEY_C, "New store instance reloads saved mapping")
 var report := {"suite":"controller_gui_propagation", "assertions":assertions, "failures":failures, "headless_gui_dispatch":true, "rendered_visual_qa":false, "physical_hardware":false}
 var output := FileAccess.open("res://evidence/controller_gui_propagation_tests.json", FileAccess.WRITE)
 output.store_string(JSON.stringify(report, "  "))
 output.close()
 print(JSON.stringify(report))
 host.queue_free()
 await process_frame
 quit(0 if failures.is_empty() else 1)
