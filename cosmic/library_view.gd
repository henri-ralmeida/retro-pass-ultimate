extends Control
## Local collection presentation and explicitly requested folder inventory.
## Never executes ROMs, emulation, automatic scans, or network scraping.
## Host owns the transition and routes input here before its system selector.
signal exit_requested

const InputGlyph = preload("res://cosmic/input_glyph.gd")
const GameBox = preload("res://cosmic/game_box.gd")
const BoxPresentation = preload("res://cosmic/box_presentation.gd")
const CatalogWindow = preload("res://cosmic/library_window.gd")
const CatalogChoice = preload("res://cosmic/catalog_choice.gd")
const CatalogImport = preload("res://cosmic/catalog_import.gd")
var catalog_choice := CatalogChoice.new()
var catalog_visit_started := false
var catalog_window := CatalogWindow.new()
const DEFAULT_MANIFEST := "res://assets/local_box_art/manifest.json"
# Public checkout contains no proprietary sleeve artwork and never invents it.
var ITEMS: Array[Dictionary] = []
var manifest_path := ""
var scan_button: Button
var scan_dialog: FileDialog
var scan_thread: Thread
var scanner: RefCounted
var scan_mutex := Mutex.new()
var scan_cancelled := false
var carousel: Node3D
var neighbor_boxes: Array[Node3D] = []
var manual_framing_active := false
var manual_framing_for_open := false
var manual_framing_progress := 0.0
var manual_framing_from := 1.0
var manual_framing_to := 1.0
var manual_saved_zoom := -1.0
const MANUAL_FRAMING_SECONDS := 0.24
var manual_release_diagnostics: Array[Dictionary] = []
var manual_release: RefCounted
var manual_release_progress := 0.0
var manual_release_direction := 0
var manual_release_teardown := false
const MANUAL_RELEASE_DURATION := 0.85
var manual_reader: Control
var manual_button: Button
var item_wheel: TextureRect
var manual_status := "Manual indisponível para este jogo."
var source_inventory_display := false

func _load_items(path_override: String = "") -> void:
 ITEMS.clear()
 manifest_path = path_override if not path_override.is_empty() else OS.get_environment("RETROPASS_BOX_ART_MANIFEST")
 if manifest_path.is_empty():
  manifest_path = "user://collection_catalog.json" if FileAccess.file_exists("user://collection_catalog.json") else DEFAULT_MANIFEST
 if FileAccess.file_exists(manifest_path):
  var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
  if parsed is Dictionary and parsed.get("items") is Array:
   var seen := {}
   for raw in parsed.items:
    if not raw is Dictionary: continue
    var id := str(raw.get("id", ""))
    if id.is_empty() or seen.has(id): continue
    seen[id] = true
    var data: Dictionary = raw.duplicate(true)
    data["title"] = str(data.get("title", id))
    data["subtitle"] = str(data.get("subtitle", "MASTER SYSTEM"))
    data["accent"] = str(data.get("accent", "9dd8f2"))
    data["description"] = str(data.get("description", "Capa do acervo local. Frente, lombada e verso independentes."))
    for field in ["cover_front", "cover_spine", "cover_back", "cover_edge", "cartridge_label", "cartridge_top", "wheel", "model_path", "uv_path", "art_root"]:
     var key: String = field
     if key in ["model_path", "uv_path"] and str(data.get(key, "")).is_empty():
      data.erase(key)
      continue
     var path := str(data.get(key, ""))
     if not path.is_empty() and not path.is_absolute_path(): path = manifest_path.get_base_dir().path_join(path)
     data[key] = path
    var pages: Variant = data.get("manual_pages", [])
    var resolved_pages: Array[String] = []
    if pages is Array:
     # Preserve an over-limit sentinel so the reader rejects rather than truncates.
     for page in pages.slice(0,129):
      var page_path := str(page) if page is String else ""
      if not page_path.is_empty() and not page_path.is_absolute_path(): page_path = manifest_path.get_base_dir().path_join(page_path)
      resolved_pages.append(page_path)
    data["manual_pages"] = resolved_pages
    ITEMS.append(data)
 if ITEMS.is_empty():
  ITEMS.append({"id":"unavailable", "title":"Acervo indisponível", "subtitle":"MASTER SYSTEM · SEM CAPAS LOCAIS", "accent":"9dd8f2", "description":"Nenhuma capa local disponível. A caixa permanece sem arte, sem substituições fictícias."})

 CatalogImport.apply_inventory_subtitles(ITEMS)
 catalog_choice.update_catalog(ITEMS)

func begin_catalog_visit() -> void:
 # A visit starts explicitly, never from redraw, focus, inspection or Back.
 catalog_choice.update_catalog(ITEMS)
 catalog_choice.end_visit()
 catalog_choice.begin_visit()
 catalog_visit_started = true
 var chosen := catalog_choice.get_selected_index()
 if chosen >= 0: _select(chosen)

const BOX_BOUNDS := AABB(Vector3(-0.87,-1.22,-0.15),Vector3(1.74,2.44,0.30))
const DEFAULT_YAW := 0.40
const DEFAULT_PITCH := -0.07
const ZOOM_MIN := 0.70
const ZOOM_MAX := 1.40
const APPROACH_SECONDS := 0.66

# Both motion tracks are caller-driven. There are no delayed tween callbacks
# that can reopen a closed library or consume elapsed time while unfocused.
var presentation := BoxPresentation.new()
var approach_progress := 0.0
var approach_target := 0.0
var approach_busy: bool:
 get: return approach_progress != approach_target
var returning_to_carousel := false
var pending_confirm := false
var carousel_yaw := DEFAULT_YAW
var carousel_pitch := DEFAULT_PITCH
var return_yaw := DEFAULT_YAW
var return_pitch := DEFAULT_PITCH
var presentation_rotation_active := false
var presentation_from := Vector2.ZERO
var presentation_to := Vector2.ZERO

var host: Node
var current_index := 0
var inspect_mode := false
var dragging := false
var yaw := DEFAULT_YAW
var pitch := DEFAULT_PITCH
var zoom := 1.0
var axis_navigation_held := false
var rotate_axis := Vector2.ZERO
var zoom_axis := 0.0
var viewport_container: SubViewportContainer
var viewport: SubViewport
var camera: Camera3D
var pivot: Node3D
var box: Node3D
var model_bounds := BOX_BOUNDS
var heading: Label
var disclosure: Label
var chapter: Label
var item_title: Label
var item_subtitle: Label
var description: Label
var collection_label: Label
var position_label: Label
var mode_label: Label
var help_label: Label
var legal_label: Label
var footer: HBoxContainer
var confirm_button: Button
var zoom_controls: HBoxContainer
var zoom_label: Label
var inspect_button: Button
var reset_button: Button
var motion_button: Button
var back_button: Button
var previous_button: Button
var next_button: Button
var cards: Array[Button] = []
var card_textures: Array[TextureRect] = []
var all_buttons: Array[Button] = []
var built := false
var layout_size := Vector2.ZERO
var controls_stamp := ""
var orbitron: Font = preload("res://assets/fonts/Orbitron.ttf")
var chakra: Font = preload("res://assets/fonts/ChakraPetch-Regular.ttf")

func configure(owner_node: Node) -> void:
 host = owner_node
 if host.get("orbitron") is Font: orbitron = host.orbitron
 if host.get("chakra") is Font: chakra = host.chakra
 if is_inside_tree(): _build()

func _ready() -> void:
 name = "ConceptLibrary"
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 visible = false
 _build()

