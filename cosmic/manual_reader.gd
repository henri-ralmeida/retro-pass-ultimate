extends Control
## Integrated local-image manual, not a PDF viewer or a game/emulator launcher.
## API: configure(host: Node); availability(item: Dictionary) -> bool;
## status_for(item: Dictionary) -> String; open_item(item: Dictionary) -> bool; close();
## handle_event(event: InputEvent) -> bool; layout(); cancel_drag(); signal closed.
## Host must route _input here FIRST and mark consumed events handled, including
## releases. Cancel the host's own drag/axis state on entry and on closed.
## open_item takes the SAME selected item, with a nonempty id and manual_pages:
## Array of absolute, res:// or user:// PNG/JPEG image paths, in reading order.
## Optional manual_item_id/manual_game_id declarations must match item.id. This
## enforces catalog identity, not visual verification of the scanned contents.
## Opening another item always discards old pages/cache, even if opening fails.
## false leaves the reader hidden; last_error is suitable for an unavailable UI.
## availability/status_for inspect identity, paths, file existence and byte size,
## never decode. Empty status means eligible, not a guarantee of valid image data.
## No fallback artwork, network URLs, SVG, PDF decoding, or external execution.
## Bounds: 128 pages, 8 MiB encoded/page, 4096 px/edge (including square 4K);
## at most 3 cached RGBA8 textures AND 64 MiB estimated cached texture storage.
## Only current/adjacent pages are decoded; dimensions are checked BEFORE decode.
## Peak CPU decode is one bounded input/image at a time; GPU/driver overhead is
## additional. Originals are never resized, modified, imported, or published.
signal closed

const MAX_PAGES := 128
const MAX_FILE_BYTES := 8 * 1024 * 1024
const MAX_EDGE := 4096
const MAX_PIXELS := 16_777_216
const MAX_CACHE_PAGES := 3
const MAX_CACHE_BYTES := 64 * 1024 * 1024
const ZOOM_MIN := 1.0
const ZOOM_MAX := 4.0
const ALLOWED_EXTENSIONS := ["png", "jpg", "jpeg"]

var host: Node
var item_id := ""
var pages: Array[String] = []
var current_page := 0
var zoom := 1.0
var pan := Vector2.ZERO
var dragging := false
var last_error := ""
var cache: Dictionary = {}
var cache_bytes := 0
var pan_axis := Vector2.ZERO
var zoom_axis := 0.0
var _trigger_values := Vector2.ZERO
var _axis_ready: Dictionary = {}
var _axis_latched := false
var _held: Dictionary = {}
var _clicked_button: Button
var _built := false
var _window_focused := true
var _natural_size := Vector2.ZERO
var _page_errors: Dictionary = {}
var _previous_focus: WeakRef
var _layout_size := Vector2.ZERO
var _buttons: Array[Button] = []
var _title: Label
var _eyebrow: Label
var _status: Label
var _help: Label
var _empty: Label
var _canvas: Panel
var _image: TextureRect
var _toolbar: HBoxContainer
var _previous: Button
var _next: Button
var _zoom_out: Button
var _zoom_in: Button
var _reset: Button
var _back: Button
var _font: Font = preload("res://assets/fonts/ChakraPetch-Regular.ttf")
var _heading_font: Font = preload("res://assets/fonts/Orbitron.ttf")

func configure(owner_node: Node) -> void:
 host = owner_node
 if is_instance_valid(host):
  if host.get("chakra") is Font: _font = host.get("chakra")
  if host.get("orbitron") is Font: _heading_font = host.get("orbitron")
 if is_inside_tree(): _build()

func _ready() -> void:
 name = "ManualReader"
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 z_index = 100
 visible = false
 _build()

