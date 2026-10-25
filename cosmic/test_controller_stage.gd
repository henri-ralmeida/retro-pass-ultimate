extends SceneTree
const Profile = preload("res://cosmic/sms_mapping_profile.gd")
const Capture = preload("res://cosmic/controller_capture_session.gd")
const Regions = preload("res://cosmic/controller_hit_regions.gd")
const Symbols = preload("res://cosmic/controller_symbols.gd")
const Retro = preload("res://cosmic/libretro_sms_contract.gd")
var assertions := 0
var failures: Array[String] = []

func check(value: bool, description: String) -> void:
 assertions += 1
 if not value:
  failures.append(description)
  push_error(description)

func key(code: int, pressed := true, echo := false) -> InputEventKey:
 var event := InputEventKey.new()
 event.physical_keycode = code
 event.keycode = code
 event.pressed = pressed
 event.echo = echo
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

func make_session():
 var session = Capture.new()
 check(session.open(Profile.new().snapshot()), "Valid profile opens an isolated capture session")
 return session

func arm(session, action: String, channel: String) -> void:
 check(session.begin(action, channel, 27), "Capture begins: " + action + "/" + channel)
 session.advance(0.2, true)
 check(session.state == Capture.State.CAPTURING, "Neutral gate arms capture")

func idle(session) -> void:
 session.advance(0.2, true)
 check(session.state == Capture.State.BROWSING, "Released inputs return to browsing")

func _initialize() -> void:
 run.call_deferred()

