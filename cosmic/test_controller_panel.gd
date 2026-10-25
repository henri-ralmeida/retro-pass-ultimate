extends SceneTree
const ControllerPanel = preload("res://cosmic/controller_mapping_panel.gd")
const Profile = preload("res://cosmic/sms_mapping_profile.gd")
const Store = preload("res://cosmic/controller_profile_store.gd")
const Capture = preload("res://cosmic/controller_capture_session.gd")
const Snapshot = preload("res://cosmic/controller_input_snapshot.gd")
const View = preload("res://cosmic/controller_model_view.gd")
var assertions := 0
var failures: Array[String] = []
var panel
var disconnected := false
var background_activations := 0

class FakeUIProfile extends RefCounted:
 func action_for(event: InputEvent) -> String:
  if event is InputEventKey and event.pressed and not event.echo:
   if event.keycode == KEY_X: return "confirm"
   if event.keycode == KEY_Z: return "back"
  if event is InputEventJoypadButton and event.pressed:
   if event.button_index == JOY_BUTTON_A: return "confirm"
   if event.button_index == JOY_BUTTON_B: return "back"
  return ""

func _initialize() -> void:
 run.call_deferred()

func check(value: bool, description: String) -> void:
 assertions += 1
 if not value:
  failures.append(description)
  push_error(description)

func key(code: int, pressed := true) -> InputEventKey:
 var event := InputEventKey.new()
 event.physical_keycode = code
 event.keycode = code
 event.pressed = pressed
 return event

func button(code: int, pressed := true, device := 27) -> InputEventJoypadButton:
 var event := InputEventJoypadButton.new()
 event.button_index = code
 event.pressed = pressed
 event.device = device
 return event

func axis(code: int, value: float, device := 27) -> InputEventJoypadMotion:
 var event := InputEventJoypadMotion.new()
 event.axis = code
 event.axis_value = value
 event.device = device
 return event

func send(event: InputEvent) -> void:
 # This is the host contract: never fall through to HOME while the panel is open.
 if panel.is_open():
  panel.route_input(event)
  return
 if event.is_pressed(): background_activations += 1

func neutral() -> void:
 panel.advance(0.2)

func make_panel() -> void:
 panel = ControllerPanel.new()
 panel.load_model = false
 panel.snapshot.poll_physical = false
 panel.device_provider = func(): return [99] if disconnected else [27, 99]
 panel.mapped_devices = {27: true, 99: false}
 panel.device_names = {27: "Synthetic Xbox", 99: "Synthetic Raw"}
 panel.store = Store.new("user://panel-%d/profiles.json" % Time.get_ticks_usec())
 root.add_child(panel)
 panel.set_process(false)
 panel.setup_host(FakeUIProfile.new())

