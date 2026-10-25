extends Control
## Contextual SMS-only modal. Host routes before HOME/library and always returns.
const Profile = preload("res://cosmic/sms_mapping_profile.gd")
const Capture = preload("res://cosmic/controller_capture_session.gd")
const Store = preload("res://cosmic/controller_profile_store.gd")
const Snapshot = preload("res://cosmic/controller_input_snapshot.gd")
const Symbols = preload("res://cosmic/controller_symbols.gd")
const ModelView = preload("res://cosmic/controller_model_view.gd")
const NAMES := {"up": "Cima", "down": "Baixo", "left": "Esquerda", "right": "Direita", "button_1": "Botão 1 · 1 START", "button_2": "Botão 2", "pause": "Pause · botão do console"}
signal closed(port: int)
signal profile_saved(port: int)
var session = Capture.new()
var store = Store.new()
var snapshot = Snapshot.new()
var input_profile: RefCounted
var device_provider := Callable()
var load_model := true # Test harness may disable only the visual loading.
var player := 0
var channel := "keyboard"
var profiles: Array = []
var devices := {0: -1, 1: -1}
var device_names: Dictionary = {}
var mapped_devices: Dictionary = {}
var verified_cancel: Dictionary = {}
var device_authorized: Dictionary = {}
var focused := true
var returning_focus: WeakRef
var last_activation: InputEvent
var pending_port := -1
var pending_close := false
var closing := false
var close_neutral := 0.0
var identification := ""
var identify_ready := false
var identify_neutral := 0.0
var identify_candidate: Dictionary = {}
var testing := false
var test_cancel_device := -1
var test_cancel_button := -1
var test_cancel_elapsed := 0.0
var test_cancel_armed := false
var test_neutral_elapsed := 0.0
var nav_axis_held := false
var ignored_double_click_button := -1
var notice_override := ""
var panel: PanelContainer
var column: VBoxContainer
var body: BoxContainer
var title: Label
var notice: Label
var model_notice: Label
var hint: Label
var model_view: Control
var model_column: VBoxContainer
var list_column: VBoxContainer
var rows: Dictionary = {}
var preferred_actions := {0: "up", 1: "up"}
var player_buttons: Array[Button] = []
var channel_button: Button
var device_row: HFlowContainer
var device_button: Button
var cancel_raw_button: Button
var family_button: Button
var test_button: Button
var save_button: Button
var close_button: Button
var cancel_capture_button: Button
var conflict_box: VBoxContainer
var conflict_text: Label
var swap_button: Button
var conflict_cancel_button: Button
var decision_box: VBoxContainer
var decision_text: Label
var decision_save: Button
var decision_discard: Button
var decision_continue: Button
var shared_box: VBoxContainer
var shared_approval: Array = []
var shared_text: Label
var shared_accept: Button
var shared_cancel: Button
var controls: Array[Button] = []

func _ready() -> void:
 name = "MasterSystemControllerMapping"
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 z_index = 200
 visible = false
 _build()
 resized.connect(_layout)
 if not Input.joy_connection_changed.is_connected(_device_connection_changed): Input.joy_connection_changed.connect(_device_connection_changed)
 _layout()

func setup_host(profile: RefCounted) -> void:
 input_profile = profile

func release_inputs_neutral() -> bool:
 # Reuse the exact gate after closing: keyboard/mouse, pinned device, and opener.
 # An unrelated pad's drift cannot trap the user in the host's final gate.
 var device := int(devices[player])
 return snapshot.neutral(device, _mapped(device))

func gameplay_blocked() -> bool:
 # Reserved integration seam: a future gameplay adapter must output neutral here.
 return is_open() or not focused

func is_open() -> bool:
 return visible and session.state != Capture.State.CLOSED

func _input(event: InputEvent) -> void:
 # Observation only. Capture and routing remain exclusively owned by the host.
 snapshot.observe(event)

func open_player(port: int, return_focus: Control = null, opening_event: InputEvent = null) -> bool:
 if port not in [0, 1] or is_open(): return false
 var loaded: Dictionary = store.load_profiles()
 profiles = loaded.profiles
 if profiles.size() != 2: return false
 if not session.open(profiles[port]): return false
 player = port
 channel = "keyboard"
 focused = true
 closing = false
 pending_close = false
 pending_port = -1
 identification = ""
 testing = false
 notice_override = str(loaded.get("notice", ""))
 returning_focus = weakref(return_focus) if return_focus != null else null
 ignored_double_click_button = -1
 last_activation = opening_event
 snapshot.mark_opening(opening_event)
 if opening_event != null: snapshot.observe(opening_event)
 if opening_event != null and (opening_event is InputEventJoypadButton or opening_event is InputEventJoypadMotion): snapshot.opening_device = opening_event.device
 visible = true
 if load_model: model_view.load_approved_model()
 _rebuild_rows()
 _refresh()
 # Avoid binding or activating the event that opened this modal.
 session.cancel("Selecione um comando na lista ou no próprio controle.")
 _refresh()
 _focus_first.call_deferred()
 return true

