extends RefCounted
## Presentation only. Family selection must never modify bindings or device identity.
static func family(device_name: String, override := "auto") -> String:
 if override in ["xbox", "playstation", "generic"]: return override
 var lower := device_name.to_lower()
 for token in ["dualsense", "dualshock", "playstation", "sony", "ps4", "ps5"]:
  if token in lower: return "playstation"
 if "xbox" in lower or "x-box" in lower: return "xbox"
 return "generic"

static func keyboard_label(code: int, layout_converter: Callable = Callable()) -> String:
 # Godot KEY_SPECIAL identifies non-printable keys. Passing those through the
 # platform's physical-layout conversion can turn arrows into unrelated keys.
 var logical := code
 if code >= KEY_SPACE and code <= 0x10FFFF and (code & KEY_SPECIAL) == 0:
  var converted := code
  if layout_converter.is_valid(): converted = int(layout_converter.call(code))
  elif DisplayServer.get_name() != "headless": converted = DisplayServer.keyboard_get_keycode_from_physical(code)
  # A missing or non-printable backend answer cannot relabel a printable key.
  if converted >= KEY_SPACE and converted <= 0x10FFFF and (converted & KEY_SPECIAL) == 0: logical = converted
 return OS.get_keycode_string(logical)

static func glyph(binding: Dictionary, device_name := "", override := "auto", mapped_device := true) -> String:
 var kind: String = str(binding.get("kind", ""))
 var code: int = int(binding.get("code", -1))
 if kind == "key":
  return keyboard_label(code)
 if kind == "axis": return "Eixo %d %s" % [code + 1, "−" if int(binding.get("sign", 1)) < 0 else "+"]
 if kind != "button": return "Não atribuído"
 if not mapped_device: return "Botão %d" % (code + 1)
 var detected := family(device_name, override)
 if detected == "playstation":
  return {JOY_BUTTON_A: "ps_cross", JOY_BUTTON_B: "ps_circle", JOY_BUTTON_X: "ps_square", JOY_BUTTON_Y: "ps_triangle", JOY_BUTTON_START: "Options", JOY_BUTTON_BACK: "Share/Create"}.get(code, "Botão %d" % (code + 1))
 if detected == "xbox":
  return {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_START: "Menu", JOY_BUTTON_BACK: "View"}.get(code, "Botão %d" % (code + 1))
 return {JOY_BUTTON_A: "south", JOY_BUTTON_B: "east", JOY_BUTTON_X: "west", JOY_BUTTON_Y: "north"}.get(code, "Botão %d" % (code + 1))
