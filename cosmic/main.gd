extends Node
## Independent presentation prototype. No ROM, media, achievement or library operations.
signal system_selected(system_id: String)
@export var systems: Array[Resource] = [preload("res://cosmic/master_system.tres")]
@export var dwell_seconds := 8.0
var dwell_elapsed := 0.0
var dwell_uses_mouse := false
var mouse_dwell_rearm_allowed := true
var auto_history_armed := true
var history_open := false
var history_blend := 0.0
var history_transition: Tween
var history_paused_for_focus := false
var history_panel: PanelContainer
var history_scroll: ScrollContainer
var history_body: RichTextLabel
var history_heading: Label
var current_index := 0
var selection_count := 0
var transition_busy := false
var reduced_motion := false
var scene_active := true
var application_focused := true
var elapsed := 0.0
var cooldown := 0.0
var hovering := false
var inspect_mode := false
var inspection_dragging := false
var inspection_yaw := 0.0
var inspection_pitch := 0.0
var inspection_zoom := 1.0
var inspection_pivot: Node3D
var reset_button: Button
var presentation: Node3D
var camera: Camera3D
var viewport: SubViewport
var viewport_container: SubViewportContainer
var model: Node3D
var background: ColorRect
var bg_material: ShaderMaterial
var ui: Control
var console_button: Button
var inspect_button: Button
var motion_button: Button
var system_logo: TextureRect
var title: Label
var eyebrow: Label
var hint: Label
var status: Label
var footer: HBoxContainer
var header: Label
var fill_light: DirectionalLight3D
var orbitron: Font = preload("res://assets/fonts/Orbitron.ttf")
var chakra: Font = preload("res://assets/fonts/ChakraPetch-Regular.ttf")
var transition: Tween
var last_input_source := ""
var model_bounds := AABB()

func _ready() -> void:
 get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
 _build_background()
 _build_3d()
 _build_ui()
 get_viewport().size_changed.connect(_layout)
 get_window().focus_exited.connect(_focus_lost)
 get_window().focus_entered.connect(_focus_returned)
 get_window().mouse_exited.connect(_pointer_left_window)
 _show_system()
 _layout()
 console_button.grab_focus()
 if "--qa-4-3" in OS.get_cmdline_user_args(): _qa_four_three.call_deferred()
 if "--capture-inspection" in OS.get_cmdline_user_args(): _capture_inspection.call_deferred()
 if "--capture-cosmic" in OS.get_cmdline_user_args(): _capture_sequence.call_deferred()
 if "--capture-motion" in OS.get_cmdline_user_args(): _capture_motion.call_deferred()
 if "--runtime-metrics" in OS.get_cmdline_user_args(): _runtime_metrics.call_deferred()
 if "--capture-offline" in OS.get_cmdline_user_args(): _capture_offline.call_deferred()

func _build_background() -> void:
 var canvas := CanvasLayer.new()
 canvas.layer = -10
 add_child(canvas)
 background = ColorRect.new()
 canvas.add_child(background)
 background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 background.mouse_filter = Control.MOUSE_FILTER_IGNORE
 bg_material = ShaderMaterial.new()
 bg_material.shader = load("res://cosmic/background.gdshader")
 background.material = bg_material

func _build_3d() -> void:
 viewport_container = SubViewportContainer.new()
 viewport_container.stretch = true
 viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(viewport_container)
 viewport = SubViewport.new()
 viewport.transparent_bg = true
 viewport.handle_input_locally = false
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 viewport.msaa_3d = Viewport.MSAA_4X
 viewport_container.add_child(viewport)
 var world := Node3D.new()
 viewport.add_child(world)
 presentation = Node3D.new()
 world.add_child(presentation)
 var env := WorldEnvironment.new()
 var resource := Environment.new()
 resource.background_mode = Environment.BG_COLOR
 resource.background_color = Color(0,0,0,0)
 resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 resource.ambient_light_color = Color("9aaac2")
 resource.ambient_light_energy = 0.65
 resource.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 env.environment = resource
 world.add_child(env)
 var key := DirectionalLight3D.new()
 key.rotation_degrees = Vector3(-42,-32,0)
 key.light_color = Color("fff0db")
 key.light_energy = 1.5
 world.add_child(key)
 fill_light = DirectionalLight3D.new()
 fill_light.rotation_degrees = Vector3(-18,145,0)
 fill_light.light_color = Color("adbdff")
 fill_light.light_energy = 0.8
 world.add_child(fill_light)
 camera = Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.near = 0.01
 camera.far = 5.0
 world.add_child(camera)
 camera.current = true