func _build() -> void:
 var veil := ColorRect.new()
 veil.color = Color(0.005, 0.012, 0.03, 0.93)
 veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 veil.mouse_filter = Control.MOUSE_FILTER_STOP
 add_child(veil)
 var margin := MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
 add_child(margin)
 panel = PanelContainer.new()
 var style := StyleBoxFlat.new()
 style.bg_color = Color("101a2c")
 style.border_color = Color("446589")
 style.set_border_width_all(1)
 style.set_corner_radius_all(14)
 style.content_margin_left = 18
 style.content_margin_right = 18
 style.content_margin_top = 12
 style.content_margin_bottom = 12
 panel.add_theme_stylebox_override("panel", style)
 margin.add_child(panel)
 column = VBoxContainer.new()
 column.add_theme_constant_override("separation", 7)
 var outer_scroll := ScrollContainer.new()
 outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 outer_scroll.follow_focus = true
 panel.add_child(outer_scroll)
 column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 outer_scroll.add_child(column)
 title = _label("Master System · Jogador 1", 22)
 column.add_child(title)
 var top := HFlowContainer.new()
 top.add_theme_constant_override("h_separation", 8)
 column.add_child(top)
 for port in 2:
  var button := _button("Jogador %d" % (port + 1), func(): request_player(port))
  top.add_child(button)
  player_buttons.append(button)
 channel_button = _button("Entrada: teclado", _toggle_channel)
 top.add_child(channel_button)
 family_button = _button("Símbolos: automático", _cycle_family)
 top.add_child(family_button)
 device_row = HFlowContainer.new()
 column.add_child(device_row)
 device_button = _button("Identificar controle", _identify_device)
 device_row.add_child(device_button)
 cancel_raw_button = _button("Definir botão de cancelar", _identify_cancel)
 device_row.add_child(cancel_raw_button)
 body = BoxContainer.new()
 body.size_flags_vertical = Control.SIZE_EXPAND_FILL
 body.add_theme_constant_override("separation", 16)
 column.add_child(body)
 model_column = VBoxContainer.new()
 model_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 model_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
 body.add_child(model_column)
 model_view = ModelView.new()
 model_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 model_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
 model_column.add_child(model_view)
 model_view.action_selected.connect(begin_capture)
 model_view.action_hovered.connect(_hover_action)
 model_notice = _label("", 13)
 model_column.add_child(model_notice)
 model_view.availability_changed.connect(func(message: String): model_notice.text = message)
 var zoom_row := HBoxContainer.new()
 model_column.add_child(zoom_row)
 zoom_row.add_child(_button("− Zoom", func(): model_view.set_zoom(model_view.zoom - 0.1)))
 zoom_row.add_child(_button("+ Zoom", func(): model_view.set_zoom(model_view.zoom + 0.1)))
 var scroll := ScrollContainer.new()
 scroll.name = "AccessibleCommandList"
 scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.follow_focus = true
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 scroll.custom_minimum_size = Vector2(290, 302)
 body.add_child(scroll)
 list_column = VBoxContainer.new()
 list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 list_column.add_theme_constant_override("separation", 6)
 scroll.add_child(list_column)
 notice = _label("", 16)
 notice.accessibility_live = DisplayServer.LIVE_POLITE
 column.add_child(notice)
 hint = _label("Tab/setas: navegar · Confirmar: selecionar · Esc/F1: voltar. Nenhum jogo é executado.", 13)
 column.add_child(hint)
 cancel_capture_button = _button("Cancelar captura", _cancel_capture)
 column.add_child(cancel_capture_button)
 conflict_box = VBoxContainer.new()
 column.add_child(conflict_box)
 conflict_text = _label("", 15)
 conflict_box.add_child(conflict_text)
 var conflict_row := HFlowContainer.new()
 conflict_box.add_child(conflict_row)
 swap_button = _button("Trocar as duas atribuições", func(): _resolve_conflict(true))
 conflict_row.add_child(swap_button)
 conflict_cancel_button = _button("Cancelar conflito", func(): _resolve_conflict(false))
 conflict_row.add_child(conflict_cancel_button)
 decision_box = VBoxContainer.new()
 column.add_child(decision_box)
 decision_text = _label("Existem alterações ainda não salvas.", 15)
 decision_box.add_child(decision_text)
 var decision_row := HFlowContainer.new()
 decision_box.add_child(decision_row)
 decision_save = _button("Salvar e continuar", func(): save_changes(false))
 decision_row.add_child(decision_save)
 decision_discard = _button("Descartar alterações", _discard_and_continue)
 decision_row.add_child(decision_discard)
 decision_continue = _button("Continuar editando", _continue_editing)
 decision_row.add_child(decision_continue)
 shared_box = VBoxContainer.new()
 column.add_child(shared_box)
 shared_text = _label("", 15)
 shared_box.add_child(shared_text)
 var shared_row := HFlowContainer.new()
 shared_box.add_child(shared_row)
 shared_accept = _button("Compartilhar estas teclas e salvar", func(): save_changes(true))
 shared_row.add_child(shared_accept)
 shared_cancel = _button("Não compartilhar; continuar editando", _cancel_shared)
 shared_row.add_child(shared_cancel)
 var bottom := HFlowContainer.new()
 column.add_child(bottom)
 test_button = _button("Testar entradas · sem emulação", _toggle_test)
 bottom.add_child(test_button)
 save_button = _button("Salvar alterações", func(): save_changes(false))
 bottom.add_child(save_button)
 close_button = _button("Voltar", request_close)
 bottom.add_child(close_button)
 conflict_box.visible = false
 decision_box.visible = false
 shared_box.visible = false