func _build() -> void:
 if built or not is_instance_valid(host): return
 built = true
 _load_items()
 _build_world()
 heading = _label("MASTER SYSTEM  /  BIBLIOTECA",orbitron,17,Color("dedeea"))
 disclosure = _label("Acervo local · sem execução",chakra,15,Color("a8b9d3"))
 chapter = _label("01  /  ACERVO LOCAL",chakra,14,Color("9dd8f2"))
 item_title = _label("",orbitron,28,Color("f5f1ff"))
 item_title.clip_text = true
 item_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 item_wheel = TextureRect.new()
 item_wheel.name = "SelectedGameWheel"
 item_wheel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 item_wheel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 item_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(item_wheel)
 item_subtitle = _label("",chakra,16,Color("bdc5de"))
 item_subtitle.clip_text = true
 item_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 description = _label("",chakra,18,Color("b0b6ce"))
 description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 collection_label = _label("COLEÇÃO",chakra,12,Color("828da9"))
 position_label = _label("01  /  02",orbitron,14,Color("d5dbee"))
 position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 mode_label = _label("",chakra,12,Color("8995b2"))
 mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 help_label = _label("←  →  mudar de capa     ·     Inspecionar para girar a caixa",chakra,14,Color("a5aec7"))
 help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 legal_label = _label("Artes e marcas pertencem aos seus titulares. Capas carregadas localmente. Nenhum jogo incluído.",chakra,11,Color("77839e"))
 legal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 for node in [heading,disclosure,chapter,item_title,item_subtitle,description,collection_label,position_label,mode_label,help_label,legal_label]: add_child(node)
 previous_button = _plain_button("‹","Capa anterior",func(): navigate(-1))
 next_button = _plain_button("›","Próxima capa",func(): navigate(1))
 scan_button = _plain_button("Adicionar pasta","Escolher pasta local e atualizar catálogo",_choose_scan_folder)
 add_child(scan_button)
 scan_dialog = FileDialog.new()
 scan_dialog.title = "Escolha a pasta local de jogos"
 scan_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
 scan_dialog.access = FileDialog.ACCESS_FILESYSTEM
 scan_dialog.use_native_dialog = true
 scan_dialog.size = Vector2i(760,480)
 scan_dialog.dir_selected.connect(_scan_folder)
 add_child(scan_dialog)
 for button in [previous_button,next_button]:
  button.add_theme_font_size_override("font_size",32)
  add_child(button)
 for index in mini(ITEMS.size(),CatalogWindow.MAX_CARD_SLOTS): _build_card(index)
 footer = HBoxContainer.new()
 footer.alignment = BoxContainer.ALIGNMENT_CENTER
 footer.add_theme_constant_override("separation",14)
 footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(footer)
 confirm_button = _mapped_button("confirm","Abrir","Abrir a caixa e apresentar seu cartucho",confirm_selected)
 inspect_button = _mapped_button("inspect","Inspecionar","Girar a caixa em 3D, ver a lombada e o verso",toggle_inspection)
 reset_button = _mapped_button("reset","Restaurar","Restaurar o ângulo e o zoom da caixa",reset_inspection)
 motion_button = _mapped_button("motion","Pausar","Reduzir o movimento do fundo cósmico",_toggle_motion)
 back_button = _mapped_button("back","Voltar","Voltar ao Master System",go_back)
 manual_button = _mapped_button("confirm","Manual","Ler o manual deste jogo",_open_manual)
 for state in ["normal","hover","pressed","disabled"]: manual_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
 manual_button.custom_minimum_size = Vector2(132,46)
 for button in [confirm_button,inspect_button,reset_button,manual_button,motion_button,back_button]: footer.add_child(button)
 manual_reader = load("res://cosmic/manual_book_reader.gd").new()
 add_child(manual_reader)
 manual_reader.configure(host)
 manual_reader.closed.connect(_manual_closed)
 zoom_controls = HBoxContainer.new()
 zoom_controls.alignment = BoxContainer.ALIGNMENT_CENTER
 zoom_controls.add_theme_constant_override("separation",4)
 zoom_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(zoom_controls)
 var zoom_out := _plain_button("−","Afastar caixa",func(): zoom_inspection(-0.10))
 var zoom_in := _plain_button("+","Aproximar caixa",func(): zoom_inspection(0.10))
 for button in [zoom_out,zoom_in]: button.custom_minimum_size = Vector2(36,34)
 zoom_label = _label("100%",chakra,14,Color("d7deee"))
 zoom_label.custom_minimum_size = Vector2(50,34)
 zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
 zoom_controls.add_child(zoom_out)
 zoom_controls.add_child(zoom_label)
 zoom_controls.add_child(zoom_in)
 _select(0)
 layout()

func _build_world() -> void:
 viewport_container = SubViewportContainer.new()
 viewport_container.name = "Library3DViewport"
 viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
 viewport_container.stretch = true
 add_child(viewport_container)
 viewport = SubViewport.new()
 viewport.name = "Library3D"
 viewport.transparent_bg = true
 viewport.handle_input_locally = false
 viewport.own_world_3d = true
 viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 viewport.msaa_3d = Viewport.MSAA_2X
 viewport_container.add_child(viewport)
 var world := Node3D.new()
 viewport.add_child(world)
 var environment := WorldEnvironment.new()
 var settings := Environment.new()
 settings.background_mode = Environment.BG_COLOR
 settings.background_color = Color(0,0,0,0)
 settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 settings.ambient_light_color = Color("d3dcff")
 settings.ambient_light_energy = 0.75
 settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 environment.environment = settings
 world.add_child(environment)
 var key := DirectionalLight3D.new()
 key.rotation_degrees = Vector3(-22,-28,0)
 key.light_color = Color("fff3e1")
 key.light_energy = 1.5
 world.add_child(key)
 var fill := DirectionalLight3D.new()
 fill.rotation_degrees = Vector3(12,148,0)
 fill.light_color = Color("9ec5ff")
 fill.light_energy = 1.0
 world.add_child(fill)
 pivot = Node3D.new()
 pivot.name = "BoxInspectionPivot"
 world.add_child(pivot)
 carousel = Node3D.new()
 carousel.name = "PerspectiveCarousel"
 world.add_child(carousel)
 camera = Camera3D.new()
 camera.projection = Camera3D.PROJECTION_PERSPECTIVE
 camera.fov = 32.0
 camera.keep_aspect = Camera3D.KEEP_HEIGHT
 camera.near = 0.01
 camera.far = 20.0
 camera.position = Vector3(0,0,8)
 camera.current = true
 world.add_child(camera)
 camera.look_at(Vector3.ZERO)

func _label(value: String, font: Font, px: int, color: Color) -> Label:
 var label := Label.new()
 label.text = value
 label.add_theme_font_override("font",font)
 label.add_theme_font_size_override("font_size",px)
 label.add_theme_color_override("font_color",color)
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 return label

func _panel_style(fill: Color, stroke: Color, radius: int = 9) -> StyleBoxFlat:
 var style := StyleBoxFlat.new()
 style.bg_color = fill
 style.border_color = stroke
 style.set_border_width_all(1)
 style.set_corner_radius_all(radius)
 style.content_margin_left = 12
 style.content_margin_right = 12
 style.content_margin_top = 7
 style.content_margin_bottom = 7
 return style

func _decorate_button(button: Button) -> void:
 button.add_theme_stylebox_override("normal",_panel_style(Color(0.045,0.065,0.12,0.70),Color(0.42,0.55,0.75,0.23)))
 button.add_theme_stylebox_override("hover",_panel_style(Color(0.08,0.14,0.23,0.90),Color("6e9bbe")))
 button.add_theme_stylebox_override("pressed",_panel_style(Color(0.12,0.22,0.32,0.94),Color("a8daef")))
 button.add_theme_stylebox_override("focus",_panel_style(Color(0,0,0,0),Color("a9ddef")))
 button.add_theme_font_override("font",chakra)
 button.add_theme_font_size_override("font_size",15)
 button.add_theme_color_override("font_color",Color("dbe4f3"))
 button.focus_mode = Control.FOCUS_ALL
 if button not in all_buttons: all_buttons.append(button)

func _plain_button(value: String, accessible: String, callback: Callable) -> Button:
 var button := Button.new()
 button.text = value
 button.accessibility_name = accessible
 button.tooltip_text = accessible
 button.custom_minimum_size = Vector2(42,42)
 button.pressed.connect(callback)
 _decorate_button(button)
 return button