func _build() -> void:
 if _built: return
 _built = true
 var shade := ColorRect.new()
 shade.color = Color("080c19")
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(shade)
 _eyebrow = _label("LEITOR DE MANUAL · PÁGINAS LOCAIS", 12, Color("94bcd1"))
 _title = _label("", 22, Color("eeeefa"))
 _title.add_theme_font_override("font", _heading_font)
 _title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 _title.clip_text = true
 _status = _label("", 15, Color("c6d8e7"))
 _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 _canvas = Panel.new()
 _canvas.clip_contents = true
 _canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
 _canvas.add_theme_stylebox_override("panel", _style(Color("101728"), Color("26364b")))
 add_child(_canvas)
 _image = TextureRect.new()
 _image.mouse_filter = Control.MOUSE_FILTER_IGNORE
 _image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 _image.stretch_mode = TextureRect.STRETCH_SCALE
 _image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
 _canvas.add_child(_image)
 _empty = _label("", 18, Color("bdc7d8"))
 remove_child(_empty)
 _canvas.add_child(_empty)
 _empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 _empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
 _empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _toolbar = HBoxContainer.new()
 _toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
 _toolbar.add_theme_constant_override("separation", 8)
 _toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(_toolbar)
 _previous = _button("‹ Anterior", "Página anterior", func(): navigate(-1))
 _next = _button("Próxima ›", "Próxima página", func(): navigate(1))
 _zoom_out = _button("−", "Reduzir zoom", func(): change_zoom(-0.25))
 _zoom_in = _button("+", "Ampliar página", func(): change_zoom(0.25))
 _reset = _button("Ajustar", "Ajustar página à tela", reset_view)
 _back = _button("Voltar", "Fechar manual e voltar", close)
 _help = _label("", 13, Color("98a9c0"))
 _help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 _help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 layout()

func _label(value: String, font_size: int, color: Color) -> Label:
 var label := Label.new()
 label.text = value
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 label.add_theme_font_override("font", _font)
 label.add_theme_font_size_override("font_size", font_size)
 label.add_theme_color_override("font_color", color)
 add_child(label)
 return label

func _style(fill: Color, border: Color) -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = fill
 style.border_color = border
 style.set_border_width_all(1)
 style.set_corner_radius_all(7)
 style.content_margin_left = 13
 style.content_margin_right = 13
 return style

func _button(value: String, description: String, callback: Callable) -> Button:
 var button := Button.new()
 button.text = value
 button.tooltip_text = description
 button.accessibility_name = description
 button.custom_minimum_size = Vector2(44, 38)
 button.add_theme_font_override("font", _font)
 button.add_theme_font_size_override("font_size", 16)
 button.add_theme_color_override("font_color", Color("dce9f4"))
 button.add_theme_stylebox_override("normal", _style(Color("152033"), Color("35455c")))
 button.add_theme_stylebox_override("hover", _style(Color("1c3046"), Color("7197b0")))
 button.add_theme_stylebox_override("pressed", _style(Color("233a50"), Color("9fc4db")))
 button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color("a6d2e5")))
 button.pressed.connect(callback)
 _toolbar.add_child(button)
 _buttons.append(button)
 return button

func availability(item: Dictionary) -> bool:
 return status_for(item).is_empty()

func status_for(item: Dictionary) -> String:
 var identity: Variant = item.get("id", "")
 if not identity is String or identity.strip_edges().is_empty(): return "Jogo sem identificação no catálogo."
 for field in ["manual_item_id", "manual_game_id"]:
  if item.has(field) and str(item[field]) != identity: return "O manual não corresponde ao jogo selecionado."
 var source: Variant = item.get("manual_pages", [])
 if not source is Array or source.is_empty():
  if not str(item.get("manual_pdf", "")).is_empty(): return "Leitura integrada de PDF não suportada; forneça páginas PNG ou JPEG."
  return "Manual indisponível para este jogo."
 if source.size() > MAX_PAGES: return "Manual excede o limite de %d páginas." % MAX_PAGES
 for value in source:
  if not value is String or not _path_allowed(value): return "Manual requer páginas locais PNG ou JPEG; PDF não é suportado."
  var file := FileAccess.open(value, FileAccess.READ)
  if file == null: return "Uma página do manual não está disponível no arquivo local."
  var length := file.get_length()
  file.close()
  if length <= 0 or length > MAX_FILE_BYTES: return "Uma página está vazia ou excede o limite de 8 MiB."
 return ""