func _label(text: String, font_size := 16) -> Label:
 var label := Label.new()
 label.text = text
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 label.add_theme_font_size_override("font_size", font_size)
 label.add_theme_color_override("font_color", Color("d8e5f4"))
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 return label

func _button(text: String, callback: Callable) -> Button:
 var button := Button.new()
 var icon := "settings"
 var lower := text.to_lower()
 if "jogador" in lower or "controle" in lower or "entradas" in lower: icon = "gamepad"
 if "salvar" in lower: icon = "save"
 if "cancel" in lower or "descartar" in lower or "não compartilhar" in lower: icon = "close"
 if "voltar" in lower: icon = "back"
 if "zoom" in lower: icon = "zoom_in" if "+" in text else "zoom_out"
 if "trocar" in lower: icon = "sort"
 preload("res://cosmic/ui_icons.gd").iconify(button,icon,text)
 button.accessibility_name = text
 button.custom_minimum_size.y = 48
 button.focus_mode = Control.FOCUS_ALL
 button.add_theme_font_size_override("font_size", 15)
 var focus_style := StyleBoxFlat.new()
 focus_style.bg_color = Color(0, 0, 0, 0)
 focus_style.border_color = Color("87e3ff")
 focus_style.set_border_width_all(3)
 focus_style.set_corner_radius_all(6)
 button.add_theme_stylebox_override("focus", focus_style)
 button.pressed.connect(callback)
 controls.append(button)
 return button

func _layout() -> void:
 if not is_instance_valid(body): return
 var narrow := size.x < 650
 body.vertical = narrow
 model_column.visible = true
 model_view.custom_minimum_size.y = 180
 # The outer scroll keeps every action reachable on small windows; no overlay clips it.

func _rebuild_rows() -> void:
 for row in rows.values():
  controls.erase(row)
  row.get_parent().remove_child(row)
  row.queue_free()
 rows.clear()
 for action in session.draft.actions():
  var row := _button(str(NAMES[action]), func(): begin_capture(action))
  row.icon = null
  row.set_meta("binding_content",true)
  row.custom_minimum_size.y = 48
  row.alignment = HORIZONTAL_ALIGNMENT_LEFT
  row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  row.focus_entered.connect(func(): model_view.set_highlight(action))
  list_column.add_child(row)
  rows[action] = row

func _mapped(device: int) -> bool:
 if device_provider.is_valid(): return bool(mapped_devices.get(device, false))
 return device >= 0 and device in Input.get_connected_joypads() and Input.is_joy_known(device)

func _device_name(device: int) -> String:
 if device_provider.is_valid(): return str(device_names.get(device, "Controle sintético"))
 return Input.get_joy_name(device) if device in Input.get_connected_joypads() else str(device_names.get(device, "Controle ausente"))

func _connected_devices() -> Array:
 if device_provider.is_valid(): return device_provider.call()
 return Array(Input.get_connected_joypads())

func _binding_text(value: Dictionary) -> String:
 var glyph: String = Symbols.glyph(value, _device_name(int(devices[player])), session.draft.family_override, _mapped(int(devices[player])))
 return {"ps_cross": "Cruz ×", "ps_circle": "Círculo ○", "ps_square": "Quadrado □", "ps_triangle": "Triângulo △", "south": "Sul", "east": "Leste", "west": "Oeste", "north": "Norte"}.get(glyph, glyph)

