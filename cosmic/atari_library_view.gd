extends Control
## Atari-only 3D collection/inspection checkpoint; deliberately no SMS GameBox or flat manual reader.
signal exit_requested
const Exhibit = preload("res://cosmic/atari_exhibit.gd")
var host: Node
var ITEMS: Array[Dictionary] = []
var current_index := 0
var exhibit: Node3D
var pivot: Node3D
var viewport: SubViewport
var viewport_container: SubViewportContainer
var camera: Camera3D
var heading: Label
var status: Label
var buttons: HFlowContainer
var action_buttons: Dictionary = {}
var back_button: Button
var state := "closed"
var inspection_role := ""
var dragging := false
var zoom := 1.0
var manual_turns := 0
var manual_leaves: Array[Node3D] = []
var manual_rest: Array[Transform3D] = []
var rest_transforms: Dictionary = {}
var media_path := ""
var media_loaded := false

func configure(owner_host: Node) -> void:
 host = owner_host
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 viewport_container = SubViewportContainer.new()
 viewport_container.stretch = true
 viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(viewport_container)
 viewport = SubViewport.new()
 viewport.own_world_3d = true
 viewport.transparent_bg = true
 viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 viewport_container.add_child(viewport)
 pivot = Node3D.new()
 viewport.add_child(pivot)
 exhibit = Exhibit.new()
 pivot.add_child(exhibit)
 media_path = OS.get_environment("RETROPASS_ATARI_MEDIA_MANIFEST")
 # Selector setup reads only identity; GLBs load when the user enters this library.
 if exhibit.media.configure(media_path, not media_path.is_empty()):
  ITEMS.append({"id": str(exhibit.media.manifest.game.id), "title": str(exhibit.media.manifest.game.title), "system_id": "atari2600"})
 else:
  ITEMS.append({"id":"unavailable", "title":"Mídia Atari indisponível", "system_id":"atari2600"})
 camera = Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.near = 0.005
 camera.far = 10.0
 camera.current = true
 viewport.add_child(camera)
 var environment := WorldEnvironment.new()
 var settings := Environment.new()
 settings.background_mode = Environment.BG_COLOR
 settings.background_color = Color(0,0,0,0)
 settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 settings.ambient_light_color = Color("d8e5ff")
 settings.ambient_light_energy = 0.65
 environment.environment = settings
 viewport.add_child(environment)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-50,-35,0)
 light.light_energy = 1.2
 viewport.add_child(light)
 _build_ui()
 _frame()
 hide()

func _build_ui() -> void:
 var margin := MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for edge in ["left","right","top","bottom"]:
  margin.add_theme_constant_override("margin_"+edge,20)
 margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(margin)
 var column := VBoxContainer.new()
 column.mouse_filter = Control.MOUSE_FILTER_IGNORE
 margin.add_child(column)
 heading = Label.new()
 heading.text = "Atari 2600 · " + str(ITEMS[0].title)
 heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 heading.add_theme_font_size_override("font_size",24)
 column.add_child(heading)
 var spacer := Control.new()
 spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
 spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
 column.add_child(spacer)
 status = Label.new()
 status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 column.add_child(status)
 buttons = HFlowContainer.new()
 column.add_child(buttons)
 action_buttons.box = _button("Inspecionar caixa",func(): inspect("box"))
 action_buttons.cartridge = _button("Cartucho",func(): inspect("cartridge"))
 action_buttons.manual = _button("Manual 3D",func(): inspect("manual"))
 action_buttons.carton = _button("Abrir/fechar caixa",_toggle_carton)
 action_buttons.previous = _button("Página anterior",func(): turn_manual(-1))
 action_buttons.next = _button("Próxima página",func(): turn_manual(1))
 action_buttons.reset = _button("Restaurar vista",reset_inspection)
 back_button = _button("Voltar",go_back)
 _refresh_status()

func _button(text: String, action: Callable) -> Button:
 var button := Button.new()
 button.text = text
 button.custom_minimum_size.y = 48
 button.pressed.connect(action)
 button.button_down.connect(cancel_drag)
 buttons.add_child(button)
 return button

func _find_manual_leaves() -> void:
 if not exhibit.asset_roots.has("manual"): return
 for index in 4:
  var leaf := exhibit.asset_roots.manual.find_child("PAGE_LEAF_%02d_SPINE" % index,true,false) as Node3D
  if leaf == null:
   manual_leaves.clear()
   manual_rest.clear()
   return
  manual_leaves.append(leaf)
  manual_rest.append(leaf.transform)