func open_item(item: Dictionary) -> bool:
 if not is_inside_tree():
  last_error = "Leitor ainda não está disponível."
  return false
 _build()
 var old_focus := get_viewport().gui_get_focus_owner()
 if not visible and is_instance_valid(old_focus): _previous_focus = weakref(old_focus)
 _clear_session()
 last_error = "Manual indisponível para este jogo."
 var identity: Variant = item.get("id", "")
 if not identity is String or identity.strip_edges().is_empty(): return false
 for field in ["manual_item_id", "manual_game_id"]:
  if item.has(field) and str(item[field]) != identity:
   last_error = "O manual não corresponde ao jogo selecionado."
   return false
 var source: Variant = item.get("manual_pages", [])
 if not source is Array or source.is_empty(): return false
 if source.size() > MAX_PAGES:
  last_error = "Manual excede o limite de %d páginas." % MAX_PAGES
  return false
 for value in source:
  if not value is String or not _path_allowed(value):
   pages.clear()
   last_error = "Manual requer páginas locais PNG ou JPEG válidas; PDF não é suportado."
   return false
  pages.append(value)
 item_id = identity
 _title.text = str(item.get("title", item_id)).left(180)
 _title.tooltip_text = _title.text
 var first := _load_page(0)
 if first.is_empty():
  last_error = str(_page_errors.get(0, "Página indisponível."))
  _clear_session()
  return false
 last_error = ""
 visible = true
 _window_focused = true
 _block_held_inputs()
 _arm_neutral_axes()
 layout()
 _show_page()
 _back.grab_focus()
 return true

func close() -> void:
 var was_open := visible
 _clear_session()
 if is_inside_tree():
  var focus := get_viewport().gui_get_focus_owner()
  if is_instance_valid(focus) and is_ancestor_of(focus): focus.release_focus()
  if _previous_focus:
   var old: Variant = _previous_focus.get_ref()
   if is_instance_valid(old) and old is Control and old.is_visible_in_tree(): old.grab_focus()
 _previous_focus = null
 if was_open: closed.emit()

func _clear_session() -> void:
 visible = false
 cancel_drag()
 _held.clear()
 _axis_ready.clear()
 pages.clear()
 item_id = ""
 current_page = 0
 zoom = 1.0
 pan = Vector2.ZERO
 _natural_size = Vector2.ZERO
 if is_instance_valid(_image): _image.texture = null
 cache.clear()
 cache_bytes = 0
 _page_errors.clear()

func _path_allowed(path: String) -> bool:
 if path.is_empty() or path.length() > 4096: return false
 for offset in path.length():
  if path.unicode_at(offset) < 32: return false
 if path.get_extension().to_lower() not in ALLOWED_EXTENSIONS: return false
 if "://" in path and not path.begins_with("res://") and not path.begins_with("user://"): return false
 if not path.is_absolute_path(): return false
 # Do not reinterpret relative traversal, network shares, or device paths.
 if ".." in path.replace("\\", "/").split("/"): return false
 if path.begins_with("\\\\") or path.begins_with("//"): return false
 return true

func _be16(bytes: PackedByteArray, offset: int) -> int:
 return int(bytes[offset]) * 256 + int(bytes[offset + 1])

func _be32(bytes: PackedByteArray, offset: int) -> int:
 return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])

