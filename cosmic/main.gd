extends Node
const InputProfile = preload("res://cosmic/input_profile.gd")
const InputGlyph = preload("res://cosmic/input_glyph.gd")
const LocalMediaHost = preload("res://cosmic/media_optin_host.gd")
var media_host
var media_button: Button
var media_release_gate := false
const MediaInputSnapshot = preload("res://cosmic/controller_input_snapshot.gd")
var media_input_snapshot = MediaInputSnapshot.new()
var media_release_device := -1
const ControllerPanel = preload("res://cosmic/controller_mapping_panel.gd")
const ControllerHomePicker = preload("res://cosmic/controller_home_picker.gd")
## Independent museum presentation. No ROM or emulator execution.
signal system_selected(system_id: String)
@export var systems: Array[Resource] = [preload("res://cosmic/master_system.tres"), preload("res://cosmic/atari_system.tres")]
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
var footer: HFlowContainer
var input_profile = InputProfile.new()
var input_device := "keyboard"
var active_pad := -1
var active_pad_name := ""
var confirm_button: Button
var back_button: Button
var settings_button: Button
var settings_panel: PanelContainer
var family_selector: OptionButton
var mapping_buttons: Dictionary = {}
var capture_action := ""
var settings_message: Label
var axis_navigation_held := false
var header: Label
var fill_light: DirectionalLight3D
var orbitron: Font = preload("res://assets/fonts/Orbitron.ttf")
var chakra: Font = preload("res://assets/fonts/ChakraPetch-Regular.ttf")
var transition: Tween
var last_input_source := ""
var model_bounds := AABB()
@export var exhibit_enabled := true
var exhibit: Node3D
var perspective_box_view
var normal_bounds := AABB()
@export var library_enabled := true
var library_state := "system"
var library_view
var sms_library_view
var atari_library_view
const AtariBridge = preload("res://cosmic/atari_system_bridge.gd")
var entry_tween: Tween
var entry_progress := 0.0
var entry_start_camera_position := Vector3.ZERO
var entry_start_camera_target := Vector3.ZERO
var entry_start_size := 0.28
var entry_veil: ColorRect
var entry_paused := false
var entry_generation := 0
var entry_library_id := 0
var entry_autostart_token := -1
# Controller configuration is an exclusive modal, not a second HOME input path.
var controller_panel
var controller_picker = ControllerHomePicker.new()
var controller_background_blocked := false
var controller_release_gate := false
var controller_release_elapsed := 0.0
var controller_return_focus: Control
var controller_return_settings := false
var controller_saved_button_states: Dictionary = {}
var controller_saved_pointer_states: Dictionary = {}
var controller_history_paused := false
var controller_click_active := false
var controller_click_port := -1
var controller_click_origin := Vector2.ZERO
var controller_click_max_distance := 0.0
var controller_last_event: InputEvent
const CONTROLLER_CLICK_SLOP := 6.0
const CONTROLLER_RELEASE_SECONDS := 0.15


func _ready() -> void:
 input_profile.load_settings()
 get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
 _build_background()
 _build_3d()
 perspective_box_view = load("res://cosmic/perspective_box_view.gd").new()
 perspective_box_view.name = "PerspectiveBackgroundBox"
 add_child(perspective_box_view)
 _build_ui()
 if library_enabled: _build_library()
 controller_panel = ControllerPanel.new()
 controller_panel.name = "MasterSystemControllerSettings"
 var controller_theme := Theme.new()
 controller_theme.default_font = chakra
 controller_panel.theme = controller_theme
 ui.get_parent().add_child(controller_panel)
 controller_panel.setup_host(input_profile)
 controller_panel.title.add_theme_font_override("font",orbitron)
 controller_panel.closed.connect(_controller_panel_closed)
 _build_local_media_host()
 Input.joy_connection_changed.connect(_joy_connection_changed)
 var pads := Input.get_connected_joypads()
 if not pads.is_empty(): _set_input_device("gamepad",pads[0],Input.get_joy_name(pads[0]))
 _refresh_controls()
 get_viewport().size_changed.connect(_layout)
 get_window().focus_exited.connect(_focus_lost)
 get_window().focus_entered.connect(_focus_returned)
 get_window().mouse_exited.connect(_pointer_left_window)
 _show_system()
 _layout()
 console_button.grab_focus()
 if "--qa-4-3" in OS.get_cmdline_user_args(): _qa_four_three.call_deferred()
 if "--qa-16-9" in OS.get_cmdline_user_args(): _qa_sixteen_nine.call_deferred()
 if "--capture-inspection" in OS.get_cmdline_user_args(): _capture_inspection.call_deferred()
 if "--capture-cosmic" in OS.get_cmdline_user_args(): _capture_sequence.call_deferred()
 if "--capture-motion" in OS.get_cmdline_user_args(): _capture_motion.call_deferred()
 if "--runtime-metrics" in OS.get_cmdline_user_args(): _runtime_metrics.call_deferred()
 if "--capture-offline" in OS.get_cmdline_user_args(): _capture_offline.call_deferred()

func _set_input_device(kind: String, device: int = -1, device_name: String = "") -> void:
 if input_device == kind and active_pad == device and active_pad_name == device_name: return
 input_device = kind
 active_pad = device
 active_pad_name = device_name
 axis_navigation_held = false
 reset_dwell()
 if is_instance_valid(footer): _refresh_controls()
 if is_instance_valid(library_view):
  library_view.cancel_drag()
  library_view.refresh_controls()

func _joy_connection_changed(device: int, connected: bool) -> void:
 if not connected: media_input_snapshot.forget_device(device)
 # The modal owns its chosen device. Do not silently adopt another pad behind it.
 if _controller_blocks_background(): return
 if connected and active_pad < 0:
  _set_input_device("gamepad",device,Input.get_joy_name(device))
 elif not connected and device == active_pad:
  inspection_dragging = false
  var remaining := Input.get_connected_joypads()
  remaining.erase(device)
  if remaining.is_empty(): _set_input_device("keyboard")
  else: _set_input_device("gamepad",remaining[0],Input.get_joy_name(remaining[0]))

