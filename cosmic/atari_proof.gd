extends Node3D
## Independent proof scene. Opt in via RETROPASS_ATARI_MEDIA_MANIFEST only.
const Adapter = preload("res://cosmic/atari_system_adapter.gd")
var exhibit: Node3D
var pivot: Node3D
var camera: Camera3D
var status: Label
var dragging := false
var start_rotation := Vector3.ZERO
var distance := 1.12

func _ready() -> void:
 pivot = Node3D.new()
 add_child(pivot)
 var manifest := OS.get_environment("RETROPASS_ATARI_MEDIA_MANIFEST")
 exhibit = Adapter.create_exhibit(manifest, not manifest.is_empty())
 pivot.add_child(exhibit)
 _make_camera_and_light()
 _make_ui()
 get_window().focus_exited.connect(_cancel_drag)

func _make_camera_and_light() -> void:
 camera = Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.near = 0.01
 camera.far = 10.0
 camera.current = true
 add_child(camera)
 _reset_view()
 var environment := WorldEnvironment.new()
 var settings := Environment.new()
 settings.background_mode = Environment.BG_COLOR
 settings.background_color = Color(0.009, 0.014, 0.026)
 settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 settings.ambient_light_color = Color(0.80, 0.86, 1.0)
 settings.ambient_light_energy = 0.50
 settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 environment.environment = settings
 add_child(environment)
 var key := DirectionalLight3D.new()
 key.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
 key.light_energy = 1.1
 add_child(key)
 var fill := DirectionalLight3D.new()
 fill.rotation_degrees = Vector3(-28.0, 150.0, 0.0)
 fill.light_energy = 0.35
 add_child(fill)

func _make_ui() -> void:
 var layer := CanvasLayer.new()
 add_child(layer)
 var margin := MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 margin.add_theme_constant_override("margin_left", 20)
 margin.add_theme_constant_override("margin_right", 20)
 margin.add_theme_constant_override("margin_top", 16)
 margin.add_theme_constant_override("margin_bottom", 16)
 margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
 layer.add_child(margin)
 var column := VBoxContainer.new()
 column.mouse_filter = Control.MOUSE_FILTER_IGNORE
 margin.add_child(column)
 var title := Label.new()
 title.text = "Atari 2600 · prova privada de integração"
 title.add_theme_font_size_override("font_size", 25)
 column.add_child(title)
 var subtitle := Label.new()
 subtitle.text = "Heavy Sixer + CX10 · metros nativos · sem ROM ou emulação"
 column.add_child(subtitle)
 var spacer := Control.new()
 spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
 spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
 column.add_child(spacer)
 status = Label.new()
 status.text = exhibit.status_text()
 status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 status.add_theme_font_size_override("font_size", 14)
 column.add_child(status)
 var buttons := HBoxContainer.new()
 column.add_child(buttons)
 _button(buttons, "Abrir/fechar abas", _toggle_carton)
 _button(buttons, "Cartucho: pose de encaixe", _toggle_cartridge)
 _button(buttons, "Restaurar vista", _reset_view)
 _button(buttons, "Fechar prova", _close_proof)
 var help := Label.new()
 help.text = "Arrastar: girar · roda: zoom · setas: girar · R: restaurar · Esc: fechar. Sem movimento automático."
 help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 help.add_theme_font_size_override("font_size", 13)
 column.add_child(help)

func _button(row: HBoxContainer, text: String, action: Callable) -> void:
 var button := Button.new()
 button.text = text
 button.pressed.connect(action)
 button.button_down.connect(_cancel_drag)
 row.add_child(button)

func _toggle_carton() -> void:
 if not exhibit.set_carton_open(not exhibit.carton_open):
  status.text = "Abas originais ausentes. Nenhum mecanismo SMS foi usado."

func _toggle_cartridge() -> void:
 if exhibit.set_cartridge_seated(not exhibit.cartridge_seated):
  status.text = exhibit.status_text()
 else:
  status.text = "Console ou cartucho ausente. Nenhum cartucho substituto foi criado."

func _input(event: InputEvent) -> void:
 # Release must cancel even when GUI consumes the event before _unhandled_input.
 if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
  _cancel_drag()

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_LEFT:
   dragging = event.pressed
  elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
   distance = clampf(distance * 0.90, 0.45, 2.2)
   _update_camera()
  elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
   distance = clampf(distance / 0.90, 0.45, 2.2)
   _update_camera()
 elif event is InputEventMouseMotion and dragging:
  if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
   _cancel_drag()
   return
  pivot.rotation.y += event.relative.x * 0.006
  pivot.rotation.x = clampf(pivot.rotation.x + event.relative.y * 0.006, -1.2, 1.2)
 elif event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_ESCAPE: _close_proof()
   KEY_R: _reset_view()
   KEY_LEFT: pivot.rotation.y -= 0.12
   KEY_RIGHT: pivot.rotation.y += 0.12
   KEY_UP: pivot.rotation.x = clampf(pivot.rotation.x - 0.12, -1.2, 1.2)
   KEY_DOWN: pivot.rotation.x = clampf(pivot.rotation.x + 0.12, -1.2, 1.2)

func _cancel_drag() -> void:
 dragging = false

func _reset_view() -> void:
 _cancel_drag()
 pivot.rotation = start_rotation
 distance = 1.12
 _update_camera()

func _update_camera() -> void:
 camera.size = distance
 camera.position = Vector3(0.36, 0.62, 0.92)
 camera.look_at(Vector3(0.0, 0.06, 0.0))

func _close_proof() -> void:
 _cancel_drag()
 get_tree().quit()