func _label(text_value: String, font: Font, px: int, color: Color) -> Label:
 var l := Label.new()
 l.text = text_value
 l.add_theme_font_override("font",font)
 l.add_theme_font_size_override("font_size",px)
 l.add_theme_color_override("font_color",color)
 l.mouse_filter = Control.MOUSE_FILTER_IGNORE
 return l

func _action_button(key: String, label_text: String, tip: String, callback: Callable) -> Button:
 var b := Button.new()
 b.custom_minimum_size = Vector2(240,48)
 b.tooltip_text = tip
 b.accessibility_name = label_text
 b.accessibility_description = tip
 b.focus_mode = Control.FOCUS_ALL
 for style in ["normal","hover","pressed","focus","disabled"]:
  b.add_theme_stylebox_override(style,StyleBoxEmpty.new())
 var row := HBoxContainer.new()
 row.mouse_filter = Control.MOUSE_FILTER_IGNORE
 row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 row.alignment = BoxContainer.ALIGNMENT_CENTER
 row.add_theme_constant_override("separation",12)
 b.add_child(row)
 var badge := PanelContainer.new()
 badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
 badge.custom_minimum_size = Vector2(32,32)
 badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 var surface := StyleBoxFlat.new()
 surface.bg_color = Color("cbd0dd")
 surface.set_corner_radius_all(16)
 badge.add_theme_stylebox_override("panel",surface)
 row.add_child(badge)
 var letter := _label(key,chakra,17,Color("182030"))
 letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
 badge.add_child(letter)
 var action_label := _label(label_text,chakra,18,Color("f5f7ff"))
 action_label.name = "ActionLabel"
 action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
 row.add_child(action_label)
 var refresh = func():
  var active = b.has_focus() or b.is_hovered()
  action_label.add_theme_color_override("font_color",Color("6eb4ff") if active else Color("f5f7ff"))
  surface.bg_color = Color("6eb4ff") if active else Color("cbd0dd")
 b.mouse_entered.connect(refresh)
 b.mouse_exited.connect(refresh)
 b.focus_entered.connect(refresh)
 b.focus_exited.connect(refresh)
 b.pressed.connect(callback)
 return b

func _set_action_label(button: Button, text_value: String) -> void:
 var label_node = button.find_child("ActionLabel",true,false)
 if label_node: label_node.text = text_value
 button.accessibility_name = text_value

func _build_ui() -> void:
 var canvas := CanvasLayer.new()
 add_child(canvas)
 ui = Control.new()
 canvas.add_child(ui)
 ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
 header = _label("RETRO PASS ULTIMATE", orbitron,18,Color("dbd9e7"))
 ui.add_child(header)
 var badge := _label("SISTEMAS NO INFINITO",chakra,13,Color("8a849d"))
 badge.name = "PrototypeLabel"
 ui.add_child(badge)
 console_button = Button.new()
 console_button.name = "SelecionarMasterSystem"
 console_button.tooltip_text = "Selecionar Master System"
 console_button.text = ""
 for style in ["normal","hover","pressed","focus","disabled"]:
  console_button.add_theme_stylebox_override(style,StyleBoxEmpty.new())
 console_button.pressed.connect(func(): confirm_selection("button"))
 console_button.mouse_entered.connect(func(): hovering = true; reset_dwell(); auto_history_armed = auto_history_armed or mouse_dwell_rearm_allowed)
 console_button.mouse_exited.connect(func(): hovering = false; reset_dwell())
 console_button.focus_entered.connect(func(): reset_dwell(); auto_history_armed = true)
 console_button.focus_exited.connect(reset_dwell)
 ui.add_child(console_button)
 eyebrow = _label("SEGA  /  CONSOLE",chakra,16,Color("a8b9df"))
 eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 ui.add_child(eyebrow)
 system_logo = TextureRect.new()
 system_logo.name = "LogoDoSistema"
 system_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 system_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 system_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
 ui.add_child(system_logo)
 title = _label("Master System",orbitron,42,Color("f4f1ff"))
 title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 ui.add_child(title)
 hint = _label("Clique no console ou pressione Enter para selecionar",chakra,17,Color("a3a5bb"))
 hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 ui.add_child(hint)
 status = _label("Protótipo de seleção · sem emulação",chakra,14,Color("777f99"))
 status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 ui.add_child(status)
 footer = HBoxContainer.new()
 footer.alignment = BoxContainer.ALIGNMENT_CENTER
 footer.add_theme_constant_override("separation",28)
 ui.add_child(footer)
 inspect_button = _action_button("I","Inspecionar","Inspecionar em 3D · arraste para girar · I",toggle_inspection)
 inspect_button.name = "AproximarConsole"
 footer.add_child(inspect_button)
 motion_button = _action_button("M","Reduzir movimento","Alternar movimento reduzido · M",toggle_motion)
 motion_button.name = "MovimentoReduzido"
 footer.add_child(motion_button)
 console_button.focus_next = inspect_button.get_path()
 inspect_button.focus_next = motion_button.get_path()
 motion_button.focus_next = console_button.get_path()
 reset_button = _action_button("R","Restaurar","Restaurar ângulo e zoom · R",reset_inspection)
 reset_button.visible = false
 footer.add_child(reset_button)
 _build_history_panel()