func _refresh() -> void:
 if not is_open(): return
 var capture_busy: bool = session.state in [Capture.State.ARMING, Capture.State.CAPTURING, Capture.State.HELD_CANDIDATE, Capture.State.RELEASE_GATE]
 var dialog: bool = decision_box.visible or shared_box.visible or session.state == Capture.State.CONFLICT
 var editing: bool = not capture_busy and not dialog and identification.is_empty() and not closing and not testing and focused
 title.text = "Master System · Jogador %d%s" % [player + 1, " · alterações não salvas" if session.dirty() else ""]
 for port in 2:
  player_buttons[port].disabled = not editing or port == player
 channel_button.text = "Entrada: %s" % ("Teclado" if channel == "keyboard" else "Controle")
 channel_button.disabled = not editing
 device_row.visible = channel == "gamepad"
 family_button.text = "Símbolos: %s" % {"auto": "automático", "xbox": "Xbox", "playstation": "PlayStation", "generic": "genérico"}[session.draft.family_override]
 family_button.disabled = not editing
 var selected_device := int(devices[player])
 var connected := selected_device in _connected_devices()
 device_button.text = "Identificar controle" if selected_device < 0 else "Trocar: %s%s" % [_device_name(selected_device), " · identificar novamente" if not device_authorized.get(selected_device, false) else (" · desconectado" if not connected else "")]
 device_button.disabled = not editing
 cancel_raw_button.visible = selected_device >= 0 and not _mapped(selected_device)
 cancel_raw_button.disabled = not editing or not connected
 for action in rows:
  var row: Button = rows[action]
  var label := "%s   ·   %s" % [NAMES[action], _binding_text(session.draft.bindings[channel][action])]
  row.text = label
  row.tooltip_text = "Jogador %d · %s · %s. Selecionar para remapear." % [player + 1, NAMES[action], _binding_text(session.draft.bindings[channel][action])]
  row.accessibility_name = row.tooltip_text
  row.disabled = not editing
 model_view.interactive = editing
 save_button.disabled = not editing or not session.dirty()
 close_button.disabled = capture_busy or not identification.is_empty() or dialog or closing or testing or not focused
 test_button.disabled = capture_busy or dialog or closing or not focused or not identification.is_empty()
 test_button.text = "Encerrar teste de entradas" if testing else "Testar entradas · sem emulação"
 cancel_capture_button.visible = capture_busy or not identification.is_empty() or testing
 cancel_capture_button.disabled = closing or not focused
 conflict_box.visible = session.state == Capture.State.CONFLICT
 if conflict_box.visible:
  var selected: String = session.selected_action
  var other: String = session.conflict_action
  conflict_text.text = "Conflito: %s já usa %s.\nTrocar: %s recebe %s; %s recebe %s." % [NAMES[other], _binding_text(session.candidate), NAMES[selected], _binding_text(session.candidate), NAMES[other], _binding_text(session.draft.bindings[channel][selected])]
 for control in controls:
  if is_instance_valid(control) and control not in rows.values():
   if not control.text.is_empty():
    control.tooltip_text = control.text
    control.accessibility_name = control.text
   preload("res://cosmic/ui_icons.gd").iconify(control,str(control.get_meta("ui_icon","settings")),control.tooltip_text)
 notice.text = notice_override if not notice_override.is_empty() else session.notice
 if not session.selected_action.is_empty(): notice.text = "%s: %s" % [NAMES[session.selected_action], notice.text]
 if closing: notice.text = "Solte todas as entradas para voltar com segurança."
 elif testing: notice.text = "Teste local de entradas. Os comandos acesos não executam jogo algum. Esc encerra."
 if not identification.is_empty():
  hint.text = "Identificação do controle em andamento. Esc/F1 ou Cancelar captura interrompe."
 elif closing or session.state == Capture.State.RELEASE_GATE:
  hint.text = "Aguarde a soltura das entradas. Nenhuma nova atribuição está sendo capturada."
 elif session.state == Capture.State.ARMING:
  hint.text = "Solte a entrada usada para selecionar o comando; depois aguarde a captura. Esc/F1 cancela."
 elif session.state in [Capture.State.CAPTURING, Capture.State.HELD_CANDIDATE]:
  if channel == "gamepad":
   hint.text = "Toque para atribuir; segure %s por 0,8 s para cancelar. Esc/F1 também cancela. Eixos: 0,65 / 0,25." % (_binding_text({"kind": "button", "code": session.cancel_hold_button}) if session.cancel_hold_button >= 0 else "o botão de cancelar verificado")
  else: hint.text = "Pressione e solte uma tecla física. Esc/F1 cancela. A navegação da interface não será alterada."
 elif session.state == Capture.State.CONFLICT:
  hint.text = "Revise as duas atribuições e escolha Trocar ou Cancelar. Nada muda sem sua escolha."
 elif decision_box.visible or shared_box.visible:
  hint.text = "Escolha uma das opções abaixo para continuar; o rascunho permanece separado do perfil salvo."
 else:
  hint.text = "Escolha um comando no modelo ou na lista para remapear. Tab/setas navegam; Confirmar seleciona."

 if testing:
  hint.text = "Para sair: Esc/F1 ou Encerrar teste. Teclas e botões atribuídos apenas acendem os comandos."
  if test_cancel_button >= 0:
   var cancel_name := "botão leste" if _mapped(test_cancel_device) else "Botão %d" % (test_cancel_button + 1)
   hint.text += " Segure %s por 0,8 s para sair; toque curto continua testável." % cancel_name