func _mapped_button(action: String, value: String, tip: String, callback: Callable) -> Button:
 var button: Button
 if host.has_method("_action_button"):
  button = host._action_button(action,value,tip,callback)
 else:
  button = _plain_button(value,value,callback)
  button.set_meta("action",action)
  var glyph := InputGlyph.new()
  glyph.name = "InputGlyph"
  glyph.position = Vector2(8,8)
  button.add_child(glyph)
  button.custom_minimum_size = Vector2(148,46)
 _decorate_button(button)
 # Keep the accepted contextual keycap/text footer, not large panels.
 for state in ["normal","hover","pressed","disabled"]:
  button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
 var focus_line := StyleBoxFlat.new()
 focus_line.bg_color = Color(0,0,0,0)
 focus_line.border_color = Color("91bddf")
 focus_line.border_width_bottom = 1
 button.add_theme_stylebox_override("focus",focus_line)
 button.name = "Library" + action.capitalize()
 return button

func _build_card(index: int) -> void:
 var data: Dictionary = ITEMS[index]
 var button := _plain_button("","Selecionar caixa: " + str(data.title),func(): _activate_card(index))
 button.set_meta("catalog_index",index)
 button.name = "LibraryCard" + str(index)
 button.alignment = HORIZONTAL_ALIGNMENT_LEFT
 add_child(button)
 cards.append(button)
 var image := TextureRect.new()
 image.name = "CoverThumbnail"
 image.mouse_filter = Control.MOUSE_FILTER_IGNORE
 image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 image.position = Vector2(11,8)
 image.size = Vector2(43,61)
 button.add_child(image)
 card_textures.append(image)
 var title_label := _label(data.title,chakra,18,Color("e5e9f5"))
 title_label.name = "CardTitle"
 title_label.clip_text = true
 title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 title_label.position = Vector2(67,13)
 button.add_child(title_label)
 var subtitle_label := _label(data.subtitle,chakra,11,Color("a4b1cc"))
 subtitle_label.name = "CardSubtitle"
 subtitle_label.position = Vector2(68,40)
 button.add_child(subtitle_label)
 var number := _label("0" + str(index+1),orbitron,12,Color(data.accent))
 number.name = "CardNumber"
 number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 button.add_child(number)

func _activate_card(slot: int) -> void:
 if slot >= 0 and slot < cards.size(): _select(int(cards[slot].get_meta("catalog_index",-1)))

func _sync_card_window() -> void:
 var focused := get_viewport().gui_get_focus_owner()
 var focused_index := int(focused.get_meta("catalog_index",-1)) if focused in cards else -1
 if catalog_window.count != ITEMS.size(): catalog_window.configure(ITEMS.size(),current_index)
 else: catalog_window.select_index(current_index)
 var retained_focus: Button
 var selected_card: Button
 for entry in catalog_window.card_slots():
  var card := cards[int(entry.slot)]
  var data: Dictionary = ITEMS[int(entry.index)]
  card.set_meta("catalog_index",int(entry.index))
  var label := str(data.title) + (" · " + str(data.subtitle) if CatalogImport.is_source_inventory(data) else "")
  card.accessibility_name = "Selecionar caixa: " + label
  card.tooltip_text = label
  if CatalogImport.is_source_inventory(data): card.tooltip_text += "\nVariante do arquivo ou região indicada no inventário; identificação não verificada."
  card.get_node("CardTitle").text = str(data.title)
  card.get_node("CardSubtitle").text = str(data.subtitle)
  card.get_node("CardNumber").text = "%02d" % (int(entry.index)+1)
  if entry.index == focused_index: retained_focus = card
  if entry.index == current_index: selected_card = card
 if focused_index >= 0:
  if retained_focus: retained_focus.grab_focus()
  elif selected_card: selected_card.grab_focus()

func _cancel_scan() -> void:
 scan_mutex.lock()
 scan_cancelled = true
 scan_mutex.unlock()

func _scan_was_cancelled() -> bool:
 scan_mutex.lock()
 var value := scan_cancelled
 scan_mutex.unlock()
 return value

func _choose_scan_folder() -> void:
 if scan_thread != null:
  _cancel_scan()
  disclosure.text = "Cancelando leitura… catálogo anterior preservado"
  return
 cancel_drag()
 scan_dialog.popup_centered()

func _scan_folder(folder: String) -> void:
 if scan_thread != null: return
 var script = load("res://cosmic/collection_scan.gd")
 if script == null:
  disclosure.text = "Scanner indisponível. Nenhum catálogo alterado."
  return
 scanner = script.new()
 scan_mutex.lock()
 scan_cancelled = false
 scan_mutex.unlock()
 scan_button.text = "Cancelar leitura"
 disclosure.text = "Lendo pasta local… nenhuma busca online configurada"
 scan_thread = Thread.new()
 var error := scan_thread.start(func(): return scanner.scan_folder(folder, {"cancelled":_scan_was_cancelled}))
 if error != OK:
  scan_thread = null
  scan_button.text = "Adicionar pasta"
  disclosure.text = "Não foi possível iniciar a leitura da pasta."

func _finish_scan() -> void:
 var result: Dictionary = scan_thread.wait_to_finish()
 scan_thread = null
 scan_button.text = "Adicionar pasta"
 if result.get("status", "error") != "ok":
  disclosure.text = "Leitura não concluída. Catálogo anterior preservado."
  return
 if result.get("items", []).is_empty():
  disclosure.text = "Nenhum jogo compatível encontrado. Catálogo anterior preservado."
  return
 var saved: int = scanner.save_catalog(result)
 if saved != OK:
  disclosure.text = "Não foi possível salvar o catálogo. Acervo anterior preservado."
  return
 for card in cards:
  all_buttons.erase(card)
  remove_child(card)
  card.queue_free()
 cards.clear()
 card_textures.clear()
 _load_items("user://collection_catalog.json")
 for index in mini(ITEMS.size(),CatalogWindow.MAX_CARD_SLOTS): _build_card(index)
 inspect_mode = false
 begin_catalog_visit()
 disclosure.text = "%d entradas locais · ScreenScraper não configurado · sem execução" % ITEMS.size()
 if not result.get("warnings", []).is_empty():
  disclosure.text += " · %d avisos" % result.warnings.size()
  disclosure.tooltip_text = "\n".join(result.warnings)
 layout()
 scan_button.grab_focus()

func _exit_tree() -> void:
 _reset_manual_release(false)
 presentation.teardown()
 if scan_thread != null:
  _cancel_scan()
  scan_thread.wait_to_finish()
  scan_thread = null

func open() -> void:
 _build()
 if not built: return
 visible = true
 _reset_presentation()
 cancel_drag()
 reset_inspection()
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 refresh_controls()
 layout()
 confirm_button.grab_focus()

func close() -> void:
 _reset_manual_release()
 if scan_dialog: scan_dialog.hide()
 cancel_drag()
 _reset_presentation()
 visible = false
 if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func navigate(direction: int) -> void:
 if inspect_mode or approach_busy or not visible: return
 var held := axis_navigation_held
 _select(posmod(current_index + direction,ITEMS.size()))
 axis_navigation_held = held