func _layout() -> void:
 if not is_instance_valid(ui): return
 var s := get_viewport().get_visible_rect().size
 var short_side := minf(s.x,s.y)
 var compact := s.x < 900
 header.position = Vector2(30,24)
 header.add_theme_font_size_override("font_size",15 if compact else 18)
 var badge: Label = ui.get_node("PrototypeLabel")
 badge.position = Vector2(30,52)
 viewport_container.position = Vector2(s.x*0.08,s.y*0.18).lerp(Vector2(s.x*0.015,s.y*0.25),history_blend)
 viewport_container.size = Vector2(s.x*0.84,s.y*0.44).lerp(Vector2(s.x*0.48,s.y*0.35),history_blend)
 if inspect_mode:
  viewport_container.position = Vector2(s.x*0.08,s.y*0.17)
  viewport_container.size = Vector2(s.x*0.84,s.y*0.57)
 console_button.position = viewport_container.position
 console_button.size = viewport_container.size
 eyebrow.position = Vector2(0,s.y*0.63)
 eyebrow.size = Vector2(s.x,24)
 system_logo.position = Vector2(s.x*0.32,s.y*0.64).lerp(Vector2(s.x*0.07,s.y*0.65),history_blend)
 system_logo.size = Vector2(s.x*0.36,s.y*0.12).lerp(Vector2(s.x*0.36,s.y*0.10),history_blend)
 title.position = Vector2(0,s.y*(0.738 if system_logo.visible else 0.675))
 title.size = Vector2(s.x,64)
 title.add_theme_font_size_override("font_size",int(clampf(short_side*(0.036 if system_logo.visible else 0.056),22,48)))
 hint.position = Vector2(0,s.y*(0.80 if system_logo.visible else 0.77))
 hint.size = Vector2(s.x,28)
 hint.add_theme_font_size_override("font_size",14 if compact else 17)
 status.position = Vector2(0,s.y*(0.838 if system_logo.visible else 0.815))
 status.size = Vector2(s.x,23)
 var footer_width := 776.0 if inspect_mode else 508.0
 footer.position = Vector2((s.x-footer_width)*0.5,s.y*0.89)
 footer.size = Vector2(footer_width,48)
 system_logo.visible = systems[current_index].logo != null and not inspect_mode
 if history_panel:
  history_panel.position = Vector2(s.x*0.53,s.y*0.16)
  history_panel.size = Vector2(s.x*0.44,s.y*0.61)
  history_panel.modulate.a = history_blend
 bg_material.set_shader_parameter("aspect",s.x/maxf(s.y,1.0))
 _frame_model()