func _observe_input_device(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed:
  _set_input_device("keyboard")
 elif event is InputEventMouseButton and event.pressed:
  _set_input_device("keyboard")
 elif event is InputEventMouseMotion and event.relative.length() > 2.0:
  _set_input_device("keyboard")
 elif (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.3):
  _set_input_device("gamepad",event.device,Input.get_joy_name(event.device))

func _refresh_controls() -> void:
 if not is_instance_valid(footer): return
 var gamepad := input_device == "gamepad"
 var family: String = input_profile.family(active_pad_name) if gamepad else "keyboard"
 confirm_button.visible = not inspect_mode and not history_open
 back_button.visible = inspect_mode or history_open
 reset_button.visible = inspect_mode
 _set_action_label(inspect_button,"Voltar" if inspect_mode else "Inspecionar")
 _set_action_label(motion_button,"Animar" if reduced_motion else "Pausar")
 var controls: Array[Control] = []
 if not inspect_mode and not history_open: controls.append(console_button)
 for button in footer.get_children():
  var action: String = button.get_meta("action","")
  var glyph = button.find_child("InputGlyph",true,false)
  if action == "local_media":
   glyph.symbol = ""
   glyph.family = "keyboard"
  elif action == "settings":
   glyph.symbol = "F1"
   glyph.family = "keyboard"
  else:
   glyph.symbol = input_profile.glyph(action,gamepad,active_pad_name)
   glyph.family = family
   button.tooltip_text = button.accessibility_name
  if button.visible: controls.append(button)
 for index in controls.size():
  var previous: NodePath = controls[posmod(index-1,controls.size())].get_path()
  var following: NodePath = controls[(index+1)%controls.size()].get_path()
  controls[index].focus_previous = previous
  controls[index].focus_next = following
  controls[index].focus_neighbor_left = previous
  controls[index].focus_neighbor_right = following
 if settings_panel:
  footer.mouse_filter = Control.MOUSE_FILTER_IGNORE if settings_panel.visible else Control.MOUSE_FILTER_PASS
 if is_instance_valid(settings_message): _refresh_mapping_labels()

func go_back() -> void:
 if _controller_blocks_background(): return
 if library_state == "library":
  library_view.go_back()
  return
 if library_state != "system":
  leave_library()
  return
 if settings_panel.visible: toggle_control_settings()
 elif inspect_mode: close_inspection()
 elif history_open: close_history()

func _build_control_settings() -> void:
 settings_panel = PanelContainer.new()
 settings_panel.name = "ControlSettings"
 settings_panel.visible = false
 var style := StyleBoxFlat.new()
 style.bg_color = Color("11182b")
 style.border_color = Color("465777")
 style.set_border_width_all(1)
 style.set_corner_radius_all(10)
 style.content_margin_left = 18
 style.content_margin_right = 18
 style.content_margin_top = 16
 style.content_margin_bottom = 16
 settings_panel.add_theme_stylebox_override("panel",style)
 ui.add_child(settings_panel)
 var scroll := ScrollContainer.new()
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 settings_panel.add_child(scroll)
 var column := VBoxContainer.new()
 column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 column.add_theme_constant_override("separation",10)
 scroll.add_child(column)
 column.add_child(_label("Controles",orbitron,20,Color("eef3ff")))
 column.add_child(_label("Master System · comandos do jogo",chakra,17,Color("eef3ff")))
 for port in 2:
  var sms_button := Button.new()
  sms_button.name = "ConfigureSmsPlayer%d" % (port + 1)
  sms_button.text = "Master System · Jogador %d" % (port + 1)
  sms_button.accessibility_name = sms_button.text
  sms_button.custom_minimum_size.y = 48
  sms_button.pressed.connect(_open_controller_settings.bind(port,sms_button))
  column.add_child(sms_button)
 column.add_child(_label("Interface · navegação e apresentação",chakra,17,Color("eef3ff")))
 family_selector = OptionButton.new()
 family_selector.accessibility_name = "Símbolos do controle"
 family_selector.get_popup().window_input.connect(_family_popup_input)
 for item in ["Automático", "Xbox", "PlayStation", "Genérico"]: family_selector.add_item(item)
 family_selector.select(["auto","xbox","playstation","generic"].find(input_profile.family_override))
 family_selector.item_selected.connect(func(index: int):
  input_profile.family_override = ["auto","xbox","playstation","generic"][index]
  _save_control_settings()
  _refresh_controls())
 column.add_child(family_selector)
 settings_message = _label("Selecione uma ação para remapear",chakra,15,Color("a8b9d3"))
 settings_message.custom_minimum_size.y = 34
 settings_message.clip_text = true
 column.add_child(settings_message)
 for action in InputProfile.ACTIONS:
  var button := Button.new()
  button.custom_minimum_size.y = 38
  button.pressed.connect(_begin_rebind.bind(action))
  mapping_buttons[action] = button
  column.add_child(button)
 var defaults := Button.new()
 defaults.text = "Restaurar controles padrão"
 defaults.custom_minimum_size.y = 38
 defaults.pressed.connect(_restore_control_defaults)
 column.add_child(defaults)
 var close := Button.new()
 close.text = "Voltar"
 close.custom_minimum_size.y = 38
 close.pressed.connect(toggle_control_settings)
 column.add_child(close)

func _restore_control_defaults() -> void:
 input_profile.keys = InputProfile.KEYS.duplicate()
 input_profile.buttons = InputProfile.BUTTONS.duplicate()
 input_profile.family_override = "auto"
 family_selector.select(0)
 capture_action = ""
 settings_message.text = "Controles padrão restaurados"
 _save_control_settings()
 _refresh_controls()

func _family_popup_input(event: InputEvent) -> void:
 var popup := family_selector.get_popup()
 if not popup.visible: return
 if not scene_active or (not application_focused and not popup.has_focus()):
  popup.set_input_as_handled()
  return
 _observe_input_device(event)
 var action: String = input_profile.action_for(event)
 if action == "back":
  popup.hide()
  popup.set_input_as_handled()
 elif action == "confirm":
  var index := popup.get_focused_item()
  if index < 0: index = family_selector.selected
  popup.index_pressed.emit(index)
  popup.hide()
  popup.set_input_as_handled()

func _refresh_mapping_labels() -> void:
 var names := {"confirm":"Confirmar","back":"Voltar","inspect":"Inspecionar","motion":"Movimento","reset":"Restaurar"}
 for action in mapping_buttons:
  var keyboard: String = input_profile.glyph(action,false)
  var pad := "Botão %d" % (int(input_profile.buttons[action])+1)
  mapping_buttons[action].text = "%s  ·  Teclado %s  /  %s" % [names[action],keyboard,pad]
  mapping_buttons[action].accessibility_name = mapping_buttons[action].text
 family_selector.tooltip_text = active_pad_name if not active_pad_name.is_empty() else "Sem controle identificado; escolha manual disponível"

func toggle_control_settings() -> void:
 if _controller_blocks_background(): return
 if not scene_active or not application_focused: return
 settings_panel.visible = not settings_panel.visible
 capture_action = ""
 inspection_dragging = false
 reset_dwell()
 settings_message.text = "Selecione uma ação para remapear"
 # Modal settings cannot activate the console or footer behind them.
 console_button.disabled = settings_panel.visible
 for button in footer.get_children(): button.disabled = settings_panel.visible
 if settings_panel.visible: family_selector.grab_focus()
 elif inspect_mode or history_open: inspect_button.grab_focus()
 else: console_button.grab_focus()
 _refresh_controls()

func _begin_rebind(action: String) -> void:
 capture_action = action
 settings_message.text = "Pressione tecla ou botão · Esc cancela"

func _save_control_settings() -> void:
 if input_profile.save_settings() != OK:
  settings_message.text = "Não foi possível salvar os controles"

func _settings_input(event: InputEvent) -> bool:
 if not settings_panel.visible: return false
 if event is InputEventKey and event.pressed and event.echo: return true
 if event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_F1):
  if capture_action.is_empty(): toggle_control_settings()
  else:
   capture_action = ""
   settings_message.text = "Remapeamento cancelado"
  return true
 if not capture_action.is_empty():
  var code := -1
  var gamepad := event is InputEventJoypadButton
  if event is InputEventKey and event.pressed and not event.echo:
   code = event.physical_keycode if event.physical_keycode else event.keycode
  elif gamepad and event.pressed: code = event.button_index
  if code >= 0:
   input_profile.rebind(capture_action,code,gamepad)
   capture_action = ""
   settings_message.text = "Controles atualizados"
   _save_control_settings()
   _refresh_controls()
  return true
 if input_profile.action_for(event) == "back":
  toggle_control_settings()
  return true
 return false