func _header_size(bytes: PackedByteArray, extension: String) -> Vector2i:
 if extension == "png":
  if bytes.size() < 33 or bytes.slice(0, 8) != PackedByteArray([137,80,78,71,13,10,26,10]): return Vector2i.ZERO
  if _be32(bytes, 8) != 13 or bytes.slice(12,16).get_string_from_ascii() != "IHDR": return Vector2i.ZERO
  # Reject 16-bit sources before decode to keep transient pixel storage bounded.
  if bytes[24] not in [1, 2, 4, 8]: return Vector2i.ZERO
  return Vector2i(_be32(bytes, 16), _be32(bytes, 20))
 if bytes.size() < 4 or bytes[0] != 0xff or bytes[1] != 0xd8: return Vector2i.ZERO
 var offset := 2
 while offset + 3 < bytes.size():
  if bytes[offset] != 0xff: return Vector2i.ZERO
  while offset < bytes.size() and bytes[offset] == 0xff: offset += 1
  if offset >= bytes.size(): return Vector2i.ZERO
  var marker := int(bytes[offset])
  offset += 1
  if marker in [0xd9, 0xda]: return Vector2i.ZERO
  if marker == 0x01 or marker in range(0xd0, 0xd9): continue
  if offset + 2 > bytes.size(): return Vector2i.ZERO
  var length := _be16(bytes, offset)
  if length < 2 or offset + length > bytes.size(): return Vector2i.ZERO
  if marker in [0xc0, 0xc1, 0xc2]:
   if length < 8: return Vector2i.ZERO
   return Vector2i(_be16(bytes, offset + 5), _be16(bytes, offset + 3))
  offset += length
 return Vector2i.ZERO

func _load_page(index: int, prefetch: bool = false) -> Dictionary:
 if cache.has(index): return cache[index]
 if index < 0 or index >= pages.size(): return {}
 if _page_errors.has(index): return {}
 var path := pages[index]
 if not _path_allowed(path): return _page_failed(index, "Caminho de página não permitido.")
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null: return _page_failed(index, "Página %d indisponível no arquivo local." % (index + 1))
 var length := file.get_length()
 if length <= 0 or length > MAX_FILE_BYTES:
  file.close()
  return _page_failed(index, "Página %d excede o limite de 8 MiB ou está vazia." % (index + 1))
 var bytes := file.get_buffer(length)
 file.close()
 if bytes.size() != length: return _page_failed(index, "Não foi possível ler a página %d." % (index + 1))
 var dimensions := _header_size(bytes, path.get_extension().to_lower())
 if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x > MAX_EDGE or dimensions.y > MAX_EDGE or dimensions.x * dimensions.y > MAX_PIXELS:
  return _page_failed(index, "Página %d inválida ou acima do limite de resolução." % (index + 1))
 var estimated_bytes := dimensions.x * dimensions.y * 4
 if prefetch and cache.has(current_page) and int(cache[current_page].bytes) + estimated_bytes > MAX_CACHE_BYTES: return {}
 _make_cache_room(estimated_bytes)
 if cache_bytes + estimated_bytes > MAX_CACHE_BYTES: return {}
 var decoded := Image.new()
 var error := decoded.load_png_from_buffer(bytes) if path.get_extension().to_lower() == "png" else decoded.load_jpg_from_buffer(bytes)
 if error != OK or decoded.is_empty(): return _page_failed(index, "Página %d corrompida ou não suportada." % (index + 1))
 if decoded.get_size() != dimensions: return _page_failed(index, "Dimensões inconsistentes na página %d." % (index + 1))
 decoded.convert(Image.FORMAT_RGBA8)
 var entry := {"texture": ImageTexture.create_from_image(decoded), "size": Vector2(dimensions), "bytes": estimated_bytes}
 cache[index] = entry
 cache_bytes += estimated_bytes
 return entry

func _page_failed(index: int, message: String) -> Dictionary:
 _page_errors[index] = message
 return {}

func _make_cache_room(bytes_needed: int) -> void:
 while not cache.is_empty() and (cache.size() >= MAX_CACHE_PAGES or cache_bytes + bytes_needed > MAX_CACHE_BYTES):
  var victim := -1
  var distance := -1
  for key in cache:
   if int(key) == current_page: continue
   if absi(int(key) - current_page) > distance:
    victim = int(key)
    distance = absi(victim - current_page)
  if victim < 0: break
  _evict(victim)

func _evict(index: int) -> void:
 if not cache.has(index): return
 cache_bytes -= int(cache[index].bytes)
 cache.erase(index)