func _frame_model() -> void:
 if systems.is_empty() or not camera: return
 var data = systems[current_index]
 var ratio := viewport_container.size.x/maxf(viewport_container.size.y,1.0)
 camera.look_at(presentation.to_global(model_bounds.get_center()) if inspect_mode else data.camera_target)
 camera.keep_aspect = Camera3D.KEEP_HEIGHT
 camera.size = data.framing_size * maxf(1.0,1.8/ratio)
 if inspect_mode:
  var extent := Vector2.ZERO
  var center := model_bounds.get_center()
  for i in range(8):
   var rotated := inspection_pivot.basis * (model_bounds.get_endpoint(i)-center)
   var view_point := camera.global_basis.inverse() * rotated
   extent.x = maxf(extent.x,absf(view_point.x)*2.0)
   extent.y = maxf(extent.y,absf(view_point.y)*2.0)
  camera.size = maxf(extent.y,extent.x/ratio) * 1.48 / inspection_zoom

func _show_system() -> void:
 if model: model.queue_free()
 var data = systems[current_index]
 model = data.model.instantiate()
 if inspection_pivot: inspection_pivot.queue_free()
 inspection_pivot = Node3D.new()
 presentation.add_child(inspection_pivot)
 inspection_pivot.add_child(model)
 model.transform = data.presentation_transform
 model_bounds = _collect_bounds(model)
 var center := model_bounds.get_center()
 inspection_pivot.position = center
 model.position -= center
 camera.position = data.camera_position
 camera.look_at(data.camera_target)
 if title:
  title.text = data.display_name
  title.visible = data.logo == null
 if eyebrow:
  eyebrow.text = data.subtitle
  eyebrow.visible = data.logo == null
 if system_logo:
  system_logo.texture = data.logo
  system_logo.accessibility_name = "Logotipo " + data.display_name
  system_logo.visible = data.logo != null
 if console_button:
  console_button.tooltip_text = "Selecionar " + data.display_name
  console_button.accessibility_name = "Selecionar " + data.display_name
 _layout()

func _collect_bounds(node: Node3D) -> AABB:
 var result := AABB()
 var first := true
 for child in node.find_children("*", "MeshInstance3D", true, false):
  var box: AABB = presentation.global_transform.affine_inverse() * child.global_transform * child.get_aabb()
  if first: result = box; first = false
  else: result = result.merge(box)
 return result

func _update_hit_rect() -> void:
 if inspect_mode: return
 if not model or viewport.size.x <= 1 or viewport.size.y <= 1: return
 var lo := Vector2(INF,INF)
 var hi := Vector2(-INF,-INF)
 for i in range(8):
  var point := presentation.global_transform * model_bounds.get_endpoint(i)
  var screen := camera.unproject_position(point)
  lo = lo.min(screen); hi = hi.max(screen)
 var ratio := viewport_container.size / Vector2(viewport.size)
 console_button.position = viewport_container.position + lo * ratio - Vector2(12,12)
 console_button.size = (hi-lo)*ratio + Vector2(24,24)

func navigate(direction: int) -> void:
 reset_dwell()
 if not scene_active or not application_focused or history_open or inspect_mode or transition_busy or systems.size() <= 1: return
 current_index = posmod(current_index+direction,systems.size())
 transition_busy = true
 _show_system()
 if reduced_motion:
  transition_busy = false
  return
 transition = create_tween()
 presentation.scale = Vector3.ONE*0.96
 transition.tween_property(presentation,"scale",Vector3.ONE,0.22)
 transition.finished.connect(func(): transition_busy = false)

func confirm_selection(source: String = "api") -> void:
 if not scene_active or not application_focused or transition_busy or history_open or inspect_mode or cooldown > 0.0 or systems.is_empty(): return
 reset_dwell()
 auto_history_armed = false
 cooldown = 0.4
 selection_count += 1
 last_input_source = source
 var id: String = systems[current_index].system_id
 status.text = "Sistema selecionado · biblioteca ainda não conectada"
 status.add_theme_color_override("font_color",Color("c9b385"))
 print("COSMIC_SELECTION id=%s count=%d source=%s" % [id,selection_count,source])
 system_selected.emit(id)