func test_testing_preserves_gameplay_inputs() -> void:
 check(panel.open_player(0), "Input test fixture opens default P1")
 neutral()
 var original: Dictionary = panel.session.live.snapshot()
 panel._toggle_test()
 send(key(KEY_Z))
 panel.advance(0.1)
 check(panel.testing and panel.rows.button_1.text.begins_with("● "), "Default gameplay Z lights Button 1 instead of acting as UI Back")
 check(panel.model_view.focused_action == "button_1", "Keyboard Z highlights its geometric command during input test")
 send(key(KEY_Z, false))
 panel.advance(0.1)
 check(panel.testing and panel.rows.button_1.text.begins_with("○ "), "Releasing Z clears illumination without leaving test mode")
 send(key(KEY_ESCAPE)); send(key(KEY_ESCAPE, false))
 neutral()
 check(not panel.testing, "Esc explicitly exits keyboard input test")
 panel._identify_device()
 neutral()
 send(button(JOY_BUTTON_A)); send(button(JOY_BUTTON_A, false))
 neutral()
 panel._toggle_test()
 neutral()
 check(panel.hint.text.contains("0,8 s") and panel.hint.text.contains("toque curto"), "Gamepad exit hold is explained before testing")
 send(button(JOY_BUTTON_B))
 panel.advance(0.1)
 check(panel.testing and panel.rows.button_2.text.begins_with("● "), "Short default east/B lights Button 2 instead of closing input test")
 check(panel.model_view.focused_action == "button_2", "East/B preserves geometric highlight during input test")
 send(button(JOY_BUTTON_B, false))
 panel.advance(0.1)
 check(panel.testing and panel.rows.button_2.text.begins_with("○ "), "East release clears highlight but keeps test mode")
 send(button(JOY_BUTTON_B, true, 99))
 panel.advance(0.9)
 check(panel.testing, "Other device cannot end the pinned gamepad input test")
 send(button(JOY_BUTTON_B, false, 99))
 send(button(JOY_BUTTON_B))
 panel.advance(0.4)
 check(panel.testing and panel.notice.text.contains("50%"), "Hold exit reports progress while still testing the assigned button")
 panel.advance(0.41)
 check(not panel.testing and panel.session.state == Capture.State.RELEASE_GATE, "Only deliberate 0.8 second hold exits gamepad test")
 send(button(JOY_BUTTON_B, false))
 neutral()
 check(panel.session.live.snapshot() == original and not panel.session.dirty(), "Testing and hold exit never modify mappings")
 panel._toggle_test()
 send(key(KEY_F1)); send(key(KEY_F1, false))
 neutral()
 check(not panel.testing, "F1 also explicitly exits gamepad input test")
 # If the activation itself is held on the exit button, it must release first.
 panel.last_activation = button(JOY_BUTTON_B)
 panel.snapshot.observe(panel.last_activation)
 panel._toggle_test()
 panel.advance(1.0)
 check(panel.testing and not panel.test_cancel_armed, "Opening held button cannot immediately trigger hold-to-exit")
 send(button(JOY_BUTTON_B, false))
 neutral()
 check(panel.test_cancel_armed, "Opening neutral gate enables deliberate hold-to-exit")
 panel._toggle_test()
 neutral()
 panel.request_close()
 neutral()
 check(not panel.is_open(), "Input test fixture closes cleanly")
 panel.devices = {0: -1, 1: -1}
 panel.device_authorized.clear()
 check(panel.open_player(0), "Gamepad-only keyboard-test fixture opens")
 neutral()
 panel.test_button.grab_focus()
 send(button(JOY_BUTTON_A))
 send(button(JOY_BUTTON_A, false))
 neutral()
 check(panel.testing and panel.channel == "keyboard" and panel.devices[0] == -1, "Gamepad can enter keyboard test without silently assigning a gameplay device")
 send(button(JOY_BUTTON_B))
 panel.advance(0.81)
 check(not panel.testing and panel.session.state == Capture.State.RELEASE_GATE, "Opening gamepad can exit keyboard test with documented hold, without keyboard or mouse")
 send(button(JOY_BUTTON_B, false))
 neutral()
 panel.request_close()
 neutral()

func test_back_during_testing_does_not_queue_close() -> void:
 check(panel.open_player(0), "Back-test fixture opens")
 neutral()
 panel.begin_capture("button_1")
 neutral()
 send(key(KEY_V)); send(key(KEY_V, false))
 neutral()
 check(panel.session.dirty(), "Back-test has unsaved draft")
 panel._toggle_test()
 check(panel.close_button.disabled, "Back is unavailable until input testing ends")
 panel.request_close()
 panel.request_player(1)
 check(not panel.pending_close and panel.pending_port == -1, "Ignored test-mode navigation never queues hidden leave intent")
 panel._toggle_test()
 neutral()
 panel.save_changes()
 neutral()
 check(panel.is_open() and panel.player == 0 and not panel.session.dirty(), "Save after test commits without unexpected close or player change")
 panel.request_close()
 neutral()
 check(not panel.is_open(), "Explicit Back after testing still closes")