func _select(index: int) -> void:
 if inspect_mode or approach_busy or index < 0 or index >= ITEMS.size(): return
 _reset_manual_release()
 presentation.teardown()
 current_index = index
 if catalog_visit_started: catalog_choice.select_explicit(str(ITEMS[index].get("id", "")))
 var data: Dictionary = ITEMS[index]
 if box:
  pivot.remove_child(box)
  box.queue_free()
 var box_script = load("res://cosmic/game_box.gd")
 if box_script:
  box = box_script.new()
  box.configure(data)
  pivot.add_child(box)
  if box.has_method("get_local_bounds"): model_bounds = box.get_local_bounds()
  presentation.configure(box)
 _refresh_manual_availability(data)
 item_title.text = data.title
 item_wheel.texture = GameBox.load_artwork(data.get("wheel",null),512)
 item_wheel.accessibility_name = "Logo local: " + str(data.title)
 item_wheel.tooltip_text = str(data.title)
 item_title.tooltip_text = data.title
 item_title.accessibility_name = data.title
 item_subtitle.text = data.subtitle
 item_subtitle.tooltip_text = data.subtitle
 description.text = data.description
 var from_inventory := CatalogImport.is_source_inventory(data)
 chapter.text = "%02d  /  %s" % [index+1, "INVENTÁRIO DE ORIGEM" if from_inventory else "ACERVO LOCAL"]
 if scan_thread == null and (from_inventory or source_inventory_display != from_inventory):
  disclosure.text = "Inventário de origem · presença local não verificada · sem execução" if from_inventory else "Acervo local · sem execução"
  disclosure.tooltip_text = ""
 source_inventory_display = from_inventory
 if from_inventory:
  item_title.tooltip_text += "\n" + str(data.subtitle)
  item_title.accessibility_name += " · " + str(data.subtitle)
 chapter.add_theme_color_override("font_color",Color(data.accent))
 position_label.text = "%02d  /  %02d" % [index+1,ITEMS.size()] if not ITEMS.is_empty() and str(ITEMS[index].get("id","")) != "unavailable" else "00  /  00"
 _sync_card_window()
 for card_index in cards.size():
  var card := cards[card_index]
  var active := int(card.get_meta("catalog_index",-1)) == current_index
  card.add_theme_stylebox_override("normal",_panel_style(Color(0.075,0.14,0.22,0.85) if active else Color(0.04,0.06,0.12,0.66),Color("709ebd") if active else Color(0.42,0.55,0.75,0.23)))
  card.accessibility_description = "Capa selecionada" if active else "Outra caixa do catálogo"
 _refresh_card_textures()
 _build_neighbors()
 reset_inspection()
 layout()

func _refresh_card_textures() -> void:
 # These compact title tabs never display thumbnails. Do not decode hidden
 # images: the selected real box already owns the visible artwork.
 for image in card_textures: image.texture = null
 var missing: Array[String] = []
 for face in ["front", "spine", "back"]:
  if GameBox.load_artwork(ITEMS[current_index].get("cover_" + face, null)) == null:
   missing.append({"front":"frente", "spine":"lombada", "back":"verso"}[face])
 description.text = "Capa indisponível" if missing.size() == 3 else ("Arte parcial" if not missing.is_empty() else "")
 description.tooltip_text = "Arte indisponível: " + ", ".join(missing) if not missing.is_empty() else ""
 if str(ITEMS[current_index].get("file_status","")) == "missing":
  description.text = "Arquivo ausente no inventário"
  description.tooltip_text = "Registro preservado para consulta, excluído do sorteio. " + description.tooltip_text

func _build_neighbors() -> void:
 for node in neighbor_boxes:
  carousel.remove_child(node)
  node.queue_free()
 neighbor_boxes.clear()
 # One real entry is one box. Never duplicate it to fake a larger collection.
 var used := {current_index:true}
 for offset in [-1, 1, -2, 2]:
  var index := posmod(current_index + offset, ITEMS.size())
  if used.has(index): continue
  used[index] = true
  var neighbor := GameBox.new()
  var neighbor_data: Dictionary = ITEMS[index].duplicate(true)
  neighbor_data["_runtime_art_max_side"] = GameBox.ArtworkCache.NEIGHBOR_MAX_SIDE
  neighbor.configure(neighbor_data)
  carousel.add_child(neighbor)
  var side := signf(float(offset))
  neighbor.position = Vector3(side * (2.05 + (abs(offset)-1)*1.25), -0.12, -1.25 - (abs(offset)-1)*0.9)
  neighbor.set_meta("carousel_position", neighbor.position)
  neighbor.rotation.y = -side * 0.65
  neighbor.scale = Vector3.ONE * 0.86
  neighbor_boxes.append(neighbor)
 carousel.visible = true

func _can_interact() -> bool:
 return not manual_framing_active and manual_release_direction == 0 and visible and built and host.get("application_focused") != false and host.get("scene_active") != false and not scan_dialog.visible

func _reduced_motion() -> bool:
 return host.get("reduced_motion") == true

func toggle_inspection() -> void:
 if not _can_interact(): return
 if inspect_mode:
  go_back()
 else:
  _begin_inspection()

func _begin_inspection() -> void:
 cancel_drag()
 if not inspect_mode:
  carousel_yaw = yaw
  carousel_pitch = pitch
  inspect_mode = true
 returning_to_carousel = false
 approach_target = 1.0
 if _reduced_motion(): approach_progress = approach_target
 _update_inspection_view()
 confirm_button.grab_focus()

func confirm_selected() -> void:
 if not _can_interact() or not presentation.available: return
 pending_confirm = true
 _begin_inspection()
 if not approach_busy:
  _start_presentation(_reduced_motion())
  pending_confirm = false
  _update_inspection_view()

func _start_presentation(reduced: bool) -> void:
 if presentation.progress == 0.0 and not presentation_rotation_active:
  # Derive a view of BOTH interior planes from the original rig. This is not
  # an inspection face preset: only explicit Confirm requests this orientation.
  var source_basis: Basis = box.global_basis.inverse() * box.lid.get_parent().global_basis
  var base_normal := (source_basis * Vector3.UP).normalized()
  var open_lid_inside := (source_basis * (Basis(Vector3.BACK,deg_to_rad(BoxPresentation.OPEN_DEGREES)) * Vector3.DOWN)).normalized()
  var bisector := (base_normal + open_lid_inside).normalized()
  presentation_from = Vector2(yaw,pitch)
  presentation_to = Vector2(-atan2(bisector.x,Vector2(bisector.y,bisector.z).length()),atan2(bisector.y,bisector.z))
  presentation_rotation_active = true
 presentation.confirm(reduced)
 _apply_presentation_orientation()

func _apply_presentation_orientation() -> void:
 if not presentation_rotation_active: return
 var weight := presentation.lid_angle / BoxPresentation.OPEN_DEGREES
 yaw = lerp_angle(presentation_from.x,presentation_to.x,weight)
 pitch = lerp_angle(presentation_from.y,presentation_to.y,weight)
 pivot.basis = Basis(Vector3.UP,yaw) * Basis(Vector3.RIGHT,pitch)

func _toggle_motion() -> void:
 if host.has_method("toggle_motion"): host.toggle_motion()
 if _reduced_motion(): _advance_presentation(0.0)
 refresh_controls()

func go_back() -> void:
 if manual_framing_active:
  _start_manual_framing(manual_saved_zoom if manual_saved_zoom > 0 else manual_framing_from,false)
  return
 if manual_release_direction != 0:
  if is_instance_valid(manual_release): manual_release.begin_return()
  manual_release_direction = -1
  if _reduced_motion(): _advance_manual_release(0.0)
  return
 if is_instance_valid(manual_reader) and manual_reader.visible:
  manual_reader.close()
  return
 if not _can_interact(): return
 if inspect_mode:
  # Repeated Back remains within this path until everything is safely stowed.
  if returning_to_carousel: return
  cancel_drag()
  pending_confirm = false
  returning_to_carousel = true
  presentation.back(_reduced_motion())
  return_yaw = yaw
  return_pitch = pitch
  if presentation.progress == 0.0: approach_target = 0.0
  _advance_presentation(0.0)
 else:
  cancel_drag()
  exit_requested.emit()

func _reset_presentation() -> void:
 presentation.reset()
 inspect_mode = false
 approach_progress = 0.0
 approach_target = 0.0
 returning_to_carousel = false
 pending_confirm = false
 presentation_rotation_active = false

func _update_inspection_view() -> void:
 if box: model_bounds = box.get_local_bounds()
 layout()

