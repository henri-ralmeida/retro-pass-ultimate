extends RefCounted
## Small native vector action vocabulary, inspired by the OLD's lucide semantics.
## No font-dependent symbols, network assets or action captions.
const PATHS := {
 "az": '<path d="m3 19 4-14 4 14M4 14h6M15 6h6l-6 12h6"/>',
 "za": '<path d="M3 6h6L3 18h6m5 1 4-14 4 14m-7-5h6"/>',
 "points": '<path d="m12 2 3 7 7 1-5 5 1 7-6-4-6 4 1-7-5-5 7-1 3-7z"/>',
 "rarity": '<path d="m4 4 16 16M5 14a5 5 0 1 0 5 5M19 10a5 5 0 1 0-5-5"/>',
 "save": '<path d="M4 3h14l3 3v15H3V3zm3 0v7h10V3M7 21v-7h10v7"/>',
 "points_high": '<path d="m10 2 2 6 6 1-4 4 1 6-5-3-5 3 1-6-4-4 6-1 2-6z"/><path d="M21 4v16m-2-2 2 2 2-2"/>',
 "points_low": '<path d="m10 2 2 6 6 1-4 4 1 6-5-3-5 3 1-6-4-4 6-1 2-6z"/><path d="M21 20V4m-2 2 2-2 2 2"/>',
 "rarity_common": '<path d="m3 3 14 14M5 12a4 4 0 1 0 4 5M15 8a4 4 0 1 0-5-5M21 20V4m-2 2 2-2 2 2"/>',
 "trophy": '<path d="M8 3h8v6a4 4 0 0 1-8 0V3zM8 5H4v3a4 4 0 0 0 4 4m8-7h4v3a4 4 0 0 1-4 4M12 13v6m-4 2h8m-7-2h6"/>',
 "comments": '<path d="M21 11a8 8 0 0 1-8 8H8l-5 3 1-6a8 8 0 1 1 17-5zM8 10h8m-8 4h5"/>',
 "hubs": '<path d="m12 3 10 5-10 5L2 8l10-5zm-10 9 10 5 10-5M2 16l10 5 10-5"/>',
 "sort": '<path d="M7 3v18m-4-4 4 4 4-4M17 21V3m-4 4 4-4 4 4"/>',
 "back": '<path d="m14 5-7 7 7 7M7 12h14"/>',
 "close": '<path d="m6 6 12 12M6 18 18 6"/>',
 "confirm": '<path d="m9 4 9 8-9 8V4z"/>',
 "inspect": '<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6M10 7v6m-3-3h6"/>',
 "manual": '<path d="M12 5v16M3 3l9 2 9-2v16l-9 2-9-2V3z"/>',
 "box": '<path d="m12 2 9 5v10l-9 5-9-5V7l9-5zm-9 5 9 5 9-5M12 12v10M7 4l10 6"/>',
 "insert": '<path d="M5 4h14v10H5V4zm3 3h8M12 14v7m-3-3 3 3 3-3M3 20v2h18v-2"/>',
 "reset": '<path d="M3 10a9 9 0 1 1 2 8M3 4v6h6"/>',
 "motion": '<path d="M8 4v16M16 4v16"/>',
 "settings": '<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="8" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="10" cy="18" r="2"/>',
 "folder": '<path d="M3 5h7l2 3h9v12H3V5zM12 11v6m-3-3h6"/>',
 "all": '<path d="M4 5h16M4 12h16M4 19h16"/>',
 "unlocked": '<circle cx="12" cy="12" r="9"/><path d="m7 12 3 3 7-7"/>',
 "locked": '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/>',
 "beaten": '<circle cx="12" cy="8" r="5"/><path d="m8 12-2 9 6-3 6 3-2-9"/>',
 "missable": '<path d="m12 3 10 18H2L12 3zm0 6v5m0 3v1"/>',
 "previous": '<path d="m15 4-8 8 8 8"/>',
 "next": '<path d="m9 4 8 8-8 8"/>',
 "zoom_in": '<circle cx="10" cy="10" r="7"/><path d="m15 15 6 6M10 6v8m-4-4h8"/>',
 "zoom_out": '<circle cx="10" cy="10" r="7"/><path d="m15 15 6 6M6 10h8"/>',
 "retry": '<path d="M3 10a9 9 0 1 1 2 8M3 4v6h6"/>',
 "gamepad": '<path d="M6 7h12l4 12-4 2-4-5h-4l-4 5-4-2L6 7zm1 3v6m-3-3h6m6-2h1m2 3h1"/>'
}
static var _cache := {}

