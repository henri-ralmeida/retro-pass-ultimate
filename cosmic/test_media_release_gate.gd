extends SceneTree
class Host:
 extends "res://cosmic/main.gd"
 var restored := 0
 func _ready() -> void: pass
 func _set_background_blocked(_value: bool) -> void: pass
 func _restore_controller_focus() -> void: restored += 1
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func axis(host, code: int, value: float, device := 7) -> void:
 var event := InputEventJoypadMotion.new()
 event.device = device
 event.axis = code
 event.axis_value = value
 host._input(event)
func gate(host) -> void:
 host.media_release_gate = true
 host.controller_release_gate = true
 host.controller_release_elapsed = 0.0
func advance(host) -> void:
 host._advance_controller_release_gate(0.2, host._controller_inputs_neutral())
func run() -> void:
 var host := Host.new()
 root.add_child(host)
 host.set_process(false)
 host.set_process_input(false)
 host.media_input_snapshot.poll_physical = false
 host.media_release_device = 7
 for code in [JOY_AXIS_RIGHT_Y, JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
  gate(host)
  axis(host, code, 0.3)
  advance(host)
  check(host.controller_release_gate, "Raw axis above interaction threshold blocks return")
  axis(host, code, 0.0)
  advance(host)
  check(not host.controller_release_gate, "Neutral axis releases gate")
 gate(host)
 var key := InputEventKey.new()
 key.keycode = KEY_RIGHT
 key.pressed = true
 host._input(key)
 advance(host)
 check(host.controller_release_gate, "Digital navigation held blocks")
 key.pressed = false
 host._input(key)
 advance(host)
 check(not host.controller_release_gate, "Digital release restores")
 gate(host)
 axis(host, JOY_AXIS_RIGHT_Y, 0.8)
 host.application_focused = false
 axis(host, JOY_AXIS_RIGHT_Y, 0.0)
 host.application_focused = true
 advance(host)
 check(not host.controller_release_gate, "Release during focus loss remains observed")
 gate(host)
 axis(host, JOY_AXIS_RIGHT_Y, 0.8)
 host._joy_connection_changed(7, false)
 advance(host)
 check(not host.controller_release_gate, "Disconnected pad cannot trap gate")
 gate(host)
 axis(host, JOY_AXIS_RIGHT_Y, 0.8, 99)
 advance(host)
 check(not host.controller_release_gate, "Unrelated pad cannot trap return")
 gate(host)
 var opener := InputEventJoypadButton.new()
 opener.device = 9
 opener.button_index = JOY_BUTTON_B
 opener.pressed = true
 host.media_input_snapshot.mark_opening(opener)
 host._input(opener)
 advance(host)
 check(host.controller_release_gate, "Separate opening pad is guarded")
 opener.pressed = false
 host._input(opener)
 advance(host)
 check(not host.controller_release_gate, "Cancel release on opener permits return")
 gate(host)
 axis(host, JOY_AXIS_LEFT_X, 0.2)
 axis(host, JOY_AXIS_LEFT_Y, 0.2)
 advance(host)
 check(host.controller_release_gate, "Diagonal magnitude blocks rotation even below per-axis threshold")
 axis(host, JOY_AXIS_LEFT_X, 0.0)
 axis(host, JOY_AXIS_LEFT_Y, 0.0)
 advance(host)
 check(not host.controller_release_gate, "Diagonal neutral permits return")
 check(host.restored == 9, "Exactly one restoration per neutral return")
 host.free()
 print("MEDIA_RELEASE_GATE: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