func _advance_presentation(delta: float) -> void:
 if not _can_interact():
  cancel_drag()
  return
 if not is_finite(delta) or delta < 0.0: return
 var reduced := _reduced_motion()
 var remaining := delta
 # Finish stowing before withdrawing the camera; no orphaned cartridge.
 if returning_to_carousel:
  if reduced: presentation.back(true)
  else:
   var stow_seconds := presentation.progress * BoxPresentation.TOTAL_SECONDS
   presentation.tick(remaining, true)
   remaining = maxf(0.0, remaining - stow_seconds)
  _apply_presentation_orientation()
  if presentation.progress == 0.0 and approach_target != 0.0:
   return_yaw = yaw
   return_pitch = pitch
   approach_target = 0.0
 if reduced: approach_progress = approach_target
 else:
  var approach_seconds := absf(approach_target - approach_progress) * APPROACH_SECONDS
  approach_progress = move_toward(approach_progress, approach_target, remaining / APPROACH_SECONDS)
  remaining = maxf(0.0, remaining - approach_seconds)
 if returning_to_carousel and approach_target == 0.0:
  # Return to the actual departure pose, never to an arbitrary face preset.
  var weight := BoxPresentation._ease(approach_progress)
  yaw = lerp_angle(carousel_yaw, return_yaw, weight)
  pitch = lerp_angle(carousel_pitch, return_pitch, weight)
  pivot.basis = Basis(Vector3.UP,yaw) * Basis(Vector3.RIGHT,pitch)
 if approach_progress == 1.0 and not returning_to_carousel:
  if pending_confirm:
   _start_presentation(reduced)
   pending_confirm = false
  if reduced and presentation.busy:
   if presentation.state in [&"closing", &"returning"]: presentation.back(true)
   else: presentation.confirm(true)
  elif remaining > 0.0: presentation.tick(remaining, true)
  _apply_presentation_orientation()
 if returning_to_carousel and approach_progress == 0.0 and presentation.progress == 0.0:
  inspect_mode = false
  returning_to_carousel = false
  presentation_rotation_active = false
  yaw = carousel_yaw
  pitch = carousel_pitch
  zoom = 1.0
  pivot.basis = Basis(Vector3.UP,yaw) * Basis(Vector3.RIGHT,pitch)
  confirm_button.grab_focus()
 _update_inspection_view()

func reset_inspection() -> void:
 if manual_framing_active or manual_release_direction != 0: return
 cancel_drag()
 if returning_to_carousel or approach_busy: return
 presentation_rotation_active = false
 if box:
  presentation.back(_reduced_motion())
  model_bounds = box.get_local_bounds()
 yaw = DEFAULT_YAW
 pitch = DEFAULT_PITCH
 zoom = 1.0
 _apply_rotation()

func rotate_inspection(relative: Vector2) -> void:
 if manual_framing_active or manual_release_direction != 0: return
 if not inspect_mode or approach_busy or returning_to_carousel: return
 presentation_rotation_active = false
 yaw = wrapf(yaw + relative.x * 0.008,-PI,PI)
 pitch = wrapf(pitch + relative.y * 0.008,-PI,PI)
 _apply_rotation()

func zoom_inspection(amount: float) -> void:
 if manual_framing_active or manual_release_direction != 0: return
 if not inspect_mode or approach_busy or returning_to_carousel: return
 zoom = clampf(zoom+amount,ZOOM_MIN,ZOOM_MAX)
 _frame_box()

func cancel_drag() -> void:
 if is_instance_valid(manual_reader): manual_reader.cancel_drag()
 dragging = false
 rotate_axis = Vector2.ZERO
 zoom_axis = 0.0
 axis_navigation_held = false
 if is_instance_valid(viewport_container): viewport_container.mouse_default_cursor_shape = Control.CURSOR_DRAG if inspect_mode else Control.CURSOR_ARROW

func _apply_rotation() -> void:
 if not pivot: return
 pivot.basis = Basis(Vector3.UP,yaw) * Basis(Vector3.RIGHT,pitch)
 _frame_box()

func _frame_box() -> void:
 if not camera or viewport_container.size.y <= 0.0: return
 var ratio := viewport_container.size.x/maxf(viewport_container.size.y,1.0)
 var tangent := tan(deg_to_rad(camera.fov)*0.5)
 var collection_distance := 0.0
 var inspect_distance := 0.0
 var points := PackedVector3Array()
 # A union AABB invents corners combining the cartridge's forward depth with
 # the open lid's distant edge. Fit the actual visible mesh bounds instead.
 var to_pivot := pivot.global_transform.affine_inverse()
 for mesh in box.find_children("*", "MeshInstance3D", true, false):
  if not mesh.mesh or not mesh.is_visible_in_tree(): continue
  var local_pose: Transform3D = to_pivot * mesh.global_transform
  for index in range(8):
   points.append(pivot.basis * (local_pose * mesh.get_aabb().get_endpoint(index)))
 if points.is_empty():
  for index in range(8): points.append(pivot.basis * model_bounds.get_endpoint(index))
 for point in points:
  var extent := maxf(absf(point.y),absf(point.x)/ratio) / tangent
  # Keep over 5% at maximum zoom. Collection is just far enough behind the
  # default inspection framing to retain a real, smooth forward approach.
  collection_distance = maxf(collection_distance, point.z + extent * 1.65)
  inspect_distance = maxf(inspect_distance, point.z + extent * 1.56 / zoom)
 if not neighbor_boxes.is_empty(): collection_distance = maxf(collection_distance, 3.35 / (tangent*ratio))
 var weight := BoxPresentation._ease(approach_progress)
 var distance := lerpf(collection_distance, inspect_distance, weight)
 camera.position = Vector3(0,0,maxf(distance,1.0))
 camera.far = maxf(30.0,distance+10.0)
 # Neighbors recede outside the view instead of popping out at entry.
 for neighbor in neighbor_boxes:
  var origin: Vector3 = neighbor.get_meta("carousel_position")
  neighbor.position = origin + Vector3(signf(origin.x) * 30.0 * weight, 0.0, 0.0)
 carousel.position.z = -2.0 * weight
 carousel.visible = approach_progress < 1.0
 if zoom_label: zoom_label.text = "%d%%" % roundi(zoom*100.0)

func refresh_controls() -> void:
 if not built: return
 var gamepad: bool = host.get("input_device") == "gamepad"
 var name_value: String = str(host.get("active_pad_name"))
 var profile = host.get("input_profile")
 for button in [confirm_button,inspect_button,reset_button,manual_button,motion_button,back_button]:
  var action: String = button.get_meta("action","")
  var glyph = button.find_child("InputGlyph",true,false)
  if glyph and profile:
   glyph.symbol = profile.glyph(action,gamepad,name_value)
   glyph.family = profile.family(name_value) if gamepad else "keyboard"
 var presented := presentation.state == &"presented" and not returning_to_carousel
 confirm_button.visible = not presented
 if is_instance_valid(manual_button):
  var became_available := presented and not manual_button.visible
  manual_button.visible = presented
  manual_button.disabled = not manual_status.is_empty()
  if became_available and not manual_button.disabled: manual_button.grab_focus()
 inspect_button.visible = not inspect_mode
 motion_button.visible = not inspect_mode
 confirm_button.disabled = not presentation.available
 var confirm_label = confirm_button.find_child("ActionLabel",true,false)
 var confirm_text := "Apresentado" if presentation.state == &"presented" else "Abrir"
 if confirm_label: confirm_label.text = confirm_text
 else: confirm_button.text = confirm_text
 confirm_button.accessibility_name = "Abrir caixa e apresentar seu cartucho"
 var action_label = inspect_button.find_child("ActionLabel",true,false)
 if action_label: action_label.text = "Voltar" if inspect_mode else "Inspecionar"
 else: inspect_button.text = "Voltar" if inspect_mode else "Inspecionar"
 inspect_button.accessibility_name = "Concluir inspeção" if inspect_mode else "Inspecionar caixa"
 back_button.accessibility_description = "Voltar à coleção" if inspect_mode else "Voltar ao Master System"
 var motion_label = motion_button.find_child("ActionLabel",true,false)
 if motion_label: motion_label.text = "Animar" if host.get("reduced_motion") == true else "Pausar"
 motion_button.accessibility_name = "Animar fundo" if host.get("reduced_motion") == true else "Pausar movimento do fundo"
 reset_button.visible = inspect_mode and not approach_busy and not returning_to_carousel
 zoom_controls.visible = inspect_mode and not returning_to_carousel
 help_label.text = "Arrastar / setas: girar · +/−: zoom" if inspect_mode else "←  →  selecionar jogo"
 if gamepad:
  help_label.text = "Analógico: girar · direito: zoom" if inspect_mode else "Direcional: selecionar jogo"
 mode_label.visible = false
 _refresh_focus()

