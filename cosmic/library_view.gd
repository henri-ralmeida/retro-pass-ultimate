extends Control
## Local collection presentation and explicitly requested folder inventory.
## Never executes ROMs, emulation, automatic scans, or network scraping.
## Host owns the transition and routes input here before its system selector.
signal exit_requested

const InputGlyph = preload("res://cosmic/input_glyph.gd")
const GameBox = preload("res://cosmic/game_box.gd")
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
    for field in ["cover_front", "cover_spine", "cover_back", "cover_edge", "model_path", "uv_path", "art_root"]:
     var key: String = field
     if key in ["model_path", "uv_path"] and str(data.get(key, "")).is_empty():
      data.erase(key)
      continue
     var path := str(data.get(key, ""))
     if not path.is_empty() and not path.is_absolute_path(): path = manifest_path.get_base_dir().path_join(path)
     data[key] = path
    ITEMS.append(data)
 if ITEMS.is_empty():
  ITEMS.append({"id":"unavailable", "title":"Acervo indisponível", "subtitle":"MASTER SYSTEM · SEM CAPAS LOCAIS", "accent":"9dd8f2", "description":"Nenhuma capa local disponível. A caixa permanece sem arte, sem substituições fictícias."})

const BOX_BOUNDS := AABB(Vector3(-0.87,-1.22,-0.15),Vector3(1.74,2.44,0.30))
const DEFAULT_YAW := 0.40
const DEFAULT_PITCH := -0.07
const ZOOM_MIN := 0.70
const ZOOM_MAX := 1.40

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
var parts: HBoxContainer
var lid_button: Button
var cartridge_button: Button
var presets: HBoxContainer
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
var preset_buttons: Array[Button] = []
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
 disclosure = _label("Acervo local · capas originais quando disponíveis · sem jogos",chakra,15,Color("a8b9d3"))
 chapter = _label("01  /  ACERVO LOCAL",chakra,14,Color("9dd8f2"))
 item_title = _label("",orbitron,39,Color("f5f1ff"))
 item_subtitle = _label("",chakra,16,Color("bdc5de"))
 description = _label("",chakra,18,Color("b0b6ce"))
 description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 collection_label = _label("COLEÇÃO",chakra,12,Color("828da9"))
 position_label = _label("01  /  02",orbitron,14,Color("d5dbee"))
 position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 mode_label = _label("OBJETO 3D  ·  FRENTE / LOMBADA / VERSO",chakra,12,Color("8995b2"))
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
 for index in ITEMS.size(): _build_card(index)
 footer = HBoxContainer.new()
 footer.alignment = BoxContainer.ALIGNMENT_CENTER
 footer.add_theme_constant_override("separation",14)
 footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(footer)
 inspect_button = _mapped_button("inspect","Inspecionar","Girar a caixa em 3D, ver a lombada e o verso",toggle_inspection)
 reset_button = _mapped_button("reset","Restaurar","Restaurar o ângulo e o zoom da caixa",reset_inspection)
 motion_button = _mapped_button("motion","Pausar","Reduzir o movimento do fundo cósmico",_toggle_motion)
 back_button = _mapped_button("back","Voltar","Voltar ao Master System",go_back)
 for button in [inspect_button,reset_button,motion_button,back_button]: footer.add_child(button)
 presets = HBoxContainer.new()
 presets.alignment = BoxContainer.ALIGNMENT_CENTER
 presets.add_theme_constant_override("separation",6)
 presets.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(presets)
 for entry in [["Frente",0.0],["Lombada",PI*0.5],["Verso",PI]]:
  var button := _plain_button(entry[0],"Ver " + str(entry[0]).to_lower() + " da caixa",show_face.bind(float(entry[1])))
  button.custom_minimum_size = Vector2(84,34)
  presets.add_child(button)
  preset_buttons.append(button)
 parts = HBoxContainer.new()
 parts.alignment = BoxContainer.ALIGNMENT_CENTER
 parts.add_theme_constant_override("separation",8)
 parts.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(parts)
 lid_button = _plain_button("Abrir caixa","Abrir ou fechar a tampa original",func(): box.toggle_lid(); _update_parts())
 cartridge_button = _plain_button("Retirar cartucho","Retirar ou guardar o cartucho original",func(): box.toggle_cartridge(); _update_parts())
 parts.add_child(lid_button)
 parts.add_child(cartridge_button)
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
 var button := _plain_button("","Selecionar caixa: " + str(data.title),func(): _select(index))
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
 title_label.position = Vector2(67,13)
 button.add_child(title_label)
 var subtitle_label := _label(data.subtitle,chakra,11,Color("a4b1cc"))
 subtitle_label.position = Vector2(68,40)
 button.add_child(subtitle_label)
 var number := _label("0" + str(index+1),orbitron,12,Color(data.accent))
 number.name = "CardNumber"
 number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 button.add_child(number)

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
 for index in ITEMS.size(): _build_card(index)
 inspect_mode = false
 _select(0)
 disclosure.text = "%d jogos locais · ScreenScraper não configurado · sem execução" % ITEMS.size()
 if not result.get("warnings", []).is_empty():
  disclosure.text += " · %d avisos" % result.warnings.size()
  disclosure.tooltip_text = "\n".join(result.warnings)
 layout()
 scan_button.grab_focus()