func _build_history_panel() -> void:
 history_panel = PanelContainer.new()
 history_panel.name = "HistoriaDoConsole"
 history_panel.visible = false
 var surface := StyleBoxFlat.new()
 surface.bg_color = Color(0.025,0.035,0.075,0.93)
 surface.border_color = Color(0.28,0.36,0.58,0.4)
 surface.set_border_width_all(1)
 surface.set_corner_radius_all(12)
 surface.content_margin_left = 20
 surface.content_margin_right = 20
 surface.content_margin_top = 18
 surface.content_margin_bottom = 18
 history_panel.add_theme_stylebox_override("panel",surface)
 ui.add_child(history_panel)
 var column := VBoxContainer.new()
 column.add_theme_constant_override("separation",14)
 history_panel.add_child(column)
 history_heading = _label("História do console",orbitron,20,Color("eef0ff"))
 column.add_child(history_heading)
 var scroll := ScrollContainer.new()
 history_scroll = scroll
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 column.add_child(scroll)
 history_body = RichTextLabel.new()
 history_body.name = "TextoHistorico"
 history_body.fit_content = true
 history_body.scroll_active = false
 history_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 history_body.add_theme_font_override("normal_font",chakra)
 history_body.add_theme_font_size_override("normal_font_size",17)
 history_body.add_theme_constant_override("line_separation",5)
 history_body.add_theme_color_override("default_color",Color("d6dcec"))
 history_body.accessibility_name = "História e fontes do console"
 scroll.add_child(history_body)

func reset_dwell() -> void:
 dwell_elapsed = 0.0

func _advance_dwell(delta: float) -> void:
 var over_controls = inspect_button.is_hovered() or motion_button.is_hovered()
 var eligible = scene_active and application_focused and auto_history_armed and not history_open and not inspect_mode and not transition_busy and not over_controls and (hovering if dwell_uses_mouse else console_button.has_focus())
 if not eligible:
  reset_dwell()
  return
 dwell_elapsed += delta
 if dwell_elapsed >= dwell_seconds: open_history(true)

func _settle_history_motion() -> void:
 if history_transition and history_transition.is_running(): history_transition.kill()
 history_blend = 1.0 if history_open else 0.0
 if history_panel: history_panel.visible = history_open
 _layout()

func open_history(automatic: bool = false) -> void:
 if history_open or inspect_mode or not scene_active or not application_focused or transition_busy: return
 reset_dwell()
 auto_history_armed = false
 history_open = true
 var data = systems[current_index]
 history_body.text = data.history_text + "\n\n" + data.history_credits if not data.history_text.is_empty() else "Texto histórico em preparação."
 history_panel.visible = true
 history_scroll.scroll_vertical = 0
 hint.text = "Esc para voltar · I para inspecionar · Page Up/Down para ler"
 status.text = "Apresentação automática · somente texto" if automatic else "Inspeção do console · somente texto"
 _set_action_label(inspect_button,"Inspecionar")
 inspect_button.tooltip_text = "Abrir inspeção 3D · I; fechar história · Esc"
 inspect_button.grab_focus()
 if reduced_motion: _settle_history_motion()
 else:
  if history_transition and history_transition.is_running(): history_transition.kill()
  history_transition = create_tween()
  history_transition.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
  history_transition.tween_property(self,"history_blend",1.0,0.45)
  history_transition.finished.connect(_layout)
 print("COSMIC_HISTORY opened automatic=",automatic)

func close_history() -> void:
 if not history_open: return
 history_open = false
 mouse_dwell_rearm_allowed = false
 reset_dwell()
 hint.text = "Clique no console ou pressione Enter para selecionar"
 status.text = "Protótipo de seleção · sem emulação"
 _set_action_label(inspect_button,"Inspecionar")
 inspect_button.tooltip_text = "Inspecionar em 3D · arraste para girar · I"
 console_button.grab_focus()
 auto_history_armed = false
 if reduced_motion: _settle_history_motion()
 else:
  if history_transition and history_transition.is_running(): history_transition.kill()
  history_transition = create_tween()
  history_transition.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
  history_transition.tween_property(self,"history_blend",0.0,0.35)
  history_transition.finished.connect(func(): history_panel.visible = false; _layout())
 print("COSMIC_HISTORY closed")

func reset_inspection() -> void:
 inspection_yaw = 0.0
 inspection_pitch = 0.0
 inspection_zoom = 1.0
 inspection_dragging = false
 if inspection_pivot: inspection_pivot.rotation = Vector3.ZERO
 _frame_model()

func rotate_inspection(relative: Vector2) -> void:
 if not inspect_mode: return
 inspection_yaw = wrapf(inspection_yaw + relative.x*0.008,-PI,PI)
 inspection_pitch = wrapf(inspection_pitch + relative.y*0.008,-PI,PI)
 inspection_pivot.rotation = Vector3(inspection_pitch,inspection_yaw,0)
 _frame_model()