func _ordered_buttons(node: Node, result: Array[Button]) -> void:
 for child in node.get_children():
  if child is Button: result.append(child)
  _ordered_buttons(child, result)

func _focusable() -> Array[Button]:
 var result: Array[Button] = []
 var ordered: Array[Button] = []
 _ordered_buttons(self, ordered)
 for button in ordered:
  if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled: continue
  if shared_box.visible and not shared_box.is_ancestor_of(button): continue
  if decision_box.visible and not shared_box.visible and not decision_box.is_ancestor_of(button): continue
  if session.state == Capture.State.CONFLICT and not conflict_box.is_ancestor_of(button): continue
  if not identification.is_empty() and button != cancel_capture_button: continue
  result.append(button)
 return result

func _focus_first() -> void:
 if not is_open(): return
 var available := _focusable()
 var preferred = rows.get(str(preferred_actions.get(player, "up")))
 if preferred in available: preferred.grab_focus()
 elif not available.is_empty(): available[0].grab_focus()

func _move_focus(direction: int) -> void:
 var available := _focusable()
 if available.is_empty(): return
 var index := available.find(get_viewport().gui_get_focus_owner())
 available[posmod(index + direction, available.size())].grab_focus()

func _toggle_channel() -> void:
 channel = "gamepad" if channel == "keyboard" else "keyboard"
 notice_override = ""
 _refresh()

func _cycle_family() -> void:
 var index: int = Profile.FAMILIES.find(session.draft.family_override)
 session.draft.family_override = Profile.FAMILIES[(index + 1) % Profile.FAMILIES.size()]
 _refresh()

func begin_capture(action: String) -> void:
 if testing or not identification.is_empty() or decision_box.visible or shared_box.visible or closing: return
 var device := int(devices[player])
 if channel == "gamepad":
  if device < 0 or device not in _connected_devices() or not device_authorized.get(device, false):
   notice_override = "Identifique explicitamente o controle deste jogador antes de capturar."
   _refresh()
   device_button.grab_focus()
   return
  if not _mapped(device) and not verified_cancel.has(device):
   notice_override = "Controle sem mapeamento conhecido: primeiro defina um botão bruto para cancelar. Eixos exigem calibração e não serão capturados."
   _refresh()
   cancel_raw_button.grab_focus()
   return
 session.cancel_hold_button = int(JOY_BUTTON_B) if _mapped(device) else int(verified_cancel.get(device, -1))
 session.device_connected = device in _connected_devices() if channel == "gamepad" else true
 if session.begin(action, channel, device):
  preferred_actions[player] = action
  notice_override = ""
  snapshot.mark_opening(last_activation)
  model_view.set_highlight(action)
  _refresh()

func _cancel_capture() -> void:
 identification = ""
 identify_candidate.clear()
 testing = false
 notice_override = ""
 session.cancel()
 model_view.cancel_pointer()
 _refresh()

func _resolve_conflict(swap: bool) -> void:
 if session.resolve_conflict(swap):
  notice_override = ""
  _refresh()

func _hover_action(action: String) -> void:
 if not action.is_empty(): model_view.set_highlight(action)
 elif not session.selected_action.is_empty(): model_view.set_highlight(session.selected_action)
 else:
  var owner := get_viewport().gui_get_focus_owner()
  for candidate in rows:
   if rows[candidate] == owner:
    model_view.set_highlight(candidate)
    return
  model_view.set_highlight("")

func _identify_device() -> void:
 identification = "device"
 identify_ready = false
 identify_neutral = 0.0
 identify_candidate.clear()
 snapshot.mark_opening(last_activation)
 notice_override = "Solte as entradas; depois pressione e solte um botão no controle que será o Jogador %d. Esc cancela." % (player + 1)
 _refresh()
 cancel_capture_button.grab_focus()

