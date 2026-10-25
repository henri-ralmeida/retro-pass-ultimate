extends RefCounted
## Bindings use Godot's physical face positions; labels use the detected family.
const ACTIONS := ["confirm", "back", "inspect", "motion", "reset"]
const KEYS := {"confirm": KEY_X, "back": KEY_Z, "inspect": KEY_I, "motion": KEY_M, "reset": KEY_R}
const BUTTONS := {"confirm": JOY_BUTTON_A, "back": JOY_BUTTON_B, "inspect": JOY_BUTTON_X, "motion": JOY_BUTTON_Y, "reset": JOY_BUTTON_RIGHT_STICK}
var keys: Dictionary = KEYS.duplicate()
var buttons: Dictionary = BUTTONS.duplicate()
var family_override := "auto"
var config_path := "user://controls.cfg"

static func family_for_name(device_name: String) -> String:
 var normalized := device_name.to_lower()
 for marker in ["dualsense", "dualshock", "playstation", "sony", "ps4", "ps5"]:
  if marker in normalized: return "playstation"
 if "xbox" in normalized or "x-box" in normalized: return "xbox"
 # XInput, Steam Input and generic wireless names do not prove hardware identity.
 return "generic"

func family(device_name: String) -> String:
 return family_override if family_override != "auto" else family_for_name(device_name)

func load_settings() -> void:
 var config := ConfigFile.new()
 if config.load(config_path) != OK: return
 var saved_family: String = str(config.get_value("display", "family", "auto"))
 if saved_family in ["auto", "xbox", "playstation", "generic"]: family_override = saved_family
 for action in ACTIONS:
  var key_value = config.get_value("keyboard", action, keys[action])
  var button_value = config.get_value("gamepad", action, buttons[action])
  if key_value is int and key_value > 0: keys[action] = key_value
  if button_value is int and button_value >= 0 and button_value < JOY_BUTTON_MAX: buttons[action] = button_value
 # Ignore malformed duplicate mappings rather than making an action unreachable.
 if _has_duplicates(keys): keys = KEYS.duplicate()
 if _has_duplicates(buttons): buttons = BUTTONS.duplicate()

func save_settings() -> Error:
 var config := ConfigFile.new()
 config.set_value("display", "family", family_override)
 for action in ACTIONS:
  config.set_value("keyboard", action, keys[action])
  config.set_value("gamepad", action, buttons[action])
 return config.save(config_path)

func _has_duplicates(bindings: Dictionary) -> bool:
 var seen: Array = []
 for value in bindings.values():
  if value in seen: return true
  seen.append(value)
 return false

func rebind(action: String, code: int, gamepad: bool) -> bool:
 if action not in ACTIONS: return false
 if code < 0 or (gamepad and code >= JOY_BUTTON_MAX) or (not gamepad and code == 0): return false
 var bindings := buttons if gamepad else keys
 var previous: int = bindings[action]
 for other in ACTIONS:
  if other != action and bindings[other] == code: bindings[other] = previous
 bindings[action] = code
 return true

func action_for(event: InputEvent) -> String:
 if event is InputEventKey and event.pressed and not event.echo:
  var code: int = event.physical_keycode if event.physical_keycode else event.keycode
  for action in ACTIONS:
   if keys[action] == code: return action
 if event is InputEventJoypadButton and event.pressed:
  for action in ACTIONS:
   if buttons[action] == event.button_index: return action
 return ""

func glyph(action: String, gamepad: bool, device_name: String = "") -> String:
 if not gamepad:
  var physical: int = keys[action]
  var logical: int = physical
  if DisplayServer.get_name() != "headless": logical = DisplayServer.keyboard_get_keycode_from_physical(physical)
  return OS.get_keycode_string(logical if logical != 0 else physical)
 var button: int = buttons[action]
 var detected := family(device_name)
 if detected == "playstation":
  return {JOY_BUTTON_A: "ps_cross", JOY_BUTTON_B: "ps_circle", JOY_BUTTON_X: "ps_square", JOY_BUTTON_Y: "ps_triangle", JOY_BUTTON_RIGHT_STICK: "R3"}.get(button, "B%d" % (button + 1))
 if detected == "xbox":
  return {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_RIGHT_STICK: "RS"}.get(button, "B%d" % (button + 1))
 return {JOY_BUTTON_A: "south", JOY_BUTTON_B: "east", JOY_BUTTON_X: "west", JOY_BUTTON_Y: "north"}.get(button, "B%d" % (button + 1))
