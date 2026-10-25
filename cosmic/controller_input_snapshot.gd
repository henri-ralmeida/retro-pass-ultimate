extends RefCounted
## Event ledger plus physical polling. The host observes every event, even while closed.
## Synthetic tests set poll_physical=false: that is not evidence of hardware testing.
const RELEASE := 0.25
var poll_physical := true
var keys: Dictionary = {}
var buttons: Dictionary = {}
var axes: Dictionary = {}
var mouse: Dictionary = {}
var opening_device := -1

func observe(event: InputEvent) -> void:
 if event is InputEventKey:
  var code: int = event.physical_keycode if event.physical_keycode else event.keycode
  if event.pressed: keys[code] = true
  else: keys.erase(code)
 elif event is InputEventMouseButton:
  # Wheel impulses never have an ordinary release.
  if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
   if event.pressed: mouse[event.button_index] = true
   else: mouse.erase(event.button_index)
 elif event is InputEventJoypadButton:
  if not buttons.has(event.device): buttons[event.device] = {}
  if event.pressed: buttons[event.device][event.button_index] = true
  else: buttons[event.device].erase(event.button_index)
 elif event is InputEventJoypadMotion:
  if not axes.has(event.device): axes[event.device] = {}
  axes[event.device][event.axis] = event.axis_value

func mark_opening(event: InputEvent) -> void:
 opening_device = -1
 if event == null: return
 if event is InputEventJoypadButton or event is InputEventJoypadMotion: opening_device = event.device

func _device_neutral(device: int, mapped := true) -> bool:
 if device < 0: return true
 if poll_physical:
  if device not in Input.get_connected_joypads(): return true
  for code in JOY_BUTTON_MAX:
   if Input.is_joy_button_pressed(device, code): return false
  # Unknown axes can have nonzero resting values: calibration is required before capture.
  if mapped:
   for code in JOY_AXIS_MAX:
    if absf(Input.get_joy_axis(device, code)) > RELEASE: return false
  return true
 if not buttons.get(device, {}).is_empty(): return false
 if mapped:
  for value in axes.get(device, {}).values():
   if not is_finite(float(value)) or absf(float(value)) > RELEASE: return false
 return true

func neutral(device := -1, mapped := true) -> bool:
 if poll_physical:
  # Lost releases are reconciled without fabricating a release of a still held key.
  for code in keys.keys():
   if not Input.is_physical_key_pressed(code) and not Input.is_key_pressed(code): keys.erase(code)
  for code in mouse.keys():
   if not Input.is_mouse_button_pressed(code): mouse.erase(code)
 if not keys.is_empty() or not mouse.is_empty(): return false
 if not _device_neutral(device, mapped): return false
 return opening_device == device or _device_neutral(opening_device, true)

func button_held(device: int, code: int) -> bool:
 if device < 0 or code < 0: return false
 if poll_physical: return device in Input.get_connected_joypads() and Input.is_joy_button_pressed(device, code)
 return buttons.get(device, {}).has(code)

func forget_device(device: int) -> void:
 buttons.erase(device)
 axes.erase(device)
 # Reconnection does not identify or assign a device.

func binding_pressed(binding: Dictionary, device: int) -> bool:
 match str(binding.get("kind", "")):
  "key":
   return Input.is_physical_key_pressed(int(binding.code)) if poll_physical else keys.has(int(binding.code))
  "button": return button_held(device, int(binding.code))
  "axis":
   if device < 0: return false
   var value := Input.get_joy_axis(device, int(binding.code)) if poll_physical else float(axes.get(device, {}).get(int(binding.code), 0.0))
   return value * int(binding.sign) >= 0.65
 return false