func _identify_cancel() -> void:
 if int(devices[player]) < 0: return
 identification = "cancel"
 identify_ready = false
 identify_neutral = 0.0
 identify_candidate.clear()
 snapshot.mark_opening(last_activation)
 notice_override = "Solte as entradas; depois pressione e solte o botão bruto que deseja segurar para cancelar."
 _refresh()
 cancel_capture_button.grab_focus()

func _identify_event(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_F1]:
  _cancel_capture()
  return
 if not identify_ready or not event is InputEventJoypadButton: return
 if event.button_index < 0 or event.button_index >= JOY_BUTTON_MAX: return
 if event.device not in _connected_devices(): return
 if identification == "cancel" and event.device != int(devices[player]): return
 if identify_candidate.is_empty() and event.pressed:
  identify_candidate = {"device": event.device, "code": int(event.button_index)}
 elif not event.pressed and event.device == int(identify_candidate.get("device", -1)) and int(event.button_index) == int(identify_candidate.get("code", -1)):
  if identification == "device":
   if int(devices[1 - player]) == event.device:
    notice_override = "Este controle já pertence ao Jogador %d. Escolha outro; nenhuma reassociação foi feita." % (2 - player)
    identify_candidate.clear()
    _refresh()
    return
   devices[player] = event.device
   device_authorized[event.device] = true
   device_names[event.device] = _device_name(event.device)
   session.target_device = event.device
   session.device_connected = true
   channel = "gamepad"
  else: verified_cancel[event.device] = int(event.button_index)
  identification = ""
  identify_candidate.clear()
  notice_override = ""
  session.cancel("Controle identificado explicitamente; escolha um comando.")
  _refresh()

func _device_connection_changed(device: int, connected: bool) -> void:
 if connected: return # Never reassign a reconnect automatically, even when the GUID matches.
 snapshot.forget_device(device)
 verified_cancel.erase(device)
 device_authorized.erase(device)
 if int(devices[player]) == device and is_open():
  session.target_device = device
  session.disconnected(device)
  identification = ""
  testing = false
  notice_override = "Controle desconectado. Identifique-o novamente; o rascunho foi preservado."
  # Retain the absent ID/name for display but invalidate permission to capture after reconnect.
  mapped_devices.erase(device)
  _refresh()

func focus_changed(value: bool) -> void:
 focused = value
 if not is_open(): return
 session.focus_changed(value)
 model_view.cancel_pointer()
 if not value:
  identification = ""
  identify_candidate.clear()
  testing = false
  nav_axis_held = false
 _refresh()

func route_input(event: InputEvent) -> bool:
 if not is_open(): return false
 snapshot.observe(event)
 if not focused or closing: return true
 if event is InputEventMouseButton:
  # A second click from the HOME double-click gesture must not select a new
  # target in the modal after its shorter neutral gate has elapsed.
  if event.pressed and event.double_click:
   ignored_double_click_button = event.button_index
   return true
  if not event.pressed and event.button_index == ignored_double_click_button:
   ignored_double_click_button = -1
   return true
 if event is InputEventMouseButton and event.pressed: last_activation = event
 elif event is InputEventKey and event.pressed: last_activation = event
 elif event is InputEventJoypadButton and event.pressed: last_activation = event
 if not identification.is_empty():
  _identify_event(event)
  return not (event is InputEventMouseButton or event is InputEventMouseMotion)
 if testing:
  # Gameplay Z/east may equal UI Back. Never steal them from the input test.
  if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F1]: _cancel_capture()
  return not (event is InputEventMouseButton or event is InputEventMouseMotion)
 # Unknown axes cannot be used without calibration. Buttons remain available after verification.
 if channel == "gamepad" and not _mapped(int(devices[player])) and event is InputEventJoypadMotion and session.state in [Capture.State.CAPTURING, Capture.State.HELD_CANDIDATE]: return true
 var previous: int = session.state
 var handled: bool = session.handle(event)
 if previous != session.state:
  _refresh()
  if session.state == Capture.State.CONFLICT: swap_button.grab_focus()
 if handled: return true
 if event is InputEventMouseButton or event is InputEventMouseMotion: return false
 if event is InputEventJoypadButton or event is InputEventJoypadMotion:
  # Navigation does not adopt another gamepad, and raw unknown buttons are not labelled as Xbox.
  if int(devices[player]) >= 0 and event.device != int(devices[player]): return true
  if not _mapped(event.device): return true
 if _is_back(event):
  if shared_box.visible: _cancel_shared()
  elif decision_box.visible: _continue_editing()
  elif session.state == Capture.State.CONFLICT: _resolve_conflict(false)
  else: request_close()
  return true
 var step := _navigation_step(event)
 if step != 0:
  _move_focus(step)
  return true
 if _is_confirm(event):
  var owner := get_viewport().gui_get_focus_owner()
  if owner in _focusable(): owner.pressed.emit()
  else: _focus_first()
  return true
 return true # All non-mouse modal input is owned, including releases and repeats.