func _exit_tree() -> void:
 if scan_thread != null:
  _cancel_scan()
  scan_thread.wait_to_finish()
  scan_thread = null

func open() -> void:
 _build()
 if not built: return
 visible = true
 inspect_mode = false
 cancel_drag()
 reset_inspection()
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 refresh_controls()
 layout()
 inspect_button.grab_focus()

func close() -> void:
 if scan_dialog: scan_dialog.hide()
 cancel_drag()
 inspect_mode = false
 visible = false
 if viewport: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func navigate(direction: int) -> void:
 if inspect_mode or not visible: return
 var held := axis_navigation_held
 _select(posmod(current_index + direction,ITEMS.size()))
 axis_navigation_held = held

func _select(index: int) -> void:
 if index < 0 or index >= ITEMS.size(): return
 current_index = index
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
 item_title.text = data.title
 item_subtitle.text = data.subtitle
 description.text = data.description
 chapter.text = "%02d  /  ACERVO LOCAL" % (index+1)
 chapter.add_theme_color_override("font_color",Color(data.accent))
 position_label.text = "%02d  /  %02d" % [index+1,ITEMS.size()]
 for card_index in cards.size():
  var card := cards[card_index]
  var active := card_index == current_index
  card.add_theme_stylebox_override("normal",_panel_style(Color(0.075,0.14,0.22,0.85) if active else Color(0.04,0.06,0.12,0.66),Color("709ebd") if active else Color(0.42,0.55,0.75,0.23)))
  card.accessibility_description = "Capa selecionada" if active else "Outra caixa do acervo local"
 _refresh_card_textures()
 _build_neighbors()
 reset_inspection()
 layout()

func _refresh_card_textures() -> void:
 for index in cards.size():
  var distance := mini(posmod(index-current_index,ITEMS.size()),posmod(current_index-index,ITEMS.size()))
  card_textures[index].texture = GameBox.load_artwork(ITEMS[index].get("cover_front", null)) if distance <= 2 else null
 var missing: Array[String] = []
 for face in ["front", "spine", "back"]:
  if GameBox.load_artwork(ITEMS[current_index].get("cover_" + face, null)) == null:
   missing.append({"front":"frente", "spine":"lombada", "back":"verso"}[face])
 description.text = str(ITEMS[current_index].description)
 if not missing.is_empty(): description.text = "Arte indisponível: " + ", ".join(missing) + ". Sem substituições fictícias."

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
  neighbor.configure(ITEMS[index])
  carousel.add_child(neighbor)
  var side := signf(float(offset))
  neighbor.position = Vector3(side * (2.05 + (abs(offset)-1)*1.25), -0.12, -1.25 - (abs(offset)-1)*0.9)
  neighbor.rotation.y = -side * 0.65
  neighbor.scale = Vector3.ONE * 0.86
  neighbor_boxes.append(neighbor)
 carousel.visible = not inspect_mode