func _activate_focused_control() -> void:
 if _controller_blocks_background(): return
 var focused := get_viewport().gui_get_focus_owner()
 if focused == console_button: confirm_selection("keyboard" if input_device=="keyboard" else "gamepad_mapping")
 elif focused is OptionButton: focused.show_popup()
 elif focused is Button and focused.is_visible_in_tree() and not focused.disabled:
  focused.pressed.emit()

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
 b.custom_minimum_size = Vector2(144,48)
 b.set_meta("action",key)
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
 var glyph := InputGlyph.new()
 glyph.name = "InputGlyph"
 glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
 row.add_child(glyph)
 var action_label := _label(label_text,chakra,18,Color("f5f7ff"))
 action_label.name = "ActionLabel"
 action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
 row.add_child(action_label)
 var refresh = func():
  var active = b.has_focus() or b.is_hovered()
  action_label.add_theme_color_override("font_color",Color("6eb4ff") if active else Color("f5f7ff"))
  glyph.modulate = Color("a5cfff") if active else Color.WHITE
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
 hint.visible = false
 ui.add_child(hint)
 status = _label("Protótipo de seleção · sem emulação",chakra,14,Color("777f99"))
 status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 status.visible = false
 ui.add_child(status)
 footer = HFlowContainer.new()
 footer.alignment = FlowContainer.ALIGNMENT_CENTER
 footer.add_theme_constant_override("h_separation",8)
 footer.add_theme_constant_override("v_separation",0)
 ui.add_child(footer)
 confirm_button = _action_button("confirm","Entrar","Entrar no sistema",func(): confirm_selection("footer"))
 footer.add_child(confirm_button)
 back_button = _action_button("back","Voltar","Voltar",go_back)
 footer.add_child(back_button)
 inspect_button = _action_button("inspect","Inspecionar","Inspecionar em 3D",toggle_inspection)
 inspect_button.name = "AproximarConsole"
 footer.add_child(inspect_button)
 motion_button = _action_button("motion","Movimento","Reduzir movimento",toggle_motion)
 motion_button.name = "MovimentoReduzido"
 footer.add_child(motion_button)
 reset_button = _action_button("reset","Restaurar","Restaurar ângulo e zoom",reset_inspection)
 footer.add_child(reset_button)
 settings_button = _action_button("settings","Controles","Símbolos e remapeamento — F1",toggle_control_settings)
 footer.add_child(settings_button)
 _build_history_panel()
 _build_control_settings()

func _layout() -> void:
 if not is_instance_valid(ui): return
 var s := get_viewport().get_visible_rect().size
 var short_side := minf(s.x,s.y)
 var compact := s.x < 900
 header.position = Vector2(30,24)
 header.add_theme_font_size_override("font_size",15 if compact else 18)
 var exhibit_layout := is_instance_valid(exhibit)
 viewport_container.position = Vector2(s.x*0.08,s.y*(0.10 if exhibit_layout else 0.18)).lerp(Vector2(s.x*0.015,s.y*0.25),history_blend)
 viewport_container.size = Vector2(s.x*0.84,s.y*(0.53 if exhibit_layout else 0.44)).lerp(Vector2(s.x*0.48,s.y*0.35),history_blend)
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
 if is_instance_valid(exhibit) and exhibit.hardware_art_missing:
  status.position.y = s.y-132
 footer.position = Vector2(20,s.y-104)
 footer.size = Vector2(s.x-40,96)
 if settings_panel:
  settings_panel.position = Vector2(maxf(12,(s.x-500)*0.5),maxf(12,(s.y-500)*0.5))
  settings_panel.size = Vector2(minf(s.x-24,500),minf(s.y-24,500))
 system_logo.visible = systems[current_index].logo != null and not inspect_mode
 if history_panel:
  history_panel.position = Vector2(s.x*0.53,s.y*0.16)
  history_panel.size = Vector2(s.x*0.44,s.y*0.61)
  history_panel.modulate.a = history_blend
 bg_material.set_shader_parameter("aspect",s.x/maxf(s.y,1.0))
 _frame_model()
 if library_view: library_view.layout()
 if entry_veil: entry_veil.size = s
 if library_state == "entering": _apply_entry(entry_progress)

func _frame_model() -> void:
 if systems.is_empty() or not camera: return
 _sync_exhibit_visibility()
 var data = systems[current_index]
 var ratio := viewport_container.size.x/maxf(viewport_container.size.y,1.0)
 camera.position = data.camera_position
 camera.look_at(presentation.to_global(model_bounds.get_center()) if inspect_mode else data.camera_target)
 camera.keep_aspect = Camera3D.KEEP_HEIGHT
 camera.size = data.framing_size * maxf(1.0,1.8/ratio)
 if is_instance_valid(exhibit) and exhibit.visible:
  normal_bounds = exhibit.get_combined_bounds() # Metadata only, not framing geometry.
  var points: PackedVector3Array = exhibit.get_visible_world_corners()
  var low := Vector2(INF,INF)
  var high := Vector2(-INF,-INF)
  for world_point in points:
   var camera_point := camera.to_local(world_point)
   low = low.min(Vector2(camera_point.x,camera_point.y))
   high = high.max(Vector2(camera_point.x,camera_point.y))
  if not points.is_empty():
   var projected_center := (low+high)*0.5
   # Pan in the approved view plane; do not rotate toward an imaginary AABB center.
   camera.global_position += camera.global_basis*Vector3(projected_center.x,projected_center.y,0)
   var actual_extent := high-low
   camera.size = maxf(actual_extent.y,actual_extent.x/ratio)*1.10
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
 _activate_system_library()
 if is_instance_valid(exhibit):
  exhibit.set_exhibit_visible(false)
  exhibit.get_parent().remove_child(exhibit)
  exhibit.queue_free()
  exhibit = null
 if model: model.queue_free()
 var data = systems[current_index]
 model = data.model.instantiate()
 if inspection_pivot: inspection_pivot.queue_free()
 inspection_pivot = Node3D.new()
 presentation.add_child(inspection_pivot)
 inspection_pivot.add_child(model)
 model.transform = data.presentation_transform
 model_bounds = _collect_bounds(model)
 if is_instance_valid(inspect_button):
  inspect_button.disabled = AtariBridge.handles(data) and not bool(model.get_meta("atari_media_available",false))
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
 _rebuild_exhibit()
 _layout()