func _show_page() -> void:
 _image.texture = null
 _natural_size = Vector2.ZERO
 for key in cache.keys():
  if absi(int(key) - current_page) > 1: _evict(int(key))
 var entry := _load_page(current_page)
 _empty.visible = entry.is_empty()
 if entry.is_empty():
  last_error = str(_page_errors.get(current_page, "Página indisponível."))
  _empty.text = last_error + "\nNenhuma página substituta foi criada."
 else:
  last_error = ""
  _image.texture = entry.texture
  _natural_size = entry.size
 # At most two adjacent pages; each decode bounded independently. Never preload
 # the full book. Large pages may evict the farther neighbor to retain current.
 for neighbor in [current_page + 1, current_page - 1]:
  if neighbor >= 0 and neighbor < pages.size(): _load_page(neighbor, true)
 _frame_page()

func navigate(direction: int) -> void:
 if not visible or pages.is_empty() or direction == 0: return
 var target := clampi(current_page + (1 if direction > 0 else -1), 0, pages.size() - 1)
 if target == current_page: return
 cancel_drag()
 current_page = target
 zoom = 1.0
 pan = Vector2.ZERO
 _show_page()

func change_zoom(amount: float) -> void:
 if not visible or _natural_size == Vector2.ZERO or not is_finite(amount): return
 var previous_zoom := zoom
 zoom = clampf(zoom + amount, ZOOM_MIN, ZOOM_MAX)
 pan *= zoom / previous_zoom
 _frame_page()

func reset_view() -> void:
 cancel_drag()
 zoom = 1.0
 pan = Vector2.ZERO
 _frame_page()

func _frame_page() -> void:
 if not _built: return
 if _natural_size.x > 0.0 and _natural_size.y > 0.0:
  var area := (_canvas.size - Vector2(24, 24)).max(Vector2.ONE)
  var fit := minf(area.x / _natural_size.x, area.y / _natural_size.y)
  var rendered := _natural_size * fit * zoom
  var limit := ((rendered - _canvas.size) * 0.5).max(Vector2.ZERO)
  pan = pan.clamp(-limit, limit)
  _image.size = rendered
  _image.position = (_canvas.size - rendered) * 0.5 + pan
 else:
  pan = Vector2.ZERO
 _status.text = "%02d / %02d · %d%%" % [current_page + 1, pages.size(), roundi(zoom * 100)]
 _previous.disabled = current_page <= 0
 _next.disabled = current_page >= pages.size() - 1
 _zoom_out.disabled = _natural_size == Vector2.ZERO or zoom <= ZOOM_MIN
 _zoom_in.disabled = _natural_size == Vector2.ZERO or zoom >= ZOOM_MAX

func layout() -> void:
 if not _built or not is_inside_tree(): return
 var view := get_viewport().get_visible_rect().size
 _layout_size = view
 var margin := clampf(view.x * 0.035, 18, 44)
 _eyebrow.position = Vector2(margin, 16)
 _eyebrow.size = Vector2(view.x - margin * 2, 20)
 _title.position = Vector2(margin, 39)
 _title.size = Vector2(maxf(80, view.x - margin * 2 - 180), 32)
 _title.add_theme_font_size_override("font_size", 18 if view.x < 900 else 22)
 _status.position = Vector2(view.x - margin - 174, 40)
 _status.size = Vector2(174, 28)
 _canvas.position = Vector2(margin, 84)
 _canvas.size = Vector2(maxf(1, view.x - margin * 2), maxf(1, view.y - 190))
 _empty.position = Vector2(22, 10)
 _empty.size = (_canvas.size - Vector2(44, 20)).max(Vector2.ONE)
 _toolbar.position = Vector2(margin, view.y - 91)
 _toolbar.size = Vector2(view.x - margin * 2, 40)
 _help.position = Vector2(margin, view.y - 43)
 _help.size = Vector2(view.x - margin * 2, 36)
 var profile: Variant = host.get("input_profile") if is_instance_valid(host) else null
 var back_key := "Esc / Z"
 var reset_key := "R"
 if profile != null and profile.has_method("glyph"):
  back_key = "Esc / " + str(profile.glyph("back", false))
  reset_key = str(profile.glyph("reset", false))
 _help.text = "← →: páginas · +/−: zoom · arrastar: mover · %s: ajustar · %s: voltar" % [reset_key, back_key]
 if is_instance_valid(host) and host.get("input_device") == "gamepad":
  _help.text = "Direcional / LB RB: páginas · LT RT: zoom · analógico direito: mover · Voltar: botão configurado"
 _frame_page()