func _is_back(event: InputEvent) -> bool:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F1]: return true
 return input_profile != null and input_profile.action_for(event) == "back"

func _is_confirm(event: InputEvent) -> bool:
 if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]: return true
 return input_profile != null and input_profile.action_for(event) == "confirm"

func _navigation_step(event: InputEvent) -> int:
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode == KEY_TAB: return -1 if event.shift_pressed else 1
  if event.keycode in [KEY_UP, KEY_LEFT]: return -1
  if event.keycode in [KEY_DOWN, KEY_RIGHT]: return 1
 if event is InputEventJoypadButton and event.pressed:
  if event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT]: return -1
  if event.button_index in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT]: return 1
 if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
  if absf(event.axis_value) <= 0.25: nav_axis_held = false
  elif absf(event.axis_value) >= 0.65 and not nav_axis_held:
   nav_axis_held = true
   return -1 if event.axis_value < 0 else 1
 return 0

func request_player(port: int) -> void:
 if testing: return
 if port == player or port not in [0, 1]: return
 pending_port = port
 pending_close = false
 _resolve_leaving()

func request_close() -> void:
 # Testing has its own explicit exit gesture; never queue an invisible close.
 if testing: return
 pending_port = -1
 pending_close = true
 _resolve_leaving()

func _resolve_leaving() -> void:
 if session.state not in [Capture.State.BROWSING, Capture.State.SAVE_ERROR] or testing: return
 if session.dirty():
  decision_box.visible = true
  _refresh()
  decision_continue.grab_focus()
 else: _finish_leaving()

func _continue_editing() -> void:
 decision_box.visible = false
 shared_box.visible = false
 pending_port = -1
 pending_close = false
 _refresh()
 _focus_first()

func _discard_and_continue() -> void:
 session.draft.load_snapshot(session.live.snapshot())
 decision_box.visible = false
 shared_box.visible = false
 _finish_leaving()

func save_changes(allow_shared := false) -> void:
 if session.state not in [Capture.State.BROWSING, Capture.State.SAVE_ERROR]: return
 var conflicts: Array = store.keyboard_conflicts(session.draft.snapshot())
 if not allow_shared and not conflicts.is_empty():
  var lines: Array[String] = []
  for item in conflicts: lines.append("%s: %s (P%d) e %s (P%d)" % [OS.get_keycode_string(int(item.code)), NAMES[item.action], player + 1, NAMES[item.other_action], int(item.other_port) + 1])
  shared_approval = conflicts.duplicate(true)
  shared_text.text = "Estas teclas controlarão os dois jogadores ao mesmo tempo:\n" + "\n".join(lines)
  shared_box.visible = true
  decision_box.visible = false
  _refresh()
  shared_cancel.grab_focus()
  return
 var result: Error = session.save_with(func(data: Dictionary) -> Error: return store.save_profile(data, allow_shared, shared_approval if allow_shared else []))
 if result != OK:
  notice_override = str(store.notice)
  shared_box.visible = false
  decision_box.visible = false
  _refresh()
  close_button.grab_focus()
  return
 profiles = store.load_profiles().profiles
 profiles[player] = session.live.snapshot()
 shared_box.visible = false
 decision_box.visible = false
 notice_override = "Configuração salva. Apenas os comandos do Master System foram alterados."
 profile_saved.emit(player)
 if pending_close or pending_port >= 0: _finish_leaving()
 else:
  session.cancel(notice_override)
  _refresh()

func _cancel_shared() -> void:
 shared_approval.clear()
 shared_box.visible = false
 notice_override = "Teclas compartilhadas não autorizadas. Rascunho mantido para você ajustar."
 pending_port = -1
 pending_close = false
 _refresh()
 _focus_first()

func _finish_leaving() -> void:
 if pending_port >= 0:
  var next := pending_port
  pending_port = -1
  session.close(true)
  session.open(profiles[next])
  player = next
  channel = "keyboard"
  _rebuild_rows()
  session.cancel("Jogador alterado. Solte as entradas para continuar.")
  _refresh()
 else:
  closing = true
  close_neutral = 0.0
  model_view.cancel_pointer()
  _refresh()