func _rebuild_exhibit() -> void:
 if is_instance_valid(perspective_box_view): perspective_box_view.clear()
 if is_instance_valid(exhibit):
  exhibit.set_exhibit_visible(false)
  exhibit.get_parent().remove_child(exhibit)
  exhibit.queue_free()
  exhibit = null
 if AtariBridge.handles(systems[current_index]):
  _sync_exhibit_visibility()
  return
 if not exhibit_enabled or not library_enabled or not is_instance_valid(library_view) or not is_instance_valid(model): return
 if library_view.ITEMS.is_empty(): return
 var selected: Dictionary = library_view.ITEMS[clampi(library_view.current_index,0,library_view.ITEMS.size()-1)]
 # No invented default title/art: reuse only the current catalog entry.
 exhibit = load("res://cosmic/exhibit_scene.gd").new()
 exhibit.name = "FloatingSelectedGameExhibit"
 presentation.add_child(exhibit)
 var approved_view_basis := Basis.looking_at(systems[current_index].camera_target-systems[current_index].camera_position,Vector3.UP)
 if not exhibit.configure_extras(model, selected, presentation.global_basis.inverse()*camera.get_parent().global_basis*approved_view_basis):
  push_warning("Exhibit incomplete: " + str(exhibit.configuration_errors))
 if is_instance_valid(exhibit.game_box) and is_instance_valid(perspective_box_view):
  # Preserve approved console framing using the original physical placement as
  # a non-rendered bounds proxy. Only the dedicated perspective world draws art.
  if perspective_box_view.configure(selected):
   for mesh in exhibit.game_box.find_children("*","MeshInstance3D",true,false):
    mesh.layers = 0
   exhibit.game_box.set_meta("perspective_bounds_proxy",true)
  else:
   push_warning("Perspective box unavailable; original physical fallback retained.")
 _sync_exhibit_visibility()

func _default_system_status() -> String:
 if AtariBridge.handles(systems[current_index]): return AtariBridge.status_text()
 if is_instance_valid(exhibit) and exhibit.hardware_art_missing:
  return "Texturas do controle indisponíveis · sem emulação"
 return "Protótipo de seleção · sem emulação"

func _sync_exhibit_visibility() -> void:
 if is_instance_valid(exhibit):
  var retain_during_entry := library_state == "entering" and not reduced_motion and entry_progress < 0.94
  exhibit.set_exhibit_visible(not inspect_mode and not history_open and history_blend <= 0.001 and (library_state == "system" or retain_during_entry))
 if is_instance_valid(perspective_box_view):
  perspective_box_view.set_active(is_instance_valid(exhibit) and exhibit.visible and is_instance_valid(exhibit.game_box) and exhibit.game_box.get_meta("perspective_bounds_proxy",false))
  perspective_box_view.set_scene_active(scene_active)
 if is_instance_valid(status):
  status.visible = is_instance_valid(exhibit) and exhibit.hardware_art_missing and not inspect_mode and not history_open and history_blend <= 0.001 and library_state == "system"
  if AtariBridge.handles(systems[current_index]):
   status.visible = not inspect_mode and not history_open and history_blend <= 0.001 and library_state == "system"
  if status.visible: status.text = _default_system_status()

func _update_perspective_box_frame() -> void:
 if not is_instance_valid(perspective_box_view): return
 if not is_instance_valid(exhibit) or not is_instance_valid(exhibit.game_box): return
 var low := Vector2(INF,INF)
 var high := Vector2(-INF,-INF)
 for mesh in exhibit.game_box.find_children("*","MeshInstance3D",true,false):
  if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
  for corner in 8:
   var world_point: Vector3 = mesh.global_transform*mesh.get_aabb().get_endpoint(corner)
   if camera.is_position_behind(world_point): continue
   var projected := camera.unproject_position(world_point)
   low = low.min(projected)
   high = high.max(projected)
 if not is_finite(low.x): return
 var ratio := viewport_container.size/Vector2(viewport.size).max(Vector2.ONE)
 var rect := Rect2(viewport_container.position+low*ratio,(high-low)*ratio)
 perspective_box_view.set_frame(rect)
 # Follow entry fade without ever drawing over the library or UI.
 perspective_box_view.modulate.a = 1.0-smoothstep(0.48,0.94,entry_progress) if library_state == "entering" else 1.0

func _collect_bounds(node: Node3D) -> AABB:
 var result := AABB()
 var first := true
 for child in node.find_children("*", "MeshInstance3D", true, false):
  var box: AABB = presentation.global_transform.affine_inverse() * child.global_transform * child.get_aabb()
  if first: result = box; first = false
  else: result = result.merge(box)
 return result

func _update_hit_rect() -> void:
 if library_state != "system": return
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
 if _controller_blocks_background(): return
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
 if _controller_blocks_background(): return
 if not scene_active or not application_focused or settings_panel.visible or transition_busy or history_open or inspect_mode or cooldown > 0.0 or systems.is_empty() or library_state != "system":
  if "--trace-input" in OS.get_cmdline_user_args(): print("SELECTION_BLOCKED ",{"active":scene_active,"focused":application_focused,"settings":settings_panel.visible,"transition":transition_busy,"history":history_open,"inspect":inspect_mode,"cooldown":cooldown,"library":library_state,"source":source})
  return
 reset_dwell()
 auto_history_armed = false
 cooldown = 0.4
 selection_count += 1
 last_input_source = source
 var id: String = systems[current_index].system_id
 status.text = "Entrando na biblioteca conceito · sem execução de jogos"
 status.add_theme_color_override("font_color",Color("c9b385"))
 print("COSMIC_SELECTION id=%s count=%d source=%s" % [id,selection_count,source])
 system_selected.emit(id)
 if library_enabled: enter_library()

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
 if _controller_blocks_background() or controller_click_active:
  reset_dwell()
  return
 if library_state != "system":
  reset_dwell()
  return
 var over_controls := false
 for button in footer.get_children():
  if button.visible and button.is_hovered(): over_controls = true
 var eligible = scene_active and application_focused and auto_history_armed and not history_open and not inspect_mode and not transition_busy and not over_controls and (hovering if dwell_uses_mouse else console_button.has_focus())
 if settings_panel.visible: eligible = false
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
 if _controller_blocks_background(): return
 if library_state != "system": return
 if history_open or inspect_mode or settings_panel.visible or not scene_active or not application_focused or transition_busy: return
 reset_dwell()
 auto_history_armed = false
 history_open = true
 _sync_exhibit_visibility()
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
 _refresh_controls()
 print("COSMIC_HISTORY opened automatic=",automatic)