func test_open_capture_and_save() -> void:
 var opener := key(KEY_F1)
 check(panel.open_player(0, null, opener), "P1 opens a dedicated modal")
 check(not panel.open_player(1), "Repeated modal open is rejected")
 panel.advance(0.3)
 check(panel.session.state == Capture.State.RELEASE_GATE, "Opening key must release before browsing")
 send(key(KEY_F1, false))
 neutral()
 check(panel.session.state == Capture.State.BROWSING, "Opening release enables browsing")
 check(panel.rows.size() == 7 and panel.rows.has("pause"), "P1 list includes console Pause without inventing Start")
 var original: Dictionary = panel.session.live.snapshot()
 panel.begin_capture("button_1")
 neutral()
 check(panel.session.state == Capture.State.CAPTURING, "List starts capture after neutral gate")
 send(key(KEY_C))
 check(panel.session.state == Capture.State.HELD_CANDIDATE, "Press waits for matching release")
 send(key(KEY_C, false))
 neutral()
 check(panel.session.draft.bindings.keyboard.button_1.code == KEY_C, "Capture updates draft")
 check(panel.session.live.snapshot() == original, "Live profile unchanged before Save")
 check(background_activations == 0, "Raw capture never routes into HOME")
 panel.save_changes()
 check(panel.session.live.bindings.keyboard.button_1.code == KEY_C, "Disk writer OK promotes draft")
 neutral()
 check(not panel.session.dirty(), "Save produces a clean draft")
 var loaded: Dictionary = Store.new(panel.store.config_path).load_profiles()
 check(loaded.error == OK and loaded.profiles[0].bindings.keyboard.button_1.code == KEY_C, "Saved profile roundtrips through a new store")

func test_conflicts_and_decisions() -> void:
 panel.begin_capture("button_1")
 neutral()
 send(key(KEY_X)); send(key(KEY_X, false))
 check(panel.session.state == Capture.State.CONFLICT, "Intra-player conflict shown explicitly")
 check(panel.conflict_box.visible and not panel.conflict_text.text.is_empty(), "Conflict has both choices and explanatory text")
 var before: Dictionary = panel.session.draft.snapshot()
 panel._resolve_conflict(false)
 neutral()
 check(panel.session.draft.snapshot() == before, "Cancel conflict changes nothing")
 panel.begin_capture("button_1")
 neutral()
 send(key(KEY_X)); send(key(KEY_X, false))
 panel._resolve_conflict(true)
 neutral()
 check(panel.session.draft.bindings.keyboard.button_2.code == KEY_C, "Explicit swap preserves the displaced assignment")
 panel.request_player(1)
 check(panel.decision_box.visible and panel.player == 0, "Dirty player switch requires decision")
 panel._continue_editing()
 check(panel.player == 0 and panel.session.dirty(), "Continue editing preserves draft and player")
 panel.request_player(1)
 panel._discard_and_continue()
 neutral()
 check(panel.player == 1 and panel.rows.size() == 6 and not panel.rows.has("pause"), "Discard switches to P2 without extra Pause")
 panel.begin_capture("button_1")
 neutral()
 send(key(KEY_C)); send(key(KEY_C, false))
 neutral()
 panel.save_changes(false)
 check(panel.shared_box.visible, "Cross-player keyboard collision is not silently shared")
 check(panel.session.live.bindings.keyboard.button_1.code == KEY_G, "Cross-player decision leaves active P2 unchanged")
 panel._cancel_shared()
 check(panel.session.dirty(), "Declining sharing keeps draft editable")
 panel.save_changes(false)
 panel.save_changes(true)
 neutral()
 check(panel.session.live.bindings.keyboard.button_1.code == KEY_C, "Explicit cross-player sharing can commit exact key pair")