func _refresh_focus() -> void:
 var available: Array[Button] = []
 for button in all_buttons:
  if button.is_visible_in_tree() and not button.disabled: available.append(button)
 for index in available.size():
  var previous := available[posmod(index-1,available.size())].get_path()
  var following := available[(index+1)%available.size()].get_path()
  available[index].focus_previous = previous
  available[index].focus_next = following
  available[index].focus_neighbor_left = previous
  available[index].focus_neighbor_right = following
  available[index].focus_neighbor_top = previous
  available[index].focus_neighbor_bottom = following

func _fit_title(label: Label, preferred: int, minimum: int) -> void:
 var font: Font = label.get_theme_font("font")
 var font_size := preferred
 while font_size > minimum and font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > label.size.x:
  font_size -= 1
 label.add_theme_font_size_override("font_size",font_size)

func layout() -> void:
 if not built or not is_inside_tree(): return
 var s := get_viewport().get_visible_rect().size
 layout_size = s
 var narrow := s.x < 900
 var margin := 24.0 if narrow else 40.0
 var header_y := 21.0
 heading.position = Vector2(margin,header_y)
 heading.add_theme_font_size_override("font_size",14 if narrow else 17)
 scan_button.position = Vector2(s.x-margin-134,20)
 scan_button.size = Vector2(134,42)
 disclosure.position = Vector2(margin,header_y+30)
 disclosure.add_theme_font_size_override("font_size",13 if narrow else 15)
 var title_y := s.y-222.0
 chapter.position = Vector2(margin,94)
 item_title.position = Vector2(margin,title_y)
 item_title.size = Vector2(s.x-margin*2,48)
 item_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 _fit_title(item_title,25 if narrow else 28,18)
 item_subtitle.position = Vector2(margin,title_y+44)
 item_subtitle.size = Vector2(s.x-margin*2,24)
 item_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 item_subtitle.add_theme_font_size_override("font_size",12 if narrow else 14)
 description.position = Vector2(margin,header_y+57)
 description.size = Vector2(s.x-margin*2,32)
 description.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 description.add_theme_font_size_override("font_size",11 if narrow else 12)
 description.visible = not inspect_mode
 collection_label.visible = false
 # The coverflow is the collection, not a flat card list. Compact title tabs
 # remain genuine pointer/focus targets for at most three adjacent entries.
 var visible_indices: Array[int] = []
 for entry in catalog_window.card_slots(): visible_indices.append(int(entry.slot))
 var card_width := minf(230.0,(s.x-margin*2)/visible_indices.size()-8.0)
 var row_width := visible_indices.size()*(card_width+8.0)-8.0
 for index in cards.size():
  cards[index].visible = not inspect_mode and ITEMS.size() > 1 and index in visible_indices
  var slot := visible_indices.find(index)
  cards[index].position = Vector2((s.x-row_width)*0.5+slot*(card_width+8),s.y-180)
  var from_inventory := CatalogImport.is_source_inventory(ITEMS[int(cards[index].get_meta("catalog_index",0))])
  cards[index].size = Vector2(card_width,48 if from_inventory else 34)
  cards[index].get_node("CardTitle").position = Vector2(10,4 if from_inventory else 7)
  var card_title: Label = cards[index].get_node("CardTitle")
  card_title.clip_text = true
  card_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  card_title.size = Vector2(card_width-20,22)
  card_title.add_theme_font_size_override("font_size",14)
  cards[index].get_node("CardNumber").visible = false
  card_textures[index].visible = false
  for child in cards[index].get_children():
   if child is Label and child.name != "CardTitle": child.visible = false
  var card_subtitle: Label = cards[index].get_node("CardSubtitle")
  card_subtitle.visible = from_inventory
  card_subtitle.position = Vector2(10,26)
  card_subtitle.size = Vector2(card_width-20,18)
  card_subtitle.clip_text = true
  card_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 var approach_weight := BoxPresentation._ease(approach_progress)
 viewport_container.position = Vector2(margin+24,lerpf(102.0,88.0,approach_weight))
 viewport_container.size = Vector2(s.x-margin*2-48,maxf(100,s.y-lerpf(324.0,292.0,approach_weight)))
 item_wheel.position = Vector2((s.x-minf(450.0,s.x-margin*2))*0.5,title_y)
 item_wheel.size = Vector2(minf(450.0,s.x-margin*2),42)
 item_wheel.visible = not inspect_mode and item_wheel.texture != null
 item_title.visible = not inspect_mode and item_wheel.texture == null
 item_subtitle.visible = not inspect_mode and ITEMS.size() == 1
 chapter.visible = not inspect_mode
 previous_button.visible = not inspect_mode and ITEMS.size() > 1
 next_button.visible = not inspect_mode and ITEMS.size() > 1
 previous_button.position = Vector2(margin,viewport_container.position.y+viewport_container.size.y*0.5-21)
 next_button.position = Vector2(s.x-margin-42,previous_button.position.y)
 previous_button.size = Vector2(42,48)
 next_button.size = Vector2(42,48)
 position_label.position = Vector2(s.x-130,94)
 position_label.size = Vector2(90,22)
 position_label.visible = not inspect_mode
 mode_label.visible = false
 mode_label.position = Vector2(0,88 if inspect_mode else s.y-151)
 mode_label.size = Vector2(s.x,24)
 zoom_controls.position = Vector2(s.x*0.5-64,s.y-187)
 zoom_controls.size = Vector2(128,38)
 help_label.position = Vector2(16,s.y-130)
 help_label.size = Vector2(s.x-32,24)
 help_label.add_theme_font_size_override("font_size",13 if narrow else 14)
 # Five contextual actions fit at supported narrow widths without clipping.
 for button in [confirm_button,inspect_button,reset_button,manual_button,motion_button,back_button]:
  button.custom_minimum_size.x = 132.0 if narrow else 144.0
  var label = button.find_child("ActionLabel",true,false)
  if label: label.add_theme_font_size_override("font_size",16 if narrow else 18)
 footer.add_theme_constant_override("separation",8 if narrow else 14)
 footer.position = Vector2(margin,s.y-96)
 footer.size = Vector2(s.x-margin*2.0,48)
 legal_label.position = Vector2(16,s.y-28)
 legal_label.size = Vector2(s.x-32,20)
 legal_label.visible = false
 disclosure.visible = not inspect_mode
 scan_button.visible = not inspect_mode
 refresh_controls()
 _frame_box()
 if is_instance_valid(manual_reader):
  manual_reader.move_to_front()
  manual_reader.layout()
 queue_redraw()

func _draw() -> void:
 if not built: return
 var s := layout_size
 var margin := 24.0 if s.x < 900 else 40.0
 draw_line(Vector2(margin,79),Vector2(s.x-margin,79),Color(0.65,0.76,0.96,0.13),1.0,true)
 draw_line(Vector2(margin,s.y-107),Vector2(s.x-margin,s.y-107),Color(0.65,0.76,0.96,0.13),1.0,true)
 if not inspect_mode:
  var center := viewport_container.position + viewport_container.size*Vector2(0.5,0.98)
  for index in range(3):
   var radius := 80.0+index*22.0
   var points := PackedVector2Array()
   for step in range(65):
    var angle := float(step)*TAU/64.0
    points.append(center+Vector2(cos(angle)*radius,sin(angle)*radius*0.13))
   draw_polyline(points,Color(0.52,0.72,0.96,0.12-float(index)*0.025),1.0,true)