func close_history() -> void:
 if not history_open: return
 history_open = false
 mouse_dwell_rearm_allowed = false
 reset_dwell()
 hint.text = "Clique no console ou pressione Enter para selecionar"
 status.text = _default_system_status()
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
 _refresh_controls()
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
 status.text = _default_system_status()
 console_button.grab_focus()
 auto_history_armed = false
 mouse_dwell_rearm_allowed = false
 reset_dwell()
 _refresh_controls()
 _layout()

func toggle_inspection() -> void:
 if AtariBridge.handles(systems[current_index]) and (not is_instance_valid(model) or not bool(model.get_meta("atari_media_available",false))):
  status.text = "Console Atari indisponível para inspeção. Habilite explicitamente a mídia local."
  return
 if _controller_blocks_background(): return
 if library_state != "system": return
 if not scene_active or not application_focused: return
 if settings_panel.visible: return
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
 _refresh_controls()
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
   KEY_ESCAPE: close_inspection(); return true
 return false

func toggle_motion() -> void:
 if _controller_blocks_background(): return
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

 _refresh_controls()

func set_scene_active(value: bool) -> void:
 if not value: controller_click_active = false
 if is_instance_valid(controller_panel): controller_panel.focus_changed(value and application_focused)
 controller_click_port = -1
 controller_release_elapsed = 0.0
 if is_instance_valid(perspective_box_view): perspective_box_view.set_scene_active(value)
 if not value and library_state != "system": leave_library()
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
 controller_click_port = -1
 controller_click_max_distance = INF
 if library_view: library_view.cancel_drag()
 inspection_dragging = false
 hovering = false
 reset_dwell()

func _focus_lost() -> void:
 application_focused = false
 if is_instance_valid(library_view) and library_view.has_method("cancel_pending_autostart"):
  library_view.cancel_pending_autostart()
 controller_click_active = false
 if is_instance_valid(controller_panel): controller_panel.focus_changed(false)
 controller_release_elapsed = 0.0
 entry_paused = entry_tween != null and entry_tween.is_running()
 if entry_paused: entry_tween.pause()
 _pointer_left_window()
 # Keep the transparent 3D target alive while the visible scene is unfocused.
 # Disabling it may drop the composed texture on some window/render backends.
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if scene_active and library_state != "library" else SubViewport.UPDATE_DISABLED
 history_paused_for_focus = history_transition != null and history_transition.is_running()
 if history_paused_for_focus: history_transition.pause()
 if transition and transition.is_running(): transition.kill()
 transition_busy = false
 presentation.scale = Vector3.ONE

func _focus_returned() -> void:
 application_focused = true
 if is_instance_valid(controller_panel): controller_panel.focus_changed(scene_active)
 controller_release_elapsed = 0.0
 if entry_paused and entry_tween and entry_tween.is_valid(): entry_tween.play()
 entry_paused = false
 inspection_dragging = false
 reset_dwell()
 cooldown = 0.4
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if scene_active and library_state != "library" else SubViewport.UPDATE_DISABLED
 if scene_active and history_paused_for_focus and history_transition and history_transition.is_valid(): history_transition.play()
 history_paused_for_focus = false

func _input(event: InputEvent) -> void:
 media_input_snapshot.observe(event)
 controller_last_event = event
 if not scene_active or not application_focused:
  get_viewport().set_input_as_handled()
  return
 if is_instance_valid(media_host) and media_host.is_open():
  if media_host.route_input(event): get_viewport().set_input_as_handled()
  return
 # A false route result allows the MODAL'S GUI only. Never fall through to HOME.
 if is_instance_valid(controller_panel) and controller_panel.is_open():
  if controller_panel.route_input(event): get_viewport().set_input_as_handled()
  return
 if controller_background_blocked or controller_release_gate:
  if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed):
   controller_release_elapsed = 0.0
  get_viewport().set_input_as_handled()
  return
 if _controller_click_input(event):
  get_viewport().set_input_as_handled()
  return
 _observe_input_device(event)
 if library_state != "system":
  if library_state == "library":
   if library_view.handle_event(event): get_viewport().set_input_as_handled()
   return
  elif input_profile.action_for(event) == "back" or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE): leave_library()
  get_viewport().set_input_as_handled()
  return
 if _settings_input(event):
  get_viewport().set_input_as_handled()
  return
 if settings_panel.visible:
  if input_profile.action_for(event) == "confirm":
   _activate_focused_control()
   get_viewport().set_input_as_handled()
  return
 if event is InputEventKey and event.pressed and event.echo:
  var repeatable_navigation: bool = inspect_mode and event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN] and event.keycode not in input_profile.keys.values()
  var repeatable_zoom: bool = inspect_mode and event.keycode in [KEY_EQUAL,KEY_PLUS,KEY_KP_ADD,KEY_MINUS,KEY_KP_SUBTRACT] and event.keycode not in input_profile.keys.values()
  if not repeatable_navigation and not repeatable_zoom:
   get_viewport().set_input_as_handled()
   return
 if event is InputEventMouseMotion:
  dwell_uses_mouse = true
  mouse_dwell_rearm_allowed = true
  if hovering and not history_open and not inspect_mode: auto_history_armed = true
 elif (event is InputEventKey and event.pressed) or (event is InputEventJoypadButton and event.pressed): dwell_uses_mouse = false
 if event is InputEventMouseMotion or (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed): reset_dwell()
 var action: String = input_profile.action_for(event)
 if not action.is_empty():
  match action:
   "confirm": _activate_focused_control()
   "back": go_back()
   "inspect": toggle_inspection()
   "motion": toggle_motion(); _refresh_controls()
   "reset":
    if inspect_mode: reset_inspection()
  get_viewport().set_input_as_handled()
  return
 if _inspection_input(event):
  get_viewport().set_input_as_handled()
  return
 if event is InputEventMouseButton and event.pressed and event.double_click and console_button.get_global_rect().has_point(event.position):
  get_viewport().set_input_as_handled()
  return
 if event is InputEventKey and event.pressed:
  match event.keycode:
   KEY_F1: toggle_control_settings(); get_viewport().set_input_as_handled()
   KEY_ESCAPE: go_back(); get_viewport().set_input_as_handled()
   KEY_LEFT: navigate(-1); get_viewport().set_input_as_handled()
   KEY_RIGHT: navigate(1); get_viewport().set_input_as_handled()
   KEY_PAGEDOWN:
    if history_open: history_scroll.scroll_vertical += 220; get_viewport().set_input_as_handled()
   KEY_PAGEUP:
    if history_open: history_scroll.scroll_vertical -= 220; get_viewport().set_input_as_handled()
   KEY_ENTER,KEY_KP_ENTER,KEY_SPACE:
    _activate_focused_control()
    get_viewport().set_input_as_handled()
 if event is InputEventJoypadButton and event.pressed:
  if event.button_index in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]:
   var direction := -1 if event.button_index == JOY_BUTTON_DPAD_LEFT else 1
   if console_button.has_focus(): navigate(direction)
   else:
    var focused := get_viewport().gui_get_focus_owner()
    if focused:
     var target := focused.focus_previous if direction < 0 else focused.focus_next
     if not target.is_empty(): focused.get_node(target).grab_focus()
   get_viewport().set_input_as_handled()
  elif history_open and event.button_index in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN]:
   history_scroll.scroll_vertical += -120 if event.button_index == JOY_BUTTON_DPAD_UP else 120
   get_viewport().set_input_as_handled()
 if event is InputEventJoypadMotion and not inspect_mode and not history_open and event.axis == JOY_AXIS_LEFT_X:
  if absf(event.axis_value) < 0.3: axis_navigation_held = false
  elif absf(event.axis_value) > 0.6 and not axis_navigation_held:
   axis_navigation_held = true
   navigate(-1 if event.axis_value < 0 else 1)