func zoom_inspection(amount: float) -> void:
 if not inspect_mode: return
 inspection_zoom = clampf(inspection_zoom+amount,0.65,1.35)
 _frame_model()

func close_inspection() -> void:
 if not inspect_mode: return
 inspect_mode = false
 reset_inspection()
 console_button.mouse_filter = Control.MOUSE_FILTER_STOP
 reset_button.visible = false
 motion_button.focus_next = console_button.get_path()
 _set_action_label(inspect_button,"Inspecionar")
 inspect_button.tooltip_text = "Inspecionar em 3D · arraste para girar · I"
 hint.text = "Clique no console ou pressione Enter para selecionar"
 status.text = "Protótipo de seleção · sem emulação"
 console_button.grab_focus()
 auto_history_armed = false
 mouse_dwell_rearm_allowed = false
 reset_dwell()
 _layout()

func toggle_inspection() -> void:
 if not scene_active or not application_focused: return
 if inspect_mode:
  close_inspection()
  return
 if history_open:
  close_history()
  _settle_history_motion()
 inspect_mode = true
 auto_history_armed = false
 reset_dwell()
 reset_inspection()
 presentation.position = Vector3.ZERO
 console_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
 reset_button.visible = true
 motion_button.focus_next = reset_button.get_path()
 reset_button.focus_next = inspect_button.get_path()
 _set_action_label(inspect_button,"Voltar")
 inspect_button.tooltip_text = "Sair da inspeção 3D · Esc ou I"
 hint.text = "Arraste para girar · roda para zoom · setas e +/− · R restaura"
 status.text = "Inspeção 3D · Esc ou I para voltar"
 inspect_button.grab_focus()
 _layout()

func _inspection_input(event: InputEvent) -> bool:
 if not inspect_mode: return false
 if event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
   inspection_dragging = false
  var inside := viewport_container.get_global_rect().has_point(event.position)
  if not inside: return false
  if event.button_index == MOUSE_BUTTON_LEFT:
   inspection_dragging = event.pressed
   return true
  if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
   zoom_inspection(0.08 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.08)
   return true
 if event is InputEventMouseMotion and inspection_dragging:
  rotate_inspection(event.relative)
  return true
 if event is InputEventKey and event.pressed:
  match event.keycode:
   KEY_LEFT: rotate_inspection(Vector2(-14,0)); return true
   KEY_RIGHT: rotate_inspection(Vector2(14,0)); return true
   KEY_UP: rotate_inspection(Vector2(0,-14)); return true
   KEY_DOWN: rotate_inspection(Vector2(0,14)); return true
   KEY_EQUAL,KEY_PLUS,KEY_KP_ADD: zoom_inspection(0.08); return true
   KEY_MINUS,KEY_KP_SUBTRACT: zoom_inspection(-0.08); return true
   KEY_R: reset_inspection(); return true
   KEY_ESCAPE: close_inspection(); return true
 return false

func toggle_motion() -> void:
 reduced_motion = not reduced_motion
 bg_material.set_shader_parameter("reduced_motion",reduced_motion)
 motion_button.tooltip_text = "Movimento reduzido: %s · M" % ("ligado" if reduced_motion else "desligado")
 _set_action_label(motion_button,"Retomar movimento" if reduced_motion else "Reduzir movimento")
 status.text = "Movimento reduzido: " + ("ligado" if reduced_motion else "desligado")
 if reduced_motion:
  _settle_history_motion()
  presentation.position = Vector3.ZERO
  if transition and transition.is_running(): transition.kill()
  transition_busy = false
  presentation.scale = Vector3.ONE

func set_scene_active(value: bool) -> void:
 scene_active = value
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
 if not value:
  inspection_dragging = false
  reset_dwell()
  _settle_history_motion()
  if transition and transition.is_running(): transition.kill()
  transition_busy = false
  hovering = false
  presentation.scale = Vector3.ONE

func _pointer_left_window() -> void:
 inspection_dragging = false
 hovering = false
 reset_dwell()