func _activate_focused() -> void:
 var focused := get_viewport().gui_get_focus_owner()
 if focused is Button and is_ancestor_of(focused) and focused.is_visible_in_tree():
  if focused.disabled: return
  # Collection cards represent the selected game; other explicit UI controls
  # keep their normal confirm action (scanner, accessibility tools, manuals).
  if focused in cards:
   var index := int(focused.get_meta("catalog_index",-1))
   if index != current_index: _select(index)
   confirm_selected()
  else:
   focused.pressed.emit()
 else:
  confirm_selected()

func _move_focus(direction: int) -> void:
 var focused := get_viewport().gui_get_focus_owner()
 if focused and is_ancestor_of(focused):
  var target = focused.get_node_or_null(focused.focus_next if direction > 0 else focused.focus_previous)
  if target is Control: target.grab_focus(); return
 inspect_button.grab_focus()

func handle_event(event: InputEvent) -> bool:
 if not visible or not built: return false
 if is_instance_valid(manual_reader) and manual_reader.visible:
  if host.get("application_focused") == false or host.get("scene_active") == false:
   manual_reader.cancel_drag()
   return true
  return manual_reader.handle_event(event)
 if manual_framing_active or manual_release_direction != 0:
  cancel_drag()
  var release_profile = host.get("input_profile")
  if release_profile and release_profile.action_for(event) == "back": go_back()
  return true
 if scan_dialog.visible: return false
 if host.get("application_focused") == false or host.get("scene_active") == false:
  cancel_drag()
  return true
 refresh_controls()
 var profile = host.get("input_profile")
 var action: String = profile.action_for(event) if profile else ""
 if not action.is_empty():
  match action:
   "confirm": _activate_focused()
   "back": go_back()
   "inspect": toggle_inspection()
   "motion": _toggle_motion()
   "reset":
    if inspect_mode: reset_inspection()
  return true
 if event is InputEventKey and event.pressed and event.echo and profile:
  var code: int = event.physical_keycode if event.physical_keycode else event.keycode
  if code in profile.keys.values(): return true
  if event.keycode not in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN,KEY_EQUAL,KEY_PLUS,KEY_KP_ADD,KEY_MINUS,KEY_KP_SUBTRACT]: return true
 if event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
   var was_dragging := dragging
   dragging = false
   return was_dragging
  var inside := viewport_container.get_global_rect().has_point(event.position)
  for button in all_buttons:
   if button.is_visible_in_tree() and button.get_global_rect().has_point(event.position): inside = false
  if inspect_mode and not approach_busy and not returning_to_carousel and inside:
   if event.button_index == MOUSE_BUTTON_LEFT:
    dragging = event.pressed
    return true
   if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
    zoom_inspection(0.08 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.08)
    return true
 if event is InputEventMouseMotion and dragging:
  rotate_inspection(event.relative)
  return true
 if event is InputEventKey and event.pressed:
  match event.keycode:
   KEY_ESCAPE: go_back(); return true
   KEY_ENTER,KEY_KP_ENTER,KEY_SPACE:
    if not event.echo: _activate_focused()
    return true
   KEY_LEFT,KEY_RIGHT:
    var direction := -1 if event.keycode == KEY_LEFT else 1
    if inspect_mode: rotate_inspection(Vector2(direction*14,0))
    else: navigate(direction)
    return true
   KEY_UP,KEY_DOWN:
    var direction := -1 if event.keycode == KEY_UP else 1
    if inspect_mode: rotate_inspection(Vector2(0,direction*14))
    else: _move_focus(direction)
    return true
   KEY_EQUAL,KEY_PLUS,KEY_KP_ADD:
    if inspect_mode: zoom_inspection(0.08)
    return true
   KEY_MINUS,KEY_KP_SUBTRACT:
    if inspect_mode: zoom_inspection(-0.08)
    return true
 if event is InputEventJoypadButton and event.pressed:
  match event.button_index:
   JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT:
    var direction := -1 if event.button_index == JOY_BUTTON_DPAD_LEFT else 1
    if inspect_mode: rotate_inspection(Vector2(direction*14,0))
    else: navigate(direction)
    return true
   JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN:
    var direction := -1 if event.button_index == JOY_BUTTON_DPAD_UP else 1
    if inspect_mode: rotate_inspection(Vector2(0,direction*14))
    else: _move_focus(direction)
    return true
   JOY_BUTTON_LEFT_SHOULDER:
    if not inspect_mode: navigate(-1)
    return true
   JOY_BUTTON_RIGHT_SHOULDER:
    if not inspect_mode: navigate(1)
    return true
 if event is InputEventJoypadMotion:
  var value: float = event.axis_value if absf(event.axis_value) > 0.20 else 0.0
  if inspect_mode:
   match event.axis:
    JOY_AXIS_LEFT_X: rotate_axis.x = value
    JOY_AXIS_LEFT_Y: rotate_axis.y = value
    JOY_AXIS_RIGHT_Y: zoom_axis = -value
   return true
  if event.axis == JOY_AXIS_LEFT_X:
   if absf(value) < 0.25: axis_navigation_held = false
   elif absf(value) > 0.60 and not axis_navigation_held:
    axis_navigation_held = true
    navigate(1 if value > 0.0 else -1)
   return true
 if event is InputEventJoypadButton: return true
 # Let real controls receive pointer clicks and Tab navigation, not host actions.
 return false

func _process(delta: float) -> void:
 if scan_thread != null and not scan_thread.is_alive() and not inspect_mode: _finish_scan()
 if not visible or not built: return
 if is_instance_valid(manual_reader) and manual_reader.visible: return
 if host.get("application_focused") == false or host.get("scene_active") == false:
  cancel_drag()
  return
 if scan_dialog.visible:
  cancel_drag()
  return
 if manual_framing_active:
  _advance_manual_framing(delta)
  return
 if manual_release_direction != 0:
  _advance_manual_release(delta)
  return
 if inspect_mode:
  _advance_presentation(delta)
  if not rotate_axis.is_zero_approx(): rotate_inspection(rotate_axis*delta*150.0)
  if not is_zero_approx(zoom_axis): zoom_inspection(zoom_axis*delta*0.55)


func _refresh_manual_availability(item: Dictionary) -> void:
 if not is_instance_valid(manual_reader) or not is_instance_valid(manual_button): return
 manual_status = manual_reader.status_for(item)
 manual_button.disabled = not manual_status.is_empty()
 manual_button.tooltip_text = manual_status if not manual_status.is_empty() else "Ler as páginas locais deste jogo"
 manual_button.accessibility_description = manual_button.tooltip_text

func _open_manual() -> void:
 if not _can_interact() or presentation.state != &"presented" or returning_to_carousel: return
 if current_index < 0 or current_index >= ITEMS.size(): return
 cancel_drag()
 _refresh_manual_availability(ITEMS[current_index])
 if not manual_status.is_empty(): return
 if manual_saved_zoom < 0.0: manual_saved_zoom = zoom
 if is_instance_valid(box.manual_book) and box.manual_book.configured:
  if not _configure_manual_release():
   var has_screen_candidate := false
   for diagnostic in manual_release_diagnostics:
    if diagnostic.has("end_rect"): has_screen_candidate = true
   if has_screen_candidate and zoom > 1.001:
    _start_manual_framing(1.0,true)
    return
   manual_status = "Gire um pouco a caixa para liberar o manual." if has_screen_candidate else "Não foi possível liberar o livreto com segurança."
   _restore_manual_zoom()
   manual_button.tooltip_text = manual_status
   manual_release = null
   return
  manual_release.begin_release()
  manual_release_progress = 0.0
  manual_release_direction = 1
  viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
  if _reduced_motion(): _advance_manual_release(0.0)
 else:
  # Image-only catalogs can still be read, but never simulate nonexistent clips.
  _show_released_manual()

func _start_manual_framing(target: float, for_open: bool) -> void:
 cancel_drag()
 manual_framing_from = zoom
 manual_framing_to = clampf(target,ZOOM_MIN,ZOOM_MAX)
 manual_framing_progress = 0.0
 manual_framing_for_open = for_open
 manual_framing_active = true
 if _reduced_motion(): _advance_manual_framing(0.0)