func test_profiles() -> void:
 var profile = Profile.new()
 var original: Dictionary = profile.snapshot()
 check(profile.actions().size() == 7, "P1 exposes six pad commands and console Pause")
 check(Profile.new(1).actions().size() == 6, "P2 does not invent a second console Pause")
 check(profile.bindings.keyboard.button_1.code == KEY_Z, "Gameplay defaults are separate from frontend Confirm")
 check(profile.bindings.gamepad.button_1.code == JOY_BUTTON_A, "SMS button 1 defaults to physical south")
 check(not profile.rebind("button_1", "gamepad", {"kind": "button", "code": JOY_BUTTON_B}), "Conflicting binding requires explicit swap")
 check(profile.snapshot() == original, "Rejected conflict is non-mutating")
 check(profile.rebind("button_1", "gamepad", {"kind": "button", "code": JOY_BUTTON_B}, true), "Explicit swap accepted")
 check(profile.bindings.gamepad.button_2.code == JOY_BUTTON_A, "Swap retains previous input for the other command")
 check(not profile.rebind("reset", "keyboard", {"kind": "key", "code": KEY_R}), "Console Reset is not silently added as a pad button")
 for reserved in [KEY_ESCAPE, KEY_F1, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
  check(not profile.rebind("button_1", "keyboard", {"kind": "key", "code": reserved}), "Emergency/modifier-only key rejected")
 check(not profile.rebind("button_1", "gamepad", {"kind": "axis", "code": 0, "sign": 0}), "Axis without direction rejected")
 check(not profile.rebind("button_1", "gamepad", {"kind": "button", "code": -1}), "Negative raw button rejected")
 check(not profile.rebind("button_1", "gamepad", {"kind": "button", "code": JOY_BUTTON_MAX}), "Out-of-range raw button rejected")
 check(profile.rebind("left", "gamepad", {"kind": "axis", "code": JOY_AXIS_LEFT_X, "sign": -1}), "Signed analog direction supported")
 var restored = Profile.new()
 check(restored.load_snapshot(JSON.parse_string(JSON.stringify(profile.snapshot()))), "JSON roundtrip accepted, including numeric representation")
 check(restored.snapshot() == profile.snapshot(), "Roundtrip preserves all binding data")
 var corrupted: Dictionary = original.duplicate(true)
 corrupted.schema_version = 99
 check(not restored.load_snapshot(corrupted), "Unknown schema fails closed")
 corrupted = original.duplicate(true)
 corrupted.bindings.gamepad.button_2 = corrupted.bindings.gamepad.button_1.duplicate(true)
 check(not restored.load_snapshot(corrupted), "Malformed duplicated persisted binding rejected")
 corrupted = original.duplicate(true)
 corrupted.bindings.keyboard.erase("up")
 check(not restored.load_snapshot(corrupted), "Missing command rejected")
 corrupted = original.duplicate(true)
 corrupted.bindings.gamepad.button_1.device = 27
 check(not restored.load_snapshot(corrupted), "Runtime device IDs cannot leak into persisted binding schema")
 check(restored.snapshot() == profile.snapshot(), "All corrupt loads preserve prior valid state")

func test_keyboard_capture() -> void:
 var session = make_session()
 check(session.begin("button_1", "keyboard"), "Keyboard capture starts waiting for neutral")
 session.handle(key(KEY_ENTER))
 session.advance(0.1, true)
 check(session.state == Capture.State.ARMING and not session.dirty(), "Opening activation and short neutral interval cannot bind")
 session.advance(0.1, false)
 session.advance(0.1, true)
 check(session.state == Capture.State.ARMING, "Noise resets rather than accumulates neutral time")
 session.advance(0.1, true)
 check(session.state == Capture.State.CAPTURING, "Stable neutral completes arming")
 check(not session.handle(InputEventMouseButton.new()), "Capture leaves modal mouse Cancel accessible; host separately blocks HOME routing")
 session.handle(key(KEY_C, true, true))
 check(session.state == Capture.State.CAPTURING, "Echoed key cannot begin a candidate")
 var modified := key(KEY_C)
 modified.ctrl_pressed = true
 session.handle(modified)
 check(session.state == Capture.State.CAPTURING, "Modified shortcut cannot become a single-key mapping")
 session.handle(key(KEY_C))
 check(session.state == Capture.State.HELD_CANDIDATE and not session.dirty(), "Pressed key waits for release before changing draft")
 session.handle(key(KEY_V, false))
 check(session.state == Capture.State.HELD_CANDIDATE, "Different key release cannot commit candidate")
 session.handle(key(KEY_C, false))
 check(session.state == Capture.State.RELEASE_GATE and session.draft.bindings.keyboard.button_1.code == KEY_C, "Matching release changes draft only")
 check(session.live.bindings.keyboard.button_1.code == KEY_Z, "Live mapping remains unchanged before Save")
 check(session.handle(key(KEY_X)), "Release gate consumes fallthrough Confirm")
 check(not session.begin("button_2", "keyboard"), "Second hotspot cannot reenter while draining held input")
 idle(session)
 check(not session.close(), "Dirty dialog cannot disappear silently")
 check(session.save_with(func(_data): return ERR_CANT_CREATE) == ERR_CANT_CREATE, "Persistence failure exposed")
 check(session.state == Capture.State.SAVE_ERROR and session.dirty() and session.live.bindings.keyboard.button_1.code == KEY_Z, "Failed save preserves both old live profile and editable draft")
 check(session.save_with(func(_data): return OK) == OK, "Retry may commit after successful writer")
 check(not session.dirty() and session.live.bindings.keyboard.button_1.code == KEY_C, "Successful write atomically promotes draft")
 check(session.close(), "Saved dialog closes")
 check(not session.handle(key(KEY_X)), "Closed session stops owning events")

func test_cancel_conflicts_and_devices() -> void:
 var session = make_session()
 arm(session, "button_1", "gamepad")
 session.handle(button(JOY_BUTTON_X, true, 99))
 check(session.state == Capture.State.CAPTURING, "Other player's device cannot steal capture")
 session.handle(button(JOY_BUTTON_B))
 session.advance(0.2, false, true)
 session.handle(button(JOY_BUTTON_B, false))
 check(session.state == Capture.State.CONFLICT and not session.dirty(), "Short east press remains assignable and exposes conflict without changing profile")
 check(not session.handle(button(JOY_BUTTON_A)), "Conflict allows modal navigation and explicit choices instead of swallowing GUI")
 check(session.resolve_conflict(false), "Conflict can be canceled explicitly")
 idle(session)
 arm(session, "button_1", "gamepad")
 session.handle(button(JOY_BUTTON_B))
 session.handle(button(JOY_BUTTON_B, false))
 check(session.resolve_conflict(true), "Conflict can be resolved explicitly by swap")
 check(session.draft.bindings.gamepad.button_1.code == JOY_BUTTON_B and session.draft.bindings.gamepad.button_2.code == JOY_BUTTON_A, "Both swap assignments staged consistently")
 idle(session)
 var before: Dictionary = session.draft.snapshot()
 arm(session, "up", "gamepad")
 session.handle(button(JOY_BUTTON_B))
 session.advance(0.81, false, true)
 check(session.state == Capture.State.RELEASE_GATE and session.draft.snapshot() == before, "Gamepad-only hold cancel wins over capture without rebinding east")
 session.handle(button(JOY_BUTTON_B, false))
 session.advance(0.1, true)
 check(session.state == Capture.State.RELEASE_GATE, "Cancel release does not activate underlying Back")
 idle(session)
 arm(session, "up", "keyboard")
 session.handle(key(KEY_ESCAPE))
 session.handle(key(KEY_ESCAPE, true, true))
 check(session.state == Capture.State.RELEASE_GATE and session.draft.snapshot() == before, "Repeated Escape only cancels capture, does not close modal or discard previous draft")
 idle(session)
 arm(session, "left", "gamepad")
 session.handle(axis(JOY_AXIS_LEFT_X, -0.4))
 check(session.state == Capture.State.CAPTURING, "Analog drift below threshold rejected")
 session.handle(axis(JOY_AXIS_LEFT_X, -0.8))
 check(session.state == Capture.State.HELD_CANDIDATE, "Intentional signed axis excursion accepted")
 session.handle(axis(JOY_AXIS_LEFT_Y, 0.0))
 check(session.state == Capture.State.HELD_CANDIDATE, "Another axis cannot release candidate")
 session.handle(axis(JOY_AXIS_LEFT_X, -0.3))
 check(session.state == Capture.State.HELD_CANDIDATE, "Hysteresis prevents early release")
 session.handle(axis(JOY_AXIS_LEFT_X, -0.2))
 check(session.draft.bindings.gamepad.left == {"kind": "axis", "code": JOY_AXIS_LEFT_X, "sign": -1}, "Signed axis staged only on return to neutral")
 idle(session)
 arm(session, "right", "gamepad")
 session.handle(button(JOY_BUTTON_Y))
 before = session.draft.snapshot()
 session.focus_changed(false)
 session.handle(button(JOY_BUTTON_Y, false))
 session.advance(2.0, true)
 check(session.state == Capture.State.RELEASE_GATE and session.draft.snapshot() == before, "Focus loss cancels capture and prevents background commit")
 session.focus_changed(true)
 idle(session)
 arm(session, "right", "gamepad")
 session.disconnected(99)
 check(session.state == Capture.State.CAPTURING, "Unrelated device disconnect does not affect pinned device")
 session.disconnected(27)
 session.handle(button(JOY_BUTTON_Y, true, 99))
 idle(session)
 check(not session.begin("right", "gamepad", 99), "Disconnect does not silently adopt another controller")
 check(session.assign_device(99), "User may explicitly identify replacement device")
 check(session.begin("right", "gamepad", 99), "Explicit new device is usable")
 session.cancel()
 idle(session)
 check(session.close(true), "Explicit discard closes dirty session")
 check(session.draft.snapshot() == session.live.snapshot(), "Discard restores last successfully saved state")

func test_regions() -> void:
 var picker = Regions.new()
 var bounds := {
  "Pad_button_1": AABB(Vector3(0.0136, 0.015, -0.0001), Vector3(0.0122, 0.00235, 0.0122)),
  "Pad_button_2": AABB(Vector3(0.0316, 0.015, -0.0001), Vector3(0.0122, 0.00235, 0.0122)),
  "Pad_eight_direction_rocker": AABB(Vector3(-0.04313989, 0.0144, -0.01513989), Vector3(0.02987978, 0.0022, 0.02987978))
 }
 check(picker.configure(bounds), "Approved mesh bounds create invisible hit regions")
 var points := {"button_1": Vector3(0.0197, 0.1, 0.006), "button_2": Vector3(0.0377, 0.1, 0.006), "up": Vector3(-0.0282, 0.1, -0.0094), "down": Vector3(-0.0282, 0.1, 0.0090), "left": Vector3(-0.0374, 0.1, -0.0002), "right": Vector3(-0.0190, 0.1, -0.0002)}
 for action in points:
  check(picker.pick_local_ray(points[action], Vector3.DOWN).get("action", "") == action, "Correct physical hotspot: " + action)
  var transform := Transform3D(Basis.from_euler(Vector3(0.3, -0.6, 0.2)).scaled(Vector3(1.5, 0.8, 2.0)), Vector3(10, 5, -3))
  check(picker.pick_world_ray(transform * points[action], transform.basis * Vector3.DOWN, transform).get("action", "") == action, "World transform and nonuniform scale preserve hotspot: " + action)
 check(picker.pick_local_ray(Vector3(-0.0282, 0.1, -0.0002), Vector3.DOWN).is_empty(), "D-pad center is not invented as another button")
 check(picker.pick_local_ray(Vector3(-0.0202, 0.1, -0.0082), Vector3.DOWN).is_empty(), "Ambiguous diagonal boundary is not silently assigned")
 check(picker.pick_local_ray(Vector3(0.0287, 0.1, 0.006), Vector3.DOWN).is_empty(), "Gap between buttons never selects either button")
 check(picker.pick_local_ray(Vector3(0.0197, -0.1, 0.006), Vector3.UP).is_empty(), "No selection through pad underside")
 check(picker.pick_local_ray(Vector3(0.0197, 0.1, 0.006), Vector3.RIGHT).is_empty(), "Grazing ray cannot select through the side")
 check(picker.pick_local_ray(Vector3(0.5, 0.1, 0.5), Vector3.DOWN).is_empty(), "Outside click remains inert")
 check(Regions.viewport_point(Vector2(500, 300), Rect2(100, 100, 800, 400), Vector2(1600, 800)) == Vector2(800, 400), "Viewport coordinates account for offset and scaling")
 check(Regions.viewport_point(Vector2(50, 300), Rect2(100, 100, 800, 400), Vector2(1600, 800)) == Vector2(-1, -1), "Letterbox/outside content ignored")
 bounds.erase("Pad_button_2")
 check(not picker.configure(bounds), "Missing named mesh disables picking rather than inventing geometry")
 check(picker.pick_local_ray(points.button_1, Vector3.DOWN).is_empty(), "Failed reconfiguration leaves no stale interactive hotspot")

func test_keyboard_labels_preserve_special_keys() -> void:
 var calls := [0]
 var broken_layout := func(code: int) -> int:
  calls[0] += 1
  return {KEY_UP: KEY_PRINT, KEY_DOWN: KEY_META, KEY_LEFT: KEY_ALT}.get(code, KEY_Z)
 for code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_TAB, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN, KEY_F2, KEY_KP_1]:
  check(Symbols.keyboard_label(code, broken_layout) == OS.get_keycode_string(code), "Non-printable identity survives a broken layout converter: " + OS.get_keycode_string(code))
 check(calls[0] == 0, "Special keys never reach the physical-layout converter")
 check(Symbols.keyboard_label(KEY_Y, broken_layout) == OS.get_keycode_string(KEY_Z), "Printable physical keys still use the keyboard layout")
 check(calls[0] == 1, "Printable key invokes layout converter exactly once")
 check(Symbols.keyboard_label(KEY_A, func(_code): return KEY_NONE) == "A", "Missing layout result falls back to physical key")
 check(Symbols.keyboard_label(KEY_A, func(_code): return KEY_PRINT) == "A", "Bogus special result cannot relabel a printable key")
 check(Symbols.glyph({"kind":"key", "code":KEY_UP}) == OS.get_keycode_string(KEY_UP), "Public glyph preserves arrow identity")