func _process(delta: float) -> void:
 if not scene_active or not application_focused: return
 if controller_release_gate:
  _advance_controller_release_gate(delta,_controller_inputs_neutral())
  return
 if _controller_blocks_background(): return
 _update_perspective_box_frame()
 if settings_panel.visible: return
 if library_state != "system":
  cooldown = maxf(0.0,cooldown-delta)
  if not reduced_motion: elapsed += delta
  bg_material.set_shader_parameter("animation_time",elapsed)
  return
 if inspect_mode and input_device == "gamepad" and active_pad in Input.get_connected_joypads():
  var direction := Vector2(Input.get_joy_axis(active_pad,JOY_AXIS_LEFT_X),Input.get_joy_axis(active_pad,JOY_AXIS_LEFT_Y))
  if direction.length() > 0.25: rotate_inspection(direction * delta * 180.0)
  var zoom_axis := Input.get_joy_axis(active_pad,JOY_AXIS_RIGHT_Y)
  if absf(zoom_axis) > 0.25: zoom_inspection(-zoom_axis * delta * 0.5)
 _advance_dwell(delta)
 if history_transition and history_transition.is_running(): _layout()
 _update_hit_rect()
 cooldown = maxf(0.0,cooldown-delta)
 if not reduced_motion: elapsed += delta
 bg_material.set_shader_parameter("animation_time",elapsed)
 bg_material.set_shader_parameter("parallax",Vector2.ZERO if reduced_motion else (get_viewport().get_mouse_position()/get_viewport().get_visible_rect().size-Vector2.ONE*0.5))
 presentation.position.y = 0.0 if reduced_motion or inspect_mode else sin(elapsed*0.7)*0.003
 fill_light.light_energy = lerpf(fill_light.light_energy,1.0 if hovering or console_button.has_focus() else 0.8,minf(delta*8,1.0))

func _controller_blocks_background() -> bool:
 return controller_background_blocked or controller_release_gate or (is_instance_valid(controller_panel) and controller_panel.is_open())

func _set_background_blocked(value: bool) -> void:
 controller_background_blocked = value
 inspection_dragging = false
 controller_click_port = -1
 controller_click_active = false
 hovering = false
 axis_navigation_held = false
 reset_dwell()
 auto_history_armed = false
 mouse_dwell_rearm_allowed = false
 if is_instance_valid(library_view): library_view.cancel_drag()
 if value:
  controller_saved_button_states.clear()
  controller_saved_pointer_states.clear()
  var buttons: Array = footer.get_children()
  buttons.append(console_button)
  for button in buttons:
   if button is BaseButton:
    controller_saved_button_states[button] = button.disabled
    controller_saved_pointer_states[button] = {"tooltip":button.tooltip_text,"mouse_filter":button.mouse_filter}
    button.disabled = true
    button.tooltip_text = ""
    button.mouse_filter = Control.MOUSE_FILTER_IGNORE
    # Godot 4.6's tooltip setter does not dismiss an already-open tooltip.
    # Hide/show within this same frame invokes the public visibility cleanup,
    # cancelling that owner's tooltip without touching model/camera or layout.
    var was_visible: bool = button.visible
    if was_visible:
     button.hide()
     button.show()
  controller_history_paused = history_transition != null and history_transition.is_running()
  if controller_history_paused: history_transition.pause()
 else:
  for button in controller_saved_button_states:
   if is_instance_valid(button): button.disabled = controller_saved_button_states[button]
  controller_saved_button_states.clear()
  for button in controller_saved_pointer_states:
   if is_instance_valid(button):
    button.tooltip_text = controller_saved_pointer_states[button].tooltip
    button.mouse_filter = controller_saved_pointer_states[button].mouse_filter
  controller_saved_pointer_states.clear()
  if controller_history_paused and scene_active and application_focused and history_transition and history_transition.is_valid():
   history_transition.play()
  controller_history_paused = false

func _open_controller_settings(port: int, return_focus: Control = null, opening_event: InputEvent = null) -> void:
 if port not in [0,1] or not scene_active or not application_focused or _controller_blocks_background(): return
 if library_state != "system" or transition_busy or systems.is_empty(): return
 if systems[current_index].system_id != "sega_master_system": return
 controller_return_focus = return_focus if is_instance_valid(return_focus) else get_viewport().gui_get_focus_owner()
 controller_return_settings = settings_panel.visible
 # Hide the old settings without its toggle/focus side effects, retaining selection.
 settings_panel.hide()
 _set_background_blocked(true)
 var gesture := opening_event if opening_event != null else controller_last_event
 # Host restores focus only after its final release gate, not while keys are held.
 if not controller_panel.open_player(port,null,gesture):
  _set_background_blocked(false)
  _restore_controller_focus()

func _controller_panel_closed(_port: int) -> void:
 controller_release_gate = true
 controller_release_elapsed = 0.0
 reset_dwell()

func _controller_inputs_neutral() -> bool:
 if media_release_gate:
  if not media_input_snapshot.neutral(media_release_device, true): return false
  # Inspection uses vector magnitude, not independent axis deadzones. A diagonal
  # (0.2,0.2) must not restart rotation after modal dismissal.
  for device in [media_release_device, media_input_snapshot.opening_device]:
   if device < 0: continue
   var direction := Vector2.ZERO
   if media_input_snapshot.poll_physical:
    if device not in Input.get_connected_joypads(): continue
    direction = Vector2(Input.get_joy_axis(device,JOY_AXIS_LEFT_X),Input.get_joy_axis(device,JOY_AXIS_LEFT_Y))
   else:
    var axes: Dictionary = media_input_snapshot.axes.get(device,{})
    direction = Vector2(float(axes.get(JOY_AXIS_LEFT_X,0.0)),float(axes.get(JOY_AXIS_LEFT_Y,0.0)))
   if not direction.is_finite() or direction.length() > 0.25: return false
  return true
 # The panel retains its ledger after closing, including the pinned device and
 # opening gesture. Never let drift from an unrelated pad deadlock return.
 if is_instance_valid(controller_panel): return controller_panel.release_inputs_neutral()
 return not Input.is_anything_pressed()