func test_device_focus_and_cancel() -> void:
 panel._identify_device()
 neutral()
 send(button(JOY_BUTTON_A)); send(button(JOY_BUTTON_A, false))
 neutral()
 check(panel.devices[1] == 27 and panel.channel == "gamepad", "Explicit press/release pins P2 device")
 panel.snapshot.observe(axis(JOY_AXIS_LEFT_X, 0.9, 99))
 check(panel.release_inputs_neutral(), "Public final gate ignores unrelated pad drift")
 panel.snapshot.observe(axis(JOY_AXIS_LEFT_X, 0.9, 27))
 check(not panel.release_inputs_neutral(), "Public final gate still blocks pinned axis hold")
 panel.snapshot.observe(axis(JOY_AXIS_LEFT_X, 0.0, 27))
 panel.snapshot.observe(axis(JOY_AXIS_LEFT_X, 0.0, 99))
 panel._focus_first()
 var previous_focus := root.gui_get_focus_owner()
 send(button(JOY_BUTTON_DPAD_DOWN)); send(button(JOY_BUTTON_DPAD_DOWN, false))
 check(root.gui_get_focus_owner() != previous_focus and panel.is_ancestor_of(root.gui_get_focus_owner()), "Known gamepad navigates contained focus")
 panel.begin_capture("button_1")
 neutral()
 send(button(JOY_BUTTON_X, true, 99)); send(button(JOY_BUTTON_X, false, 99))
 check(panel.session.state == Capture.State.CAPTURING, "Other controller cannot steal capture")
 send(button(JOY_BUTTON_X))
 panel.focus_changed(false)
 check(panel.session.state == Capture.State.RELEASE_GATE, "Focus loss aborts pending candidate")
 send(button(JOY_BUTTON_X, false))
 panel.focus_changed(true)
 neutral()
 check(panel.session.state == Capture.State.BROWSING, "Focus return does not resume capture")
 panel.begin_capture("button_1")
 neutral()
 send(button(JOY_BUTTON_B))
 panel.advance(0.9)
 check(panel.session.state == Capture.State.RELEASE_GATE and not panel.session.dirty(), "Long cancel hold does not map the east button")
 send(button(JOY_BUTTON_B, false))
 neutral()
 panel.begin_capture("button_1")
 neutral()
 send(axis(JOY_AXIS_LEFT_X, 0.7))
 check(panel.session.state == Capture.State.HELD_CANDIDATE, "Known controller signed axis captured")
 send(axis(JOY_AXIS_LEFT_X, 0.0))
 neutral()
 check(panel.session.draft.bindings.gamepad.button_1.kind == "axis", "Axis release changes draft only")
 disconnected = true
 panel._device_connection_changed(27, false)
 neutral()
 check(panel.devices[1] == 27 and not panel.device_authorized.has(27), "Disconnect preserves absent selection and removes authorization")
 disconnected = false
 panel.begin_capture("button_2")
 check(panel.session.state == Capture.State.BROWSING, "Reconnect never silently authorizes the old runtime ID")
 panel._identify_device()
 neutral()
 send(button(4, true, 99)); send(button(4, false, 99))
 neutral()
 check(panel.devices[1] == 99 and not panel._mapped(99), "Unknown device remains explicitly raw")
 panel.begin_capture("button_2")
 check(panel.session.state == Capture.State.BROWSING, "Unknown device needs verified cancel button first")
 panel._identify_cancel()
 neutral()
 send(button(5, true, 99)); send(button(5, false, 99))
 neutral()
 check(panel.verified_cancel.get(99) == 5, "Unknown cancel button requires deliberate press/release")
 panel.begin_capture("button_2")
 neutral()
 send(axis(0, 0.8, 99))
 check(panel.session.state == Capture.State.CAPTURING, "Unknown uncalibrated axes are not captured")
 panel._cancel_capture()
 neutral()