func test_symbols_and_adapter() -> void:
 for name in ["XInput Controller", "Steam Virtual Gamepad", "Wireless Controller", ""]:
  check(Symbols.family(name) == "generic", "Ambiguous identity is not guessed: " + name)
 check(Symbols.family("Sony DualSense Wireless Controller") == "playstation", "Known PlayStation name receives matching symbols")
 check(Symbols.family("Xbox Wireless Controller") == "xbox", "Known Xbox name receives matching symbols")
 var south := {"kind": "button", "code": JOY_BUTTON_A}
 check(Symbols.glyph(south, "XInput Controller") == "south", "Hidden XInput identity defaults to physical position")
 check(Symbols.glyph(south, "XInput Controller", "playstation") == "ps_cross", "Manual PlayStation display override is supported")
 check(Symbols.glyph(south, "Xbox Controller", "auto", false) == "Botão 1", "Unknown/unmapped pad does not falsely claim standardized face positions")
 check(Symbols.glyph({"kind": "button", "code": JOY_BUTTON_X}, "DualSense") == "ps_square", "Keyboard X and PlayStation cross remain distinct concepts")
 check(Retro.joypad_mask(["button_1"], 0, true) == 1, "SMS button 1 targets RETRO B, not Godot B")
 check(Retro.joypad_mask(["button_2"], 0, true) == 256, "SMS button 2 targets RETRO A")
 check(Retro.joypad_mask(["up", "right"], 0, true) == 144, "Legitimate diagonal contains two cardinals")
 check(Retro.joypad_mask(["up", "down", "left", "right", "button_1"], 0, true) == 1, "Opposite directions neutralize without erasing action buttons")
 check(Retro.joypad_mask(["pause"], 0, true) == 8, "Console pause is routed through port zero Start for this core contract")
 check(Retro.joypad_mask(["pause"], 1, true) == 0, "Player two does not invent its own pause input")
 check(Retro.joypad_mask(["reset", "power"], 0, true) == 0, "Reset/power never become accidental joypad bits")
 check(Retro.joypad_mask(["button_1", "pause"], 0, false) == 0, "Configuration/focus-loss gameplay gate is fully neutral")

func run() -> void:
 test_profiles()
 test_keyboard_capture()
 test_cancel_conflicts_and_devices()
 test_regions()
 test_keyboard_labels_preserve_special_keys()
 test_symbols_and_adapter()
 var report := {"assertions": assertions, "failures": failures, "passed": failures.is_empty(), "engine": Engine.get_version_info().string, "mode": "headless pure modules with synthetic input; no rendering, physical gamepad, Windows or emulation test"}
 var file := FileAccess.open("res://evidence/controller_stage_tests.json", FileAccess.WRITE)
 file.store_string(JSON.stringify(report, "  ") + "\n")
 print("CONTROLLER_STAGE_TESTS ", JSON.stringify(report))
 quit(0 if failures.is_empty() else 1)