func begin_catalog_visit() -> void:
 current_index = 0 # Only the explicitly supplied game, never an invented catalogue.

func _load_private_models() -> void:
 if media_loaded: return
 media_loaded = true
 exhibit.configure(media_path, not media_path.is_empty())
 for key in exhibit.asset_roots:
  rest_transforms[key] = exhibit.asset_roots[key].transform
 _find_manual_leaves()

func open() -> void:
 _load_private_models()
 state = "collection"
 inspection_role = ""
 show()
 _restore_collection()
 viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
 layout()
 back_button.grab_focus()

func close() -> void:
 cancel_drag()
 state = "closed"
 _restore_collection()
 viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 hide()

func inspect(role: String) -> bool:
 if state == "closed" or not exhibit.asset_roots.has(role):
  if status: status.text = "Recurso privado ausente; nenhuma substituição criada."
  return false
 cancel_drag()
 _restore_collection()
 inspection_role = role
 state = "inspection"
 for key in exhibit.asset_roots:
  var asset: Node3D = exhibit.asset_roots[key]
  asset.visible = key == role
  if key == role:
   asset.transform = Transform3D.IDENTITY
 reset_inspection()
 _refresh_status()
 back_button.grab_focus()
 return true

func _restore_collection() -> void:
 for key in exhibit.asset_roots:
  exhibit.asset_roots[key].visible = true
  exhibit.asset_roots[key].transform = rest_transforms[key]
 manual_turns = 0
 _apply_manual_turns()
 inspection_role = ""
 reset_inspection()
 _refresh_status()

func turn_manual(direction: int) -> bool:
 if state != "inspection" or inspection_role != "manual" or manual_leaves.size() != 4: return false
 manual_turns = clampi(manual_turns + direction,0,4)
 _apply_manual_turns()
 _refresh_status()
 return true

func _apply_manual_turns() -> void:
 for index in manual_leaves.size():
  var leaf := manual_leaves[index]
  leaf.transform = manual_rest[index]
  # Native source leaves extend +X from a Z-axis spine; positive rotation lifts upward.
  if index < manual_turns:
   leaf.rotate_object_local(Vector3.BACK, PI)
   leaf.position.y = 0.0004 + index * 0.0001

func go_back() -> void:
 if state == "inspection":
  state = "collection"
  _restore_collection()
  back_button.grab_focus()
 elif state != "closed":
  exit_requested.emit()

func reset_inspection() -> void:
 cancel_drag()
 pivot.rotation = Vector3.ZERO
 zoom = 1.0
 _frame()

func _frame() -> void:
 if not is_instance_valid(camera): return
 var ratio := maxf(0.3, float(viewport.size.x)/maxf(1.0,float(viewport.size.y)))
 var target := Vector3(0,0.06,0)
 var base_size := 1.1
 camera.position = Vector3(0.36,0.62,0.92)
 if inspection_role == "manual":
  target = Vector3(0.02,0,0)
  camera.position = Vector3(0.02,0.7,0.08)
  base_size = 0.27
 elif not inspection_role.is_empty():
  target = Vector3(0,0.07,0)
  base_size = 0.40
 camera.look_at(target)
 camera.size = base_size * maxf(1.0,1.4/ratio) / zoom

func layout() -> void:
 if not is_instance_valid(viewport_container): return
 viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _frame()

func cancel_drag() -> void: dragging = false
func refresh_controls() -> void: pass