func toggle_inspection() -> void:
 if not visible: return
 inspect_mode = not inspect_mode
 cancel_drag()
 reset_inspection()
 refresh_controls()
 layout()
 inspect_button.grab_focus()

func _toggle_motion() -> void:
 if host.has_method("toggle_motion"): host.toggle_motion()
 refresh_controls()

func go_back() -> void:
 if inspect_mode:
  toggle_inspection()
 else:
  cancel_drag()
  exit_requested.emit()

func _update_parts() -> void:
 model_bounds = box.get_local_bounds()
 lid_button.text = "Fechar caixa" if box.opened else "Abrir caixa"
 cartridge_button.text = "Guardar cartucho" if box.cartridge_out else "Retirar cartucho"
 _frame_box()

func reset_inspection() -> void:
 cancel_drag()
 if box:
  box.reset_parts()
  model_bounds = box.get_local_bounds()
  if lid_button: _update_parts()
 yaw = DEFAULT_YAW
 pitch = DEFAULT_PITCH
 zoom = 1.0
 _apply_rotation()

func show_face(angle: float) -> void:
 if not inspect_mode: return
 cancel_drag()
 yaw = angle
 pitch = 0.0
 _apply_rotation()

func rotate_inspection(relative: Vector2) -> void:
 if not inspect_mode: return
 yaw = wrapf(yaw + relative.x * 0.008,-PI,PI)
 pitch = wrapf(pitch + relative.y * 0.008,-PI,PI)
 _apply_rotation()

func zoom_inspection(amount: float) -> void:
 if not inspect_mode: return
 zoom = clampf(zoom+amount,ZOOM_MIN,ZOOM_MAX)
 _frame_box()

func cancel_drag() -> void:
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
 var distance := 0.0
 for index in range(8):
  var point := pivot.basis * model_bounds.get_endpoint(index)
  # Solve the perspective frustum per vertex, including its depth. This keeps
  # a 5% border at maximum zoom for every yaw/pitch, not just front-facing.
  distance = maxf(distance,point.z + maxf(absf(point.y),absf(point.x)/ratio) / tangent * (1.56 if inspect_mode else 1.12) / zoom)
 if not inspect_mode and not neighbor_boxes.is_empty():
  distance = maxf(distance, 3.35 / (tangent*ratio))
 camera.position = Vector3(0,0,maxf(distance,1.0))
 camera.far = maxf(30.0,distance+10.0)
 if zoom_label: zoom_label.text = "%d%%" % roundi(zoom*100.0)