func cancel_drag() -> void:
 dragging = false
 pan_axis = Vector2.ZERO
 zoom_axis = 0.0
 _trigger_values = Vector2.ZERO
 _axis_latched = false
 _clicked_button = null
 # An axis must return to neutral after interruption before it can act again.
 _axis_ready.clear()
 _arm_neutral_axes()

func _arm_neutral_axes() -> void:
 # Real devices generally emit only changes. Already-neutral axes should work
 # on their first deliberate movement, but held axes stay disarmed. Disconnected
 # synthetic events must explicitly send neutral before exercising an axis.
 for device in Input.get_connected_joypads():
  for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
   if absf(Input.get_joy_axis(device, axis)) < 0.22:
    _axis_ready["%d:%d" % [device, axis]] = true

func _block_held_inputs() -> void:
 var key_codes: Array = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN, KEY_EQUAL, KEY_PLUS, KEY_MINUS, KEY_KP_ADD, KEY_KP_SUBTRACT, KEY_ESCAPE, KEY_R, KEY_Z, KEY_TAB, KEY_ENTER, KEY_SPACE]
 var profile: Variant = host.get("input_profile") if is_instance_valid(host) else null
 if profile != null and profile.get("keys") is Dictionary: key_codes.append_array(profile.keys.values())
 for code in key_codes:
  if Input.is_physical_key_pressed(int(code)) or Input.is_key_pressed(int(code)): _held["k:%d" % int(code)] = true
 for device in Input.get_connected_joypads():
  for code in JOY_BUTTON_MAX:
   if Input.is_joy_button_pressed(device, code): _held["j:%d:%d" % [device, code]] = true

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
  _window_focused = false
  cancel_drag()
 elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
  _window_focused = true
  cancel_drag()
  _block_held_inputs()

func _process(delta: float) -> void:
 if not visible: return
 if get_viewport().get_visible_rect().size != _layout_size: layout()
 if not _window_focused: return
 var bounded_delta := clampf(delta, 0, 0.05)
 if pan_axis != Vector2.ZERO:
  pan -= pan_axis * 620.0 * bounded_delta
  _frame_page()
 if not is_zero_approx(zoom_axis): change_zoom(zoom_axis * bounded_delta * 1.6)

func _button_at(point: Vector2) -> Button:
 for button in _buttons:
  if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(point): return button
 return null

func _cycle_focus(reverse: bool) -> void:
 var available: Array[Button] = []
 for button in _buttons:
  if not button.disabled: available.append(button)
 if available.is_empty(): return
 var index := available.find(get_viewport().gui_get_focus_owner())
 available[posmod(index + (-1 if reverse else 1), available.size())].grab_focus()