func _focus_lost() -> void:
 application_focused = false
 _pointer_left_window()
 # Keep the transparent 3D target alive while the visible scene is unfocused.
 # Disabling it may drop the composed texture on some window/render backends.
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if scene_active else SubViewport.UPDATE_DISABLED
 history_paused_for_focus = history_transition != null and history_transition.is_running()
 if history_paused_for_focus: history_transition.pause()
 if transition and transition.is_running(): transition.kill()
 transition_busy = false
 presentation.scale = Vector3.ONE

func _focus_returned() -> void:
 application_focused = true
 inspection_dragging = false
 reset_dwell()
 cooldown = 0.4
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if scene_active else SubViewport.UPDATE_DISABLED
 if scene_active and history_paused_for_focus and history_transition and history_transition.is_valid(): history_transition.play()
 history_paused_for_focus = false

func _input(event: InputEvent) -> void:
 if not scene_active or not application_focused: return
 if _inspection_input(event):
  get_viewport().set_input_as_handled()
  return
 if event is InputEventMouseMotion:
  dwell_uses_mouse = true
  mouse_dwell_rearm_allowed = true
  if hovering and not history_open and not inspect_mode: auto_history_armed = true
 elif (event is InputEventKey and event.pressed) or (event is InputEventJoypadButton and event.pressed): dwell_uses_mouse = false
 if event is InputEventMouseMotion or (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed): reset_dwell()
 if event is InputEventMouseButton and event.pressed and event.double_click and console_button.get_global_rect().has_point(event.position):
  get_viewport().set_input_as_handled()
  return
 if event is InputEventKey and event.pressed:
  if event.echo:
   if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE,KEY_LEFT,KEY_RIGHT,KEY_I,KEY_M]: get_viewport().set_input_as_handled()
   return
  match event.keycode:
   KEY_LEFT: navigate(-1); get_viewport().set_input_as_handled()
   KEY_RIGHT: navigate(1); get_viewport().set_input_as_handled()
   KEY_I: toggle_inspection(); get_viewport().set_input_as_handled()
   KEY_ESCAPE:
    if history_open: close_history(); get_viewport().set_input_as_handled()
   KEY_PAGEDOWN:
    if history_open: history_scroll.scroll_vertical += 220; get_viewport().set_input_as_handled()
   KEY_PAGEUP:
    if history_open: history_scroll.scroll_vertical -= 220; get_viewport().set_input_as_handled()
   KEY_M: toggle_motion(); get_viewport().set_input_as_handled()
   KEY_ENTER,KEY_KP_ENTER,KEY_SPACE:
    if console_button.has_focus():
     confirm_selection("keyboard"); get_viewport().set_input_as_handled()
 if event is InputEventJoypadButton and event.pressed:
  if event.button_index == JOY_BUTTON_A:
   if inspect_button.has_focus(): toggle_inspection()
   elif motion_button.has_focus(): toggle_motion()
   elif reset_button.has_focus(): reset_inspection()
   elif console_button.has_focus(): confirm_selection("gamepad_mapping")
   get_viewport().set_input_as_handled()
  elif event.button_index == JOY_BUTTON_DPAD_LEFT: navigate(-1)
  elif event.button_index == JOY_BUTTON_DPAD_RIGHT: navigate(1)

func _process(delta: float) -> void:
 if not scene_active or not application_focused: return
 _advance_dwell(delta)
 if history_transition and history_transition.is_running(): _layout()
 _update_hit_rect()
 cooldown = maxf(0.0,cooldown-delta)
 if not reduced_motion: elapsed += delta
 bg_material.set_shader_parameter("animation_time",elapsed)
 bg_material.set_shader_parameter("parallax",Vector2.ZERO if reduced_motion else (get_viewport().get_mouse_position()/get_viewport().get_visible_rect().size-Vector2.ONE*0.5))
 presentation.position.y = 0.0 if reduced_motion or inspect_mode else sin(elapsed*0.7)*0.003
 fill_light.light_energy = lerpf(fill_light.light_energy,1.0 if hovering or console_button.has_focus() else 0.8,minf(delta*8,1.0))