func refresh_controls() -> void:
 if not built: return
 var gamepad: bool = host.get("input_device") == "gamepad"
 var name_value: String = str(host.get("active_pad_name"))
 var profile = host.get("input_profile")
 for button in [inspect_button,reset_button,motion_button,back_button]:
  var action: String = button.get_meta("action","")
  var glyph = button.find_child("InputGlyph",true,false)
  if glyph and profile:
   glyph.symbol = profile.glyph(action,gamepad,name_value)
   glyph.family = profile.family(name_value) if gamepad else "keyboard"
 var action_label = inspect_button.find_child("ActionLabel",true,false)
 if action_label: action_label.text = "Concluir" if inspect_mode else "Inspecionar"
 else: inspect_button.text = "Concluir" if inspect_mode else "Inspecionar"
 inspect_button.accessibility_name = "Concluir inspeção" if inspect_mode else "Inspecionar caixa"
 back_button.accessibility_description = "Voltar à coleção" if inspect_mode else "Voltar ao Master System"
 var motion_label = motion_button.find_child("ActionLabel",true,false)
 if motion_label: motion_label.text = "Animar" if host.get("reduced_motion") == true else "Pausar"
 motion_button.accessibility_name = "Animar fundo" if host.get("reduced_motion") == true else "Pausar movimento do fundo"
 reset_button.visible = inspect_mode
 carousel.visible = not inspect_mode
 parts.visible = inspect_mode and box.can_open()
 presets.visible = inspect_mode
 zoom_controls.visible = inspect_mode
 help_label.text = "Arraste para girar · roda ou +/− para zoom · setas giram" if inspect_mode else "←  →  mudar de capa     ·     Inspecionar para girar a caixa"
 if gamepad:
  help_label.text = "Analógico / direcional: girar · analógico direito: zoom" if inspect_mode else "Direcional: mudar de capa · Tab ou foco para escolher ações"
 mode_label.text = str(ITEMS[current_index].title).to_upper() + "  ·  INSPEÇÃO LIVRE" if inspect_mode else "OBJETO 3D  ·  FRENTE / LOMBADA / VERSO"
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
 var compact := s.y < 620
 var title_y := s.y-222.0
 chapter.position = Vector2(margin,94)
 item_title.position = Vector2(margin,title_y)
 item_title.size = Vector2(s.x-margin*2,48)
 item_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 item_title.add_theme_font_size_override("font_size",25 if narrow else 32)
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
 var visible_indices: Array[int] = [current_index]
 for offset in [-1,1]:
  var adjacent := posmod(current_index+offset,ITEMS.size())
  if adjacent not in visible_indices: visible_indices.append(adjacent)
 visible_indices.sort()
 var card_width := minf(230.0,(s.x-margin*2)/visible_indices.size()-8.0)
 var row_width := visible_indices.size()*(card_width+8.0)-8.0
 for index in cards.size():
  cards[index].visible = not inspect_mode and ITEMS.size() > 1 and index in visible_indices
  var slot := visible_indices.find(index)
  cards[index].position = Vector2((s.x-row_width)*0.5+slot*(card_width+8),s.y-180)
  cards[index].size = Vector2(card_width,34)
  cards[index].get_node("CardTitle").position = Vector2(10,7)
  cards[index].get_node("CardTitle").add_theme_font_size_override("font_size",14)
  cards[index].get_node("CardNumber").visible = false
  card_textures[index].visible = false
  for child in cards[index].get_children():
   if child is Label and child.name != "CardTitle": child.visible = false
 viewport_container.position = Vector2(margin+24,102)
 viewport_container.size = Vector2(s.x-margin*2-48,maxf(100,s.y-324))
 if inspect_mode:
  viewport_container.position = Vector2(s.x*0.15,112)
  viewport_container.size = Vector2(s.x*0.70,s.y-364)
 item_title.visible = not inspect_mode
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
 mode_label.visible = inspect_mode
 mode_label.position = Vector2(0,88 if inspect_mode else s.y-151)
 mode_label.size = Vector2(s.x,24)
 parts.position = Vector2(s.x*0.5-170,s.y-230)
 parts.size = Vector2(340,36)
 presets.position = Vector2(s.x*0.5-220,s.y-187)
 presets.size = Vector2(280,38)
 zoom_controls.position = Vector2(s.x*0.5+76,s.y-187)
 zoom_controls.size = Vector2(128,38)
 help_label.position = Vector2(16,s.y-130)
 help_label.size = Vector2(s.x-32,24)
 help_label.add_theme_font_size_override("font_size",13 if narrow else 14)
 footer.position = Vector2(margin,s.y-96)
 footer.size = Vector2(s.x-margin*2.0,48)
 legal_label.position = Vector2(16,s.y-28)
 legal_label.size = Vector2(s.x-32,20)
 refresh_controls()
 _frame_box()
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
  focused.pressed.emit()
 else:
  toggle_inspection()

func _move_focus(direction: int) -> void:
 var focused := get_viewport().gui_get_focus_owner()
 if focused and is_ancestor_of(focused):
  var target = focused.get_node_or_null(focused.focus_next if direction > 0 else focused.focus_previous)
  if target is Control: target.grab_focus(); return
 inspect_button.grab_focus()

func handle_event(event: InputEvent) -> bool:
 if not visible or not built: return false
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
  if inspect_mode and inside:
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
 if scan_thread != null and not scan_thread.is_alive(): _finish_scan()
 if not visible or not built: return
 if host.get("application_focused") == false or host.get("scene_active") == false:
  cancel_drag()
  return
 if scan_dialog.visible:
  cancel_drag()
  return
 if inspect_mode:
  if not rotate_axis.is_zero_approx(): rotate_inspection(rotate_axis*delta*150.0)
  if not is_zero_approx(zoom_axis): zoom_inspection(zoom_axis*delta*0.55)