func _toggle_test() -> void:
 if testing:
  _cancel_capture()
  session.notice = "Teste encerrado. Nenhum jogo foi executado."
  _refresh()
  return
 var device := int(devices[player])
 if channel == "gamepad" and (device not in _connected_devices() or not device_authorized.get(device, false)):
  notice_override = "Identifique o controle deste jogador antes de testar suas entradas."
  _refresh()
  return
 if channel == "gamepad" and not _mapped(device) and not verified_cancel.has(device):
  notice_override = "Antes de testar este controle bruto, defina o botão que você poderá segurar para sair."
  _refresh()
  return
 test_cancel_device = device if device in _connected_devices() and device_authorized.get(device, false) else -1
 # For a keyboard test opened by a mapped gamepad, retain only an escape gesture
 # on that opener. This does NOT assign a player or persist the last-used device.
 if test_cancel_device < 0 and last_activation is InputEventJoypadButton and last_activation.device in _connected_devices() and _mapped(last_activation.device):
  test_cancel_device = last_activation.device
 test_cancel_button = int(JOY_BUTTON_B) if _mapped(test_cancel_device) else int(verified_cancel.get(test_cancel_device, -1))
 test_cancel_elapsed = 0.0
 test_cancel_armed = false
 test_neutral_elapsed = 0.0
 snapshot.mark_opening(last_activation)
 testing = true
 _refresh()

func _advance_input_test(delta: float) -> void:
 var device := int(devices[player])
 if test_cancel_button >= 0:
  if not test_cancel_armed:
   var neutral: bool = snapshot.neutral(test_cancel_device, _mapped(test_cancel_device))
   test_neutral_elapsed = test_neutral_elapsed + maxf(0.0, delta) if neutral else 0.0
   test_cancel_armed = test_neutral_elapsed >= Capture.NEUTRAL_SECONDS
  else:
   test_cancel_elapsed = test_cancel_elapsed + maxf(0.0, delta) if snapshot.button_held(test_cancel_device, test_cancel_button) else 0.0
   if test_cancel_elapsed >= Capture.CANCEL_HOLD_SECONDS:
    _cancel_capture()
    session.notice = "Teste encerrado pelo botão mantido. Solte as entradas para continuar."
    _refresh()
    return
  if test_cancel_elapsed > 0.0:
   notice.text = "Teste de entradas ativo · segurar para sair: %d%%. Toque curto não encerra." % mini(100, int(test_cancel_elapsed / Capture.CANCEL_HOLD_SECONDS * 100.0))
  else:
   notice.text = "Teste local de entradas. Os comandos acesos não executam jogo algum. Esc/F1 encerra."
 var active: Array[String] = []
 for action in session.draft.actions():
  if snapshot.binding_pressed(session.draft.bindings[channel][action], device): active.append(action)
  rows[action].text = ("● " if action in active else "○ ") + str(NAMES[action]) + " · " + _binding_text(session.draft.bindings[channel][action])
 model_view.set_highlight(active[0] if not active.is_empty() else "")

func advance(delta: float) -> void:
 if not is_open() or not focused: return
 var device := int(devices[player])
 var neutral: bool = release_inputs_neutral()
 if closing:
  close_neutral = close_neutral + maxf(0.0, delta) if neutral else 0.0
  if close_neutral >= Capture.NEUTRAL_SECONDS:
   var previous_player := player
   session.close(true)
   visible = false
   closing = false
   model_view.clear_model()
   var previous = returning_focus.get_ref() if returning_focus != null else null
   closed.emit(previous_player)
   if is_instance_valid(previous) and previous.is_visible_in_tree() and previous.focus_mode != Control.FOCUS_NONE: previous.grab_focus()
  return
 if not identification.is_empty():
  # Identifying a device requires all visible devices to be neutral first.
  for candidate in _connected_devices(): neutral = neutral and snapshot._device_neutral(int(candidate), _mapped(int(candidate)))
  identify_neutral = identify_neutral + maxf(0.0, delta) if neutral else 0.0
  if identify_neutral >= Capture.NEUTRAL_SECONDS: identify_ready = true
  return
 var before: int = session.state
 session.advance(delta, neutral, snapshot.button_held(device, session.cancel_hold_button))
 if before != session.state:
  _refresh()
  if session.state == Capture.State.BROWSING: _focus_first()
 if session.state == Capture.State.HELD_CANDIDATE and session.cancel_elapsed > 0.0:
  notice.text = "Segure para cancelar: %d%%. Soltar antes conclui a atribuição." % mini(100, int(session.cancel_elapsed / Capture.CANCEL_HOLD_SECONDS * 100.0))
 if testing: _advance_input_test(delta)

func _process(delta: float) -> void:
 advance(delta)
