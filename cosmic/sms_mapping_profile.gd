extends RefCounted
## Emulator-domain bindings only. Never changes frontend InputMap or controls.cfg.
const SCHEMA_VERSION := 1
const SYSTEM_ID := "master_system"
const PAD_ACTIONS := ["up", "down", "left", "right", "button_1", "button_2"]
const CHANNELS := ["keyboard", "gamepad"]
const FAMILIES := ["auto", "xbox", "playstation", "generic"]
var port := 0
var family_override := "auto"
var bindings: Dictionary = {}

func _init(player_port: int = 0) -> void:
 port = player_port
 restore_defaults()

func actions() -> Array:
 var result := PAD_ACTIONS.duplicate()
 if port == 0: result.append("pause")
 return result

func restore_defaults() -> void:
 bindings = {"keyboard": {}, "gamepad": {}}
 var key_codes: Array = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_Z, KEY_X, KEY_ENTER]
 if port == 1: key_codes = [KEY_W, KEY_S, KEY_A, KEY_D, KEY_G, KEY_H]
 var pad_codes: Array = [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START]
 var available := actions()
 for index in available.size():
  bindings.keyboard[available[index]] = {"kind": "key", "code": int(key_codes[index])}
  bindings.gamepad[available[index]] = {"kind": "button", "code": int(pad_codes[index])}
 family_override = "auto"

static func is_integer(value: Variant) -> bool:
 return value is int or (value is float and is_finite(value) and value == floor(value))

static func valid_binding(value: Variant, channel: String) -> bool:
 if not value is Dictionary or not value.has("kind") or not value.has("code"): return false
 if not is_integer(value.code): return false
 var code := int(value.code)
 if channel == "keyboard":
  return value.kind == "key" and value.size() == 2 and code > 0 and code < (1 << 24) and code not in [KEY_ESCAPE, KEY_F1, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]
 if channel != "gamepad": return false
 if value.kind == "button": return value.size() == 2 and code >= 0 and code < JOY_BUTTON_MAX
 if value.kind == "axis":
  return value.size() == 3 and code >= 0 and code < JOY_AXIS_MAX and value.has("sign") and is_integer(value.sign) and int(value.sign) in [-1, 1]
 return false

static func binding_key(value: Dictionary) -> String:
 return "%s:%d:%d" % [str(value.get("kind", "")), int(value.get("code", -1)), int(value.get("sign", 0))]

static func canonical_binding(value: Dictionary) -> Dictionary:
 var result := {"kind": str(value.kind), "code": int(value.code)}
 if value.kind == "axis": result.sign = int(value.sign)
 return result

func conflict_for(action: String, channel: String, candidate: Dictionary) -> String:
 if channel not in CHANNELS: return ""
 for other in actions():
  if other != action and binding_key(bindings[channel][other]) == binding_key(candidate): return other
 return ""

func rebind(action: String, channel: String, candidate: Dictionary, allow_swap := false) -> bool:
 if action not in actions() or not valid_binding(candidate, channel): return false
 var other := conflict_for(action, channel, candidate)
 if not other.is_empty() and not allow_swap: return false
 var old: Dictionary = bindings[channel][action].duplicate(true)
 if not other.is_empty(): bindings[channel][other] = old
 bindings[channel][action] = canonical_binding(candidate)
 return true

func snapshot() -> Dictionary:
 return {"schema_version": SCHEMA_VERSION, "system_id": SYSTEM_ID, "player_port": port, "family_override": family_override, "bindings": bindings.duplicate(true)}

func load_snapshot(data: Variant) -> bool:
 # Validate a separate candidate before replacing any live state. JSON numbers may be floats.
 if not data is Dictionary or data.size() != 5: return false
 for field in ["schema_version", "system_id", "player_port", "family_override", "bindings"]:
  if not data.has(field): return false
 if not is_integer(data.schema_version) or int(data.schema_version) != SCHEMA_VERSION: return false
 if data.system_id != SYSTEM_ID or not is_integer(data.player_port) or int(data.player_port) not in [0, 1]: return false
 if data.family_override not in FAMILIES or not data.bindings is Dictionary or data.bindings.size() != CHANNELS.size(): return false
 var available := PAD_ACTIONS.duplicate()
 if int(data.player_port) == 0: available.append("pause")
 for channel in CHANNELS:
  if not data.bindings.has(channel) or not data.bindings[channel] is Dictionary: return false
  if data.bindings[channel].size() != available.size(): return false
  var seen: Array[String] = []
  for action in available:
   if not data.bindings[channel].has(action): return false
   var candidate: Variant = data.bindings[channel][action]
   if not valid_binding(candidate, channel): return false
   var token := binding_key(candidate)
   if token in seen: return false
   seen.append(token)
 port = int(data.player_port)
 family_override = data.family_override
 bindings = {"keyboard": {}, "gamepad": {}}
 for channel in CHANNELS:
  for action in available:
   bindings[channel][action] = canonical_binding(data.bindings[channel][action])
 return true