func _advance_controller_release_gate(delta: float, all_neutral: bool) -> void:
 if not controller_release_gate: return
 controller_release_elapsed = controller_release_elapsed + maxf(delta,0.0) if all_neutral else 0.0
 if controller_release_elapsed < CONTROLLER_RELEASE_SECONDS: return
 controller_release_gate = false
 media_release_gate = false
 controller_release_elapsed = 0.0
 _set_background_blocked(false)
 if active_pad >= 0 and active_pad not in Input.get_connected_joypads(): _set_input_device("keyboard")
 _restore_controller_focus()
 cooldown = maxf(cooldown,0.4)

func _restore_controller_focus() -> void:
 settings_panel.visible = controller_return_settings
 _refresh_controls()
 if is_instance_valid(controller_return_focus) and controller_return_focus.is_visible_in_tree() and controller_return_focus.focus_mode != Control.FOCUS_NONE:
  controller_return_focus.grab_focus()
 elif settings_panel.visible: family_selector.grab_focus()
 elif inspect_mode or history_open: inspect_button.grab_focus()
 else: console_button.grab_focus()
 # grab_focus emits existing dwell-arm callbacks: deliberately disarm AFTER it.
 auto_history_armed = false
 mouse_dwell_rearm_allowed = false
 reset_dwell()
 controller_return_focus = null
 controller_return_settings = false

func _controller_home_eligible() -> bool:
 if not scene_active or not application_focused or _controller_blocks_background(): return false
 if library_state != "system" or inspect_mode or inspection_dragging or history_open or history_blend > 0.001 or transition_busy: return false
 if settings_panel.visible or (history_transition != null and history_transition.is_running()): return false
 if is_instance_valid(entry_veil) and entry_veil.visible: return false
 return is_instance_valid(exhibit) and exhibit.is_visible_in_tree() and is_instance_valid(camera)

func _pick_home_controller(window_position: Vector2) -> int:
 if not _controller_home_eligible(): return -1
 var rect := viewport_container.get_global_rect()
 if not rect.has_point(window_position) or rect.size.x <= 0.0 or rect.size.y <= 0.0: return -1
 if viewport.size.x <= 1 or viewport.size.y <= 1: return -1
 # Match this SubViewportContainer's stretched content, including window scale.
 var local_point := viewport_container.get_global_transform_with_canvas().affine_inverse() * window_position
 var point := local_point / viewport_container.size * Vector2(viewport.size)
 # The approved perspective box is drawn in a different, composited viewport.
 # Its REAL triangles occlude clicks here too; its transparent frame does not.
 if is_instance_valid(perspective_box_view) and perspective_box_view.is_visible_in_tree() and is_instance_valid(perspective_box_view.box):
  var box_rect: Rect2 = perspective_box_view.get_global_rect()
  if box_rect.has_point(window_position) and box_rect.size.x > 0.0 and box_rect.size.y > 0.0:
   var box_local: Vector2 = perspective_box_view.get_global_transform_with_canvas().affine_inverse() * window_position
   var box_point: Vector2 = box_local / perspective_box_view.size * Vector2(perspective_box_view.viewport.size)
   var box_camera: Camera3D = perspective_box_view.camera
   if not controller_picker.nearest_hit([perspective_box_view.box],box_camera.project_ray_origin(box_point),box_camera.project_ray_normal(box_point),box_camera.far,box_camera.cull_mask).is_empty(): return -1
 return exhibit.pick_controller(camera.project_ray_origin(point),camera.project_ray_normal(point))

func _controller_click_input(event: InputEvent) -> bool:
 if event is InputEventMouseMotion and controller_click_active:
  controller_click_max_distance = maxf(controller_click_max_distance,event.position.distance_to(controller_click_origin))
  if controller_click_max_distance > CONTROLLER_CLICK_SLOP: controller_click_port = -1
  return true
 if not event is InputEventMouseButton: return false
 if event.button_index != MOUSE_BUTTON_LEFT:
  if controller_click_active: controller_click_port = -1
  return false
 if event.pressed:
  if controller_click_active: return true
  var port := _pick_home_controller(event.position)
  if port < 0: return false
  controller_click_active = true
  controller_click_port = -1 if event.double_click else port
  controller_click_origin = event.position
  controller_click_max_distance = 0.0
  reset_dwell()
  return true
 if not controller_click_active: return false
 var selected_port := controller_click_port
 controller_click_active = false
 controller_click_port = -1
 controller_click_max_distance = maxf(controller_click_max_distance,event.position.distance_to(controller_click_origin))
 if selected_port >= 0 and controller_click_max_distance <= CONTROLLER_CLICK_SLOP and _pick_home_controller(event.position) == selected_port:
  _open_controller_settings(selected_port,null,event)
 return true

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
 await get_tree().create_timer(1.6).timeout
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png("res://evidence/cosmic/03_confirmacao.png")
 if library_state != "system": leave_library()
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

func _build_library() -> void:
 library_view = load("res://cosmic/library_view.gd").new()
 ui.get_parent().add_child(library_view)
 library_view.configure(self)
 library_view.begin_catalog_visit()
 library_view.exit_requested.connect(leave_library)
 library_view.hide()
 sms_library_view = library_view
 entry_veil = ColorRect.new()
 entry_veil.color = Color(0.015,0.02,0.05,0)
 entry_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
 ui.get_parent().add_child(entry_veil)
 entry_veil.hide()

func _activate_system_library() -> void:
 entry_generation += 1
 if not library_enabled or not is_instance_valid(sms_library_view): return
 if is_instance_valid(library_view): library_view.close()
 if AtariBridge.handles(systems[current_index]):
  if not is_instance_valid(atari_library_view):
   atari_library_view = AtariBridge.create_library(ui.get_parent(),self)
   atari_library_view.exit_requested.connect(leave_library)
  library_view = atari_library_view
 else:
  library_view = sms_library_view
 library_view.begin_catalog_visit()