func _capture_sequence() -> void:
 get_window().size = Vector2i(1152,648)
 await get_tree().create_timer(2).timeout
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://evidence/cosmic/01_composicao.png")
 hovering = true
 await get_tree().create_timer(0.3).timeout
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://evidence/cosmic/02_hover.png")
 confirm_selection("capture_test")
 await get_tree().create_timer(0.5).timeout
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://evidence/cosmic/03_confirmacao.png")
 toggle_inspection()
 await get_tree().create_timer(0.5).timeout
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://evidence/cosmic/04_aproximacao.png")
 toggle_inspection()
 get_window().size = Vector2i(1024,768)
 await get_tree().create_timer(0.5).timeout
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://evidence/cosmic/05_proporcao_4_3.png")
 open_history(false)
 await get_tree().create_timer(0.6).timeout
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://evidence/cosmic/06_historia_4_3.png")
 get_tree().quit()

func _capture_motion() -> void:
 get_window().size = Vector2i(1152,648)
 DirAccess.make_dir_recursive_absolute("res://evidence/cosmic/motion_frames")
 await get_tree().create_timer(2.0).timeout
 var stamps: Array[float] = []
 for i in range(100):
  await RenderingServer.frame_post_draw
  stamps.append(Time.get_ticks_msec()/1000.0)
  get_viewport().get_texture().get_image().save_png("res://evidence/cosmic/motion_frames/frame_%04d.png" % i)
  await get_tree().create_timer(0.1).timeout
 var f = FileAccess.open("res://evidence/cosmic/motion_frames/timestamps.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(stamps))
 get_tree().quit()

func _runtime_metrics() -> void:
 get_window().size = Vector2i(1152,648)
 await get_tree().create_timer(2.0).timeout
 var intervals: Array[float] = []
 var started = Time.get_ticks_usec()
 var previous = started
 while Time.get_ticks_usec()-started < 10000000:
  await get_tree().process_frame
  var now = Time.get_ticks_usec()
  intervals.append((now-previous)/1000.0)
  previous=now
 var wall_seconds=(previous-started)/1000000.0
 intervals.sort()
 var metrics={"mode":"real-time standalone, no screenshots/movie writing", "engine":Engine.get_version_info().string, "renderer":RenderingServer.get_video_adapter_name(), "frames":intervals.size(), "wall_seconds":wall_seconds, "mean_fps":intervals.size()/wall_seconds, "frame_ms_p50":intervals[int(intervals.size()*0.5)], "frame_ms_p95":intervals[int(intervals.size()*0.95)], "draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "viewport":"1152x648", "not_user_hardware":true}
 var f=FileAccess.open("res://evidence/cosmic/runtime_metrics.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(metrics,"  "))
 print("COSMIC_RUNTIME_METRICS ",JSON.stringify(metrics))
 get_tree().quit()

func _capture_offline() -> void:
 get_window().size=Vector2i(1152,648)
 DirAccess.make_dir_recursive_absolute("res://evidence/cosmic/offline_frames")
 await get_tree().create_timer(2.0).timeout
 reset_dwell()
 auto_history_armed = true
 dwell_uses_mouse = false
 console_button.grab_focus()
 for i in range(360):
  if "--inspection-demo" in OS.get_cmdline_user_args():
   if i == 45: toggle_inspection()
   if i >= 60 and i < 180: rotate_inspection(Vector2(5.0,0))
   if i >= 180 and i < 285: rotate_inspection(Vector2(0,5.0))
   if i == 300: reset_inspection()
   if i == 330: close_inspection()
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png("res://evidence/cosmic/offline_frames/frame_%04d.png" % i)
 print("COSMIC_OFFLINE_COMPLETE 360 real viewport frames; fixed simulation step 1/30 second; NOT realtime benchmark")
 get_tree().quit()

func _capture_inspection() -> void:
 get_window().size = Vector2i(1152,648)
 await get_tree().create_timer(1.5).timeout
 toggle_inspection()
 for i in range(4):
  reset_inspection()
  if i == 1: rotate_inspection(Vector2(160,30))
  if i == 2: rotate_inspection(Vector2(0,300))
  if i == 3:
   get_window().size = Vector2i(1024,768)
   rotate_inspection(Vector2(-160,-60))
  await get_tree().create_timer(0.5).timeout
  await RenderingServer.frame_post_draw
  get_viewport().get_texture().get_image().save_png("res://evidence/cosmic/inspection_angle_%02d.png" % i)
 get_tree().quit()

func _qa_four_three() -> void:
 await get_tree().process_frame
 await get_tree().process_frame
 get_window().size = Vector2i(1024,768)