static func texture(key: String) -> Texture2D:
 if _cache.has(key): return _cache[key]
 var image := Image.new()
 var body: String = PATHS.get(key,PATHS.settings)
 var error := image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#dce9fc" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">'+body+'</svg>',2.0)
 if error != OK: return null
 var result := ImageTexture.create_from_image(image)
 _cache[key] = result
 return result

static func style(fill := Color("101a2b"), stroke := Color("33455f")) -> StyleBoxFlat:
 var result := StyleBoxFlat.new()
 result.bg_color = fill
 result.border_color = stroke
 result.set_border_width_all(1)
 result.set_corner_radius_all(10)
 result.content_margin_left = 12
 result.content_margin_right = 12
 result.content_margin_top = 8
 result.content_margin_bottom = 8
 return result

static func decorate(button: Button) -> void:
 button.focus_mode = Control.FOCUS_ALL
 if not button.has_meta("focus_hint_hook"):
  button.set_meta("focus_hint_hook",true)
  button.focus_entered.connect(func(): _show_focus_hint.call_deferred(button))
  button.focus_exited.connect(func(): _hide_focus_hint(button))
  button.tree_exiting.connect(func(): _hide_focus_hint(button))
 button.add_theme_stylebox_override("normal",style(Color(0.04,0.07,0.13,0.86)))
 button.add_theme_stylebox_override("hover",style(Color("182d46"),Color("76b8e5")))
 button.add_theme_stylebox_override("pressed",style(Color("244965"),Color("b4e6ff")))
 button.add_theme_stylebox_override("focus",style(Color(0,0,0,0),Color("b4e6ff")))
 button.add_theme_stylebox_override("disabled",style(Color(0.05,0.07,0.11,0.6),Color("263044")))
 button.add_theme_color_override("icon_disabled_color",Color("546076"))

static func iconify(button: Button, key: String, tip: String = "") -> void:
 button.text = ""
 button.icon = texture(key)
 button.expand_icon = true
 button.add_theme_constant_override("icon_max_width",26)
 button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
 button.custom_minimum_size = Vector2(52,48)
 button.set_meta("ui_icon",key)
 if not tip.is_empty():
  button.tooltip_text = tip
  button.accessibility_name = tip
 button.accessibility_description = button.tooltip_text
 decorate(button)

static func action_icon(action: String, caption: String = "") -> String:
 var lower := caption.to_lower()
 if action == "local_media": return "folder"
 if "voltar" in lower: return "back"
 if "animar" in lower or "retomar movimento" in lower: return "confirm"
 if action == "confirm" and ("entrar" in lower or "abrir" in lower or "apresentado" in lower): return "box"
 if "manual" in lower or "livreto" in lower or "página" in lower: return "manual"
 if "inser" in lower or "cartucho" in lower: return "insert"
 return action if PATHS.has(action) else "settings"

static func _hide_focus_hint(button: Button) -> void:
 if not button.has_meta("focus_hint"): return
 var hint: Variant = button.get_meta("focus_hint",null)
 if is_instance_valid(hint): hint.queue_free()
 button.remove_meta("focus_hint")

static func _show_focus_hint(button: Button) -> void:
 if not is_instance_valid(button): return
 _hide_focus_hint(button)
 if not is_instance_valid(button) or not button.is_inside_tree() or not button.has_focus() or not button.is_visible_in_tree() or button.tooltip_text.is_empty(): return
 var layer := CanvasLayer.new()
 layer.layer = 90
 button.get_viewport().add_child(layer)
 button.set_meta("focus_hint",layer)
 var bubble := PanelContainer.new()
 bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
 bubble.add_theme_stylebox_override("panel",style(Color("1b3049"),Color("88bde2")))
 layer.add_child(bubble)
 var label := Label.new()
 label.text = button.tooltip_text.left(240)
 label.add_theme_font_size_override("font_size",14)
 label.add_theme_font_override("font",load("res://assets/fonts/ChakraPetch-Regular.ttf"))
 label.add_theme_color_override("font_color",Color("eef7ff"))
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 label.custom_minimum_size.x = 240
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 bubble.add_child(label)
 var rect := button.get_global_rect()
 var bounds := button.get_viewport_rect().size
 bubble.position = Vector2(clampf(rect.get_center().x-132,8,maxf(8,bounds.x-272)),maxf(8,rect.position.y-74))