func test_modal_navigation_and_close() -> void:
 panel.channel = "keyboard"
 panel._refresh()
 panel._focus_first()
 var before := root.gui_get_focus_owner()
 send(key(KEY_TAB)); send(key(KEY_TAB, false))
 check(root.gui_get_focus_owner() != before, "Keyboard Tab navigates only within modal")
 check(panel.is_ancestor_of(root.gui_get_focus_owner()), "Focus stays inside modal")
 panel.request_close()
 check(panel.decision_box.visible, "Dirty close prompts save/discard/continue")
 panel._discard_and_continue()
 send(key(KEY_X))
 panel.advance(0.3)
 check(panel.is_open(), "Closing waits while a confirm key is held")
 send(key(KEY_X, false))
 neutral()
 check(not panel.is_open(), "Closing completes after neutral interval")
 check(background_activations == 0, "No modal event reaches background even when closing")

func test_snapshot() -> void:
 var state = Snapshot.new()
 state.poll_physical = false
 state.observe(button(JOY_BUTTON_A, true, 99))
 check(state.neutral(27), "Unrelated device does not block pinned-device neutral")
 state.mark_opening(button(JOY_BUTTON_A, true, 99))
 check(not state.neutral(27), "Opening device held gesture does block neutral")
 state.observe(button(JOY_BUTTON_A, false, 99))
 check(state.neutral(27), "Opening device release clears neutral gate")
 state.observe(axis(0, 0.1, 27))
 check(state.neutral(27), "Small axis drift is neutral")
 state.observe(axis(0, 0.3, 27))
 check(not state.neutral(27), "Axis outside release threshold blocks neutral")
 state.forget_device(27)
 check(state.neutral(27), "Disconnected event ledger clears held controls")

func test_model_view() -> void:
 var view = View.new()
 root.add_child(view)
 view.size = Vector2(520, 300)
 var model := Node3D.new()
 for spec in [["Pad_eight_direction_rocker", Vector3(-0.0282, 0.0155, -0.0002), Vector3(0.02988, 0.0022, 0.02988)], ["Pad_button_1", Vector3(0.0197, 0.016175, 0.006), Vector3(0.0122, 0.00235, 0.0122)], ["Pad_button_2", Vector3(0.0377, 0.016175, 0.006), Vector3(0.0122, 0.00235, 0.0122)]]:
  var mesh := MeshInstance3D.new()
  mesh.name = spec[0]
  mesh.position = spec[1]
  var box := BoxMesh.new()
  box.size = spec[2]
  mesh.mesh = box
  model.add_child(mesh)
 check(view.install_instance(model), "Model view derives hotspots from geometry bounds")
 var mesh1 := model.get_child(1) as MeshInstance3D
 var original_mesh := mesh1.mesh
 var original_material := mesh1.material_override
 view.set_highlight("button_1")
 check(view.highlight.visible and mesh1.mesh == original_mesh and mesh1.material_override == original_material, "Highlight is a separate overlay, never mutating source mesh or material")
 var point: Vector2 = view.camera.unproject_position(Vector3(0.0197, 0.018, 0.006))
 check(view.action_at(point) == "button_1", "Face-on camera ray selects geometric button")
 view.set_zoom(99.0)
 check(is_equal_approx(view.zoom, 1.4), "Zoom is bounded without rotating or editing geometry")
 view.clear_model()
 check(view.action_at(Vector2.ZERO).is_empty(), "Missing model has no invented hotspot")
 view.queue_free()

func run() -> void:
 make_panel()
 await process_frame
 panel.set_process(false)
 test_testing_preserves_gameplay_inputs()
 test_back_during_testing_does_not_queue_close()
 test_open_capture_and_save()
 test_conflicts_and_decisions()
 test_device_focus_and_cancel()
 test_modal_navigation_and_close()
 test_snapshot()
 test_model_view()
 var report := {"assertions": assertions, "failures": failures, "synthetic_only": true, "hardware_tested": false, "ui_render_reviewed": false}
 var output := FileAccess.open("res://evidence/controller_panel_tests.json", FileAccess.WRITE)
 output.store_string(JSON.stringify(report, "  "))
 output.close()
 print(JSON.stringify(report))
 panel.queue_free()
 await process_frame
 quit(0 if failures.is_empty() else 1)
