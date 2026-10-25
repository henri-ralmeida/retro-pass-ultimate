extends SceneTree
const Proof = preload("res://cosmic/atari_proof.gd")
var failures: Array[String] = []
func _initialize() -> void:
 _run.call_deferred()
func _expect(ok: bool, message: String) -> void:
 if not ok: failures.append(message)
func _run() -> void:
 var proof = Proof.new()
 root.add_child(proof)
 proof.dragging = true
 var release := InputEventMouseButton.new()
 release.button_index = MOUSE_BUTTON_LEFT
 release.pressed = false
 proof._input(release)
 _expect(not proof.dragging, "Global release cancels drag before GUI consumption")
 proof.dragging = true
 proof._cancel_drag()
 _expect(not proof.dragging, "Focus-loss cancellation resets drag")
 var wheel := InputEventMouseButton.new()
 wheel.pressed = true
 wheel.button_index = MOUSE_BUTTON_WHEEL_UP
 for i in 100: proof._unhandled_input(wheel)
 _expect(is_equal_approx(proof.distance, 0.45), "Near zoom bounded")
 wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
 for i in 100: proof._unhandled_input(wheel)
 _expect(is_equal_approx(proof.distance, 2.2), "Far zoom bounded")
 var key := InputEventKey.new()
 key.pressed = true
 key.keycode = KEY_UP
 for i in 100: proof._unhandled_input(key)
 _expect(is_equal_approx(proof.pivot.rotation.x, -1.2), "Keyboard rotation bounded")
 proof._reset_view()
 _expect(proof.pivot.rotation.is_zero_approx(), "Reset restores voluntary rotation")
 _expect(is_equal_approx(proof.distance, 1.12), "Reset restores camera")
 proof.free()
 for failure in failures: push_error(failure)
 print("ATARI INPUT TEST FAILURES: ", failures.size())
 quit(0 if failures.is_empty() else 1)