func _refresh_status() -> void:
 if not is_instance_valid(status): return
 for key in ["box","cartridge","manual"]:
  action_buttons[key].visible = state != "inspection"
  action_buttons[key].disabled = not exhibit.asset_roots.has(key)
 action_buttons.carton.visible = state == "inspection" and inspection_role == "box"
 action_buttons.previous.visible = state == "inspection" and inspection_role == "manual"
 action_buttons.next.visible = action_buttons.previous.visible
 action_buttons.previous.disabled = manual_turns == 0
 action_buttons.next.disabled = manual_turns == manual_leaves.size()
 action_buttons.reset.visible = state == "inspection"
 if inspection_role == "manual":
  status.text = "Manual 3D · " + ["Capa", "Páginas 2–3", "Páginas 4–5", "Páginas 6–7", "Contracapa"][manual_turns] + " · arrastar para girar, roda para ampliar."
 elif state == "inspection":
  status.text = "Inspeção voluntária · arrastar/setas: girar · roda: zoom · R: restaurar · Esc: voltar."
 else:
  if not exhibit.configured:
   status.text = "Mídia privada Atari ausente/desabilitada. Nenhuma arte ou geometria substituta foi criada."
  else:
   status.text = str(ITEMS[0].title) + " · acervo local · sem execução de jogos."
   if not exhibit.missing.is_empty(): status.text += " Recursos ausentes: " + ", ".join(exhibit.missing)
  if exhibit.asset_roots.has("box") or exhibit.asset_roots.has("cartridge") or exhibit.asset_roots.has("manual"):
   status.text += "\nInspecione os recursos disponíveis pelos botões. Animação de inserção em desenvolvimento."

func _toggle_carton() -> void:
 if inspection_role == "manual": return
 exhibit.set_carton_open(not exhibit.carton_open)

func _focusable_actions() -> Array[Button]:
 var result: Array[Button] = []
 for child in buttons.get_children():
  if child is Button and child.is_visible_in_tree() and not child.disabled:
   result.append(child)
 return result

func _move_action_focus(direction: int) -> void:
 cancel_drag()
 var available := _focusable_actions()
 if available.is_empty(): return
 var current := available.find(get_viewport().gui_get_focus_owner())
 available[posmod(current + direction, available.size())].grab_focus()

func _activate_focused_action() -> void:
 var available := _focusable_actions()
 var focused := get_viewport().gui_get_focus_owner()
 if focused in available:
  focused.pressed.emit()
 elif not available.is_empty():
  available[0].grab_focus()

func _direction_input(horizontal: int, vertical: int) -> void:
 if state != "inspection":
  _move_action_focus(horizontal if horizontal != 0 else vertical)
  return
 pivot.rotation.y += horizontal * 0.12
 pivot.rotation.x = clampf(pivot.rotation.x + vertical * 0.12,-1.3,1.3)

func handle_event(event: InputEvent) -> bool:
 if state == "closed" or not visible: return false
 var profile = host.get("input_profile") if is_instance_valid(host) else null
 var action: String = profile.action_for(event) if profile else ""
 if not action.is_empty():
  match action:
   "confirm": _activate_focused_action()
   "back": go_back()
   "reset":
    if state == "inspection": reset_inspection()
  return true
 # Held physical bindings must not leak into native GUI repeat handling.
 if event is InputEventKey and event.pressed and event.echo and profile:
  var physical: int = event.physical_keycode if event.physical_keycode else event.keycode
  if physical in profile.keys.values(): return true
 if event is InputEventJoypadButton and event.pressed:
  match event.button_index:
   JOY_BUTTON_DPAD_LEFT: _move_action_focus(-1)
   JOY_BUTTON_DPAD_RIGHT: _move_action_focus(1)
   JOY_BUTTON_DPAD_UP: _move_action_focus(-1)
   JOY_BUTTON_DPAD_DOWN: _move_action_focus(1)
   _: return false
  return true
 if event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
   cancel_drag()
   return false
  # GUI owns pointer gestures over controls; it must never rotate the asset.
  var hovered := get_viewport().gui_get_hovered_control()
  if hovered != null and hovered != viewport_container and hovered != self: return false
  if event.button_index == MOUSE_BUTTON_LEFT:
   dragging = event.pressed
   return true
  if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
   zoom = clampf(zoom*(1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.1),0.6,3.0)
   _frame()
   return true
 elif event is InputEventMouseMotion and dragging:
  if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
   cancel_drag()
   return false
  pivot.rotation.y += event.relative.x*0.006
  pivot.rotation.x = clampf(pivot.rotation.x+event.relative.y*0.006,-1.3,1.3)
  return true
 elif event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_ESCAPE: go_back()
   KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _activate_focused_action()
   KEY_R:
    if state == "inspection": reset_inspection()
   KEY_LEFT: _direction_input(-1,0)
   KEY_RIGHT: _direction_input(1,0)
   KEY_UP: _direction_input(0,-1)
   KEY_DOWN: _direction_input(0,1)
   _: return false
  return true
 return false