func _advance_manual_framing(delta: float) -> void:
 if not manual_framing_active or not is_finite(delta) or delta < 0: return
 manual_framing_progress = 1.0 if _reduced_motion() else minf(1.0,manual_framing_progress+delta/MANUAL_FRAMING_SECONDS)
 zoom = lerpf(manual_framing_from,manual_framing_to,BoxPresentation._ease(manual_framing_progress))
 _frame_box()
 if manual_framing_progress >= 1.0:
  manual_framing_active = false
  if manual_framing_for_open: _open_manual()
  else:
   manual_saved_zoom = -1.0
   if visible and not manual_button.disabled: manual_button.grab_focus()

func _restore_manual_zoom() -> void:
 if manual_saved_zoom > 0 and not is_equal_approx(zoom,manual_saved_zoom):
  _start_manual_framing(manual_saved_zoom,false)
 else: manual_saved_zoom = -1.0

func _project_mesh_rect(mesh: MeshInstance3D, pose: Transform3D) -> Rect2:
 var bounds := mesh.get_aabb()
 var projected := Rect2()
 var first := true
 var pixel_scale := viewport_container.size / Vector2(viewport.size).max(Vector2.ONE)
 for corner in 8:
  var point := pose * bounds.get_endpoint(corner)
  if camera.is_position_behind(point): return Rect2()
  var screen := camera.unproject_position(point) * pixel_scale + viewport_container.global_position
  if first: projected = Rect2(screen,Vector2.ZERO); first = false
  else: projected = projected.expand(screen)
 return projected

func _configure_manual_release() -> bool:
 manual_release_diagnostics.clear()
 # The two viewports do not share depth. Handoff is allowed only once the real
 # released book is visibly clear of the foreground cartridge, not merely 3D-clear.
 var cartridge_rect := Rect2()
 var first := true
 var meshes: Array[Node] = box.cartridge.find_children("*","MeshInstance3D",true,false)
 if box.cartridge is MeshInstance3D: meshes.append(box.cartridge)
 for candidate in meshes:
  var mesh := candidate as MeshInstance3D
  var projected := _project_mesh_rect(mesh,mesh.global_transform)
  if projected.size.x <= 0.0 or projected.size.y <= 0.0: continue
  cartridge_rect = projected if first else cartridge_rect.merge(projected)
  first = false
 var page_mesh: MeshInstance3D = box.manual_book.cover
 var stage_rect := Rect2(viewport_container.global_position,viewport_container.size).grow(-4.0)
 var base_offset := Vector3(0.07,0.01,0)
 var baseline = load("res://cosmic/manual_release_path.gd").new()
 if not baseline.configure(box,box.manual_book,{"approach_offset_source_m":base_offset}):
  manual_release_diagnostics.append({"offset":base_offset,"error":baseline.last_error})
  return false
 var base_pose: Transform3D = baseline.pose_for(1.0)
 var closed_pose: Transform3D = box.manual_book.get_report().closed_lid_pose
 var offsets: Array[Vector3] = []
 for depth in [0.01,0.0,-0.02]:
  for step in range(8,25): offsets.append(Vector3(float(step)*0.005,depth,0))
 for side in [-1.0,1.0]:
  offsets.append(Vector3(-0.075,-0.02,0))
  offsets.append(Vector3(0,-0.02,side*0.08))
 for offset in offsets:
  # Cheap projection first. Only an endpoint that fits gets a fresh continuous
  # geometry certificate; this avoids dozens of expensive plans on one click.
  var endpoint_pose := base_pose
  endpoint_pose.origin += closed_pose.basis.inverse() * (offset-base_offset)
  var pose: Transform3D = box.manual_book.root.get_parent().global_transform * endpoint_pose * page_mesh.transform
  var end_rect := _project_mesh_rect(page_mesh,pose)
  var clear := first or not end_rect.intersects(cartridge_rect.grow(4.0))
  var inside := stage_rect.encloses(end_rect)
  manual_release_diagnostics.append({"offset":offset,"end_rect":end_rect,"stage_rect":stage_rect,"cartridge_rect":cartridge_rect,"clear":clear,"inside":inside})
  if end_rect.size.x <= 2 or end_rect.size.y <= 2 or not clear or not inside: continue
  if offset.is_equal_approx(base_offset):
   manual_release = baseline
   return true
  var release = load("res://cosmic/manual_release_path.gd").new()
  if release.configure(box,box.manual_book,{"approach_offset_source_m":offset}):
   baseline.clear()
   manual_release = release
   return true
  manual_release_diagnostics.back()["error"] = release.last_error
 baseline.clear()
 manual_release = null
 return false

func _advance_manual_release(delta: float) -> void:
 if not is_finite(delta) or delta < 0.0: return
 if manual_release_direction == 0 or not is_instance_valid(manual_release): return
 if _reduced_motion():
  manual_release_progress = 1.0 if manual_release_direction > 0 else 0.0
 else:
  manual_release_progress = clampf(manual_release_progress + float(manual_release_direction) * maxf(delta,0.0) / MANUAL_RELEASE_DURATION, 0.0, 1.0)
 if not manual_release.apply_progress(manual_release_progress):
  manual_status = "O percurso do livreto foi interrompido para preservar o encaixe."
  manual_button.tooltip_text = manual_status
  _reset_manual_release()
  return
 if manual_release_direction > 0 and manual_release_progress >= 1.0:
  manual_release_direction = 0
  _show_released_manual()
 elif manual_release_direction < 0 and manual_release_progress <= 0.0:
  manual_release_direction = 0
  manual_release.restore()
  manual_release = null
  _restore_manual_zoom()
  if visible and not manual_button.disabled: manual_button.grab_focus()

func _show_released_manual() -> void:
 manual_reader.set_reduced_motion(_reduced_motion())
 manual_reader.bind_source_book(box.manual_book, _manual_origin_rect(), camera)
 if manual_reader.open_item(ITEMS[current_index]):
  viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
  manual_reader.move_to_front()
 else:
  manual_status = manual_reader.last_error
  manual_button.tooltip_text = manual_status
  manual_button.disabled = true
  if is_instance_valid(manual_release):
   manual_release_direction = -1
   if _reduced_motion(): _advance_manual_release(0.0)

func _reset_manual_release(refresh_view: bool = true) -> void:
 manual_release_teardown = true
 if is_instance_valid(manual_reader): manual_reader.finish_close()
 manual_release_direction = 0
 manual_release_progress = 0.0
 manual_framing_active = false
 if manual_saved_zoom > 0: zoom = manual_saved_zoom
 manual_saved_zoom = -1.0
 if is_instance_valid(manual_release): manual_release.restore()
 manual_release = null
 manual_release_teardown = false
 if is_instance_valid(viewport) and visible:
  viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
  if refresh_view and is_inside_tree(): _frame_box()

func _manual_origin_rect() -> Rect2:
 if not is_instance_valid(box) or box.manual_book == null or not box.manual_book.configured: return Rect2()
 var page_mesh: MeshInstance3D = box.manual_book.cover
 if not is_instance_valid(page_mesh) or not is_instance_valid(camera): return Rect2()
 var bounds := page_mesh.get_aabb()
 var projected := Rect2()
 var first := true
 for corner in 8:
  var point := page_mesh.global_transform * bounds.get_endpoint(corner)
  if camera.is_position_behind(point): return Rect2()
  var pixel_scale := viewport_container.size / Vector2(viewport.size).max(Vector2.ONE)
  var screen := camera.unproject_position(point) * pixel_scale + viewport_container.global_position
  if first: projected = Rect2(screen,Vector2.ZERO); first = false
  else: projected = projected.expand(screen)
 return projected

func _manual_closed() -> void:
 if manual_release_teardown: return
 cancel_drag()
 if is_instance_valid(manual_release):
  manual_release.begin_return()
  manual_release_direction = -1
  if _reduced_motion(): _advance_manual_release(0.0)
 else:
  _restore_manual_zoom()
 if is_instance_valid(viewport):
  viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
 if visible and is_instance_valid(manual_button) and not manual_button.disabled: manual_button.grab_focus()