func enter_library() -> void:
 if _controller_blocks_background(): return
 if library_state != "system" or not scene_active or not application_focused or not is_instance_valid(library_view): return
 entry_generation += 1
 entry_library_id = library_view.get_instance_id()
 entry_autostart_token = library_view.arm_entry_autostart() if library_view.has_method("arm_entry_autostart") else -1
 reset_dwell()
 auto_history_armed = false
 inspection_dragging = false
 library_state = "entering"
 _sync_exhibit_visibility()
 entry_start_size = camera.size
 entry_start_camera_position = camera.position
 entry_start_camera_target = camera.position-camera.basis.z*camera.position.distance_to(systems[current_index].camera_target)
 presentation.position = Vector3.ZERO
 ui.hide()
 entry_veil.show()
 if reduced_motion:
  _finish_library_entry(entry_generation)
  return
 entry_tween = create_tween()
 entry_tween.tween_method(_apply_entry_for_visit.bind(entry_generation),0.0,1.0,1.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
 entry_tween.tween_callback(_finish_library_entry.bind(entry_generation))

func _apply_entry_for_visit(value: float, expected_generation: int) -> void:
 if expected_generation != entry_generation or library_state != "entering": return
 _apply_entry(value)

func _apply_entry(value: float) -> void:
 entry_progress = value
 _sync_exhibit_visibility()
 bg_material.set_shader_parameter("entry_warp",0.0 if reduced_motion else sin(value*PI))
 var data = systems[current_index]
 var s := get_viewport().get_visible_rect().size
 var exhibit_layout := is_instance_valid(exhibit)
 viewport_container.position = Vector2(s.x*0.08,s.y*(0.10 if exhibit_layout else 0.18)).lerp(Vector2.ZERO,value)
 viewport_container.size = Vector2(s.x*0.84,s.y*(0.53 if exhibit_layout else 0.44)).lerp(s,value)
 camera.position = entry_start_camera_position.lerp(Vector3(0.035,0.07,0.16),value)
 camera.look_at(entry_start_camera_target.lerp(data.camera_target,value))
 camera.size = lerpf(entry_start_size,0.038,value)
 entry_veil.color.a = smoothstep(0.48,0.94,value)
 _update_perspective_box_frame()

func _finish_library_entry(expected_generation: int = -1) -> void:
 if expected_generation < 0: expected_generation = entry_generation
 if expected_generation != entry_generation or library_state != "entering": return
 if not is_instance_valid(library_view) or library_view.get_instance_id() != entry_library_id: return
 bg_material.set_shader_parameter("entry_warp",0.0)
 library_state = "library"
 _sync_exhibit_visibility()
 viewport_container.hide()
 viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 library_view.open()
 entry_veil.color.a = 1.0
 if reduced_motion:
  _complete_library_reveal(expected_generation,entry_library_id,entry_autostart_token)
 else:
  entry_tween = create_tween()
  entry_tween.tween_property(entry_veil,"color:a",0.0,0.35)
  entry_tween.tween_callback(_complete_library_reveal.bind(expected_generation,entry_library_id,entry_autostart_token))
 print("COSMIC_LIBRARY opened template_only=true")

func _complete_library_reveal(expected_generation: int, expected_library_id: int, autostart_token: int) -> void:
 if expected_generation != entry_generation or library_state != "library": return
 if not is_instance_valid(library_view) or library_view.get_instance_id() != expected_library_id: return
 entry_veil.hide()
 if not scene_active or not application_focused:
  if library_view.has_method("cancel_pending_autostart"): library_view.cancel_pending_autostart()
  return
 if library_view.has_method("complete_entry_autostart"):
  library_view.complete_entry_autostart(autostart_token)

func leave_library() -> void:
 entry_generation += 1
 if library_state == "system": return
 if entry_tween and entry_tween.is_valid(): entry_tween.kill()
 entry_paused = false
 library_view.close()
 entry_veil.hide()
 entry_veil.color.a = 0.0
 library_state = "system"
 _rebuild_exhibit()
 entry_progress = 0.0
 bg_material.set_shader_parameter("entry_warp",0.0)
 ui.show()
 viewport_container.show()
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if scene_active else SubViewport.UPDATE_DISABLED
 camera.position = systems[current_index].camera_position
 presentation.position = Vector3.ZERO
 presentation.scale = Vector3.ONE
 _layout()
 console_button.grab_focus()
 auto_history_armed = false
 mouse_dwell_rearm_allowed = false
 reset_dwell()
 cooldown = 0.4
 print("COSMIC_LIBRARY closed")

func _qa_sixteen_nine() -> void:
 await get_tree().process_frame
 await get_tree().process_frame
 get_window().size = Vector2i(1152,648)


func _build_local_media_host() -> void:
 media_button = _action_button("local_media","Mídia local","Configuração opcional · sem download",_open_local_media)
 footer.add_child(media_button)
 media_host = LocalMediaHost.new()
 media_host.name = "LocalMediaOptionalGuide"
 media_host.profile = input_profile
 media_host.catalog_getter = _local_media_inventory
 media_host.catalog_apply = _apply_local_media
 media_host.can_apply = func(): return not transition_busy
 media_host.launcher = media_button
 var local_theme := Theme.new()
 local_theme.default_font = chakra
 local_theme.default_font_size = 16
 media_host.theme = local_theme
 ui.get_parent().add_child(media_host)
 media_host.opened.connect(func(): _set_background_blocked(true))
 media_host.closed.connect(func():
  controller_release_gate = true
  media_release_gate = true
  controller_release_elapsed = 0.0
  reset_dwell())

func _open_local_media() -> void:
 if _controller_blocks_background() or library_state != "system" or transition_busy: return
 controller_return_focus = media_button
 controller_return_settings = settings_panel.visible
 settings_panel.hide()
 media_release_device = active_pad
 media_input_snapshot.mark_opening(controller_last_event)
 media_host.open_panel()

func _local_media_inventory() -> Array:
 # Already-loaded metadata only. No scan, file-open, name/edition inference.
 var items: Array = []
 for view in [sms_library_view,atari_library_view]:
  if is_instance_valid(view): items.append_array(view.ITEMS.duplicate(true))
 return items

func _apply_local_media(result: Dictionary) -> int:
 # Apply to this session only; original catalog file and source media untouched.
 # Only metadata is changed here; visible meshes/textures refresh on normal navigation.
 # Current decode/hash + identity checks completed on the worker.
 var updated: Array = result.get("items",[])
 var cache = load("res://cosmic/library_artwork_cache.gd").shared()
 for path in result.get("changed_paths",[]): cache.invalidate(str(path))
 for view in [sms_library_view,atari_library_view]:
  if not is_instance_valid(view): continue
  for i in view.ITEMS.size():
   var old: Dictionary = view.ITEMS[i]
   for item in updated:
    if item.get("id","") == old.get("id","") and item.get("system","") == old.get("system",""):
     for field in ["cover_front","cover_back","cover_spine","cover_edge","cartridge_label","cartridge_top","wheel"]:
      if item.get(field,"") != old.get(field,""): cache.invalidate(str(item.get(field,"")))
     if view == sms_library_view and (item != old or not result.get("changed_paths",[]).is_empty()): view.local_media_refresh_pending = true
     view.ITEMS[i] = item.duplicate(true)
     break
  view.catalog_choice.update_catalog(view.ITEMS)
 return int(result.get("applied",0))