func handle_event(event: InputEvent) -> bool:
 if not visible: return false
 # Modal deliberately consumes all routed events, not only recognized actions.
 if not _window_focused: return true
 var token := ""
 if event is InputEventKey:
  var key: int = event.physical_keycode if event.physical_keycode else event.keycode
  token = "k:%d" % key
  if not event.pressed:
   _held.erase(token)
   return true
  if event.echo or _held.has(token): return true
  _held[token] = true
 elif event is InputEventJoypadButton:
  token = "j:%d:%d" % [event.device, event.button_index]
  if not event.pressed:
   _held.erase(token)
   return true
  if _held.has(token): return true
  _held[token] = true
 var profile: Variant = host.get("input_profile") if is_instance_valid(host) else null
 var action := str(profile.action_for(event)) if profile != null and profile.has_method("action_for") else ""
 if action == "back" or (event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)):
  close()
  return true
 if action == "reset":
  reset_view()
  return true
 if action == "confirm":
  var focus := get_viewport().gui_get_focus_owner()
  if focus is Button and focus in _buttons and not focus.disabled: focus.pressed.emit()
  return true
 if not action.is_empty(): return true
 if event is InputEventKey:
  var code: int = event.physical_keycode if event.physical_keycode else event.keycode
  if profile == null and code == KEY_Z:
   close()
  elif profile == null and code == KEY_R: reset_view()
  elif code in [KEY_LEFT, KEY_PAGEUP]: navigate(-1)
  elif code in [KEY_RIGHT, KEY_PAGEDOWN]: navigate(1)
  elif code in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]: change_zoom(0.25)
  elif code in [KEY_MINUS, KEY_KP_SUBTRACT]: change_zoom(-0.25)
  elif code == KEY_UP:
   pan.y += 48
   _frame_page()
  elif code == KEY_DOWN:
   pan.y -= 48
   _frame_page()
  elif code == KEY_TAB: _cycle_focus(event.shift_pressed)
  elif code in [KEY_ENTER, KEY_SPACE]:
   var focus := get_viewport().gui_get_focus_owner()
   if focus is Button and focus in _buttons and not focus.disabled: focus.pressed.emit()
 elif event is InputEventJoypadButton:
  if profile == null and event.button_index == JOY_BUTTON_B: close()
  elif profile == null and event.button_index == JOY_BUTTON_RIGHT_STICK: reset_view()
  elif event.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_LEFT_SHOULDER]: navigate(-1)
  elif event.button_index in [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_RIGHT_SHOULDER]: navigate(1)
  elif event.button_index == JOY_BUTTON_DPAD_UP: change_zoom(0.25)
  elif event.button_index == JOY_BUTTON_DPAD_DOWN: change_zoom(-0.25)
 elif event is InputEventJoypadMotion:
  _handle_axis(event)
 elif event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_LEFT:
   if event.pressed:
    _clicked_button = _button_at(event.position)
    dragging = _clicked_button == null and _canvas.get_global_rect().has_point(event.position) and _image.texture != null
    if _clicked_button: _clicked_button.grab_focus()
   else:
    var clicked := _clicked_button
    cancel_drag()
    if is_instance_valid(clicked) and clicked == _button_at(event.position): clicked.pressed.emit()
  elif event.pressed and _canvas.get_global_rect().has_point(event.position):
   if event.button_index == MOUSE_BUTTON_WHEEL_UP: change_zoom(0.25)
   elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: change_zoom(-0.25)
 elif event is InputEventMouseMotion and dragging:
  if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
   if event.relative.is_finite(): pan += event.relative.limit_length(8192)
   _frame_page()
  else: cancel_drag()
 return true

func _handle_axis(event: InputEventJoypadMotion) -> void:
 if not is_finite(event.axis_value): return
 var value := clampf(event.axis_value, -1, 1)
 var key := "%d:%d" % [event.device, event.axis]
 if absf(value) < 0.22: _axis_ready[key] = true
 if not _axis_ready.get(key, false): return
 if event.axis == JOY_AXIS_LEFT_X:
  if absf(value) < 0.22: _axis_latched = false
  elif absf(value) > 0.65 and not _axis_latched:
   navigate(1 if value > 0 else -1)
   _axis_latched = true
   _axis_ready[key] = true
 elif event.axis == JOY_AXIS_RIGHT_X: pan_axis.x = value if absf(value) > 0.22 else 0.0
 elif event.axis == JOY_AXIS_RIGHT_Y: pan_axis.y = value if absf(value) > 0.22 else 0.0
 elif event.axis == JOY_AXIS_TRIGGER_LEFT:
  _trigger_values.x = maxf(value, 0) if absf(value) > 0.22 else 0.0
  zoom_axis = _trigger_values.y - _trigger_values.x
 elif event.axis == JOY_AXIS_TRIGGER_RIGHT:
  _trigger_values.y = maxf(value, 0) if absf(value) > 0.22 else 0.0
  zoom_axis = _trigger_values.y - _trigger_values.x
