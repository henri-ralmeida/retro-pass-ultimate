extends Control
## One read-only modal owned by its library; adapter responses are generation-bound.
signal closed
signal read_requested(ticket: Dictionary)
const Icons = preload("res://cosmic/ui_icons.gd")
const Model = preload("res://cosmic/achievements_model.gd")
const InputSnapshot = preload("res://cosmic/controller_input_snapshot.gd")
var model := Model.new()
var host: Node
var game := {}
var provider: Object
var generation := 0
var request_serial := 0
var pending := {}
var view := "achievements"
var state := "unavailable"
var error_text := ""
var comments: Array = []
var hubs: Array = []
var members: Array = []
var selected_achievement := ""
var selected_hub := ""
var page := 0
var has_more := false
var console_filter := ""
var _opening_gate := true
var _held := {}
var _axis_held := false
var _scroll_axis := 0.0
var _restore_focus: Control
var _subview_focus: Control
var _focus_intent := ""
var _requested_focus := ""
var _return_row := ""
var _return_hub := ""
var _panel: PanelContainer
var _heading: Label
var _subtitle: Label
var _toolbar: HBoxContainer
var _filters: HFlowContainer
var _status: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _footer: HFlowContainer
var _buttons: Array[Button] = []
var _sort_open := false
var _sort_button: Button
var _trophy_button: Button
var _close_button: Button
var _snapshot = InputSnapshot.new()

func configure(owner_host: Node) -> void:
 host = owner_host
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 var shade := ColorRect.new()
 shade.color = Color(0.004,0.009,0.025,0.84)
 shade.mouse_filter = Control.MOUSE_FILTER_STOP
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(shade)
 _panel = PanelContainer.new()
 _panel.add_theme_stylebox_override("panel",Icons.style(Color(0.035,0.055,0.10,0.98),Color("425d7b")))
 add_child(_panel)
 var column := VBoxContainer.new()
 column.add_theme_constant_override("separation",12)
 _panel.add_child(column)
 var top := HBoxContainer.new()
 column.add_child(top)
 var titles := VBoxContainer.new()
 titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 top.add_child(titles)
 _heading = _label("",24,Color("eef5ff"))
 titles.add_child(_heading)
 _subtitle = _label("",14,Color("9cb3ce"))
 titles.add_child(_subtitle)
 _close_button = _button("close","Fechar painel",close_panel)
 top.add_child(_close_button)
 _toolbar = HBoxContainer.new()
 _toolbar.add_theme_constant_override("separation",8)
 column.add_child(_toolbar)
 _trophy_button = _button("trophy","Troféus",func(): _navigate("achievements"))
 _trophy_button.set_meta("tab_view","achievements")
 _trophy_button.toggle_mode = true
 _toolbar.add_child(_trophy_button)
 var comment_tab := _button("comments","Comentários do jogo — somente leitura",func(): _navigate("game_comments"))
 comment_tab.toggle_mode = true
 comment_tab.set_meta("tab_view","game_comments")
 _toolbar.add_child(comment_tab)
 var hub_tab := _button("hubs","Hubs de jogos relacionados",func(): _navigate("hubs"))
 hub_tab.toggle_mode = true
 hub_tab.set_meta("tab_view","hubs")
 _toolbar.add_child(hub_tab)
 var stretch := Control.new()
 stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _toolbar.add_child(stretch)
 var soft := _button("unlocked","Alternar Hardcore / Softcore",_toggle_mode)
 _toolbar.add_child(soft)
 _sort_button = _button("sort","Ordenação",_show_sort)
 _toolbar.add_child(_sort_button)
 _filters = HFlowContainer.new()
 _filters.add_theme_constant_override("h_separation",8)
 column.add_child(_filters)
 for key in Model.FILTERS:
  var captions := {"all":"Todas","unlocked":"Desbloqueadas","locked":"Bloqueadas","beaten":"Beaten Path — tipos de progressão; não é status oficial","missable":"Missable"}
  var button := _button(key,captions[key],func(): model.filter = key; _render())
  button.set_meta("filter",key)
  _filters.add_child(button)
 _status = _label("",15,Color("b6c8df"))
 _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 column.add_child(_status)
 _scroll = ScrollContainer.new()
 _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 _scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 _scroll.follow_focus = true
 column.add_child(_scroll)
 _content = VBoxContainer.new()
 _content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _content.add_theme_constant_override("separation",8)
 _scroll.add_child(_content)
 _footer = HFlowContainer.new()
 _footer.add_theme_constant_override("separation",8)
 column.add_child(_footer)
 resized.connect(_layout)
 _layout()
 hide()

func _label(value: String, font_size: int, color: Color) -> Label:
 var label := Label.new()
 label.text = value
 label.add_theme_font_size_override("font_size",font_size)
 label.add_theme_color_override("font_color",color)
 label.add_theme_font_override("font",load("res://assets/fonts/ChakraPetch-Regular.ttf"))
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 return label

func _button(icon: String, tip: String, action: Callable) -> Button:
 var button := Button.new()
 Icons.iconify(button,icon,tip)
 button.set_meta("focus_key",tip)
 button.pressed.connect(action)
 return button

func _layout() -> void:
 if not is_instance_valid(_panel): return
 var area := get_rect().size
 var padding := 20.0 if area.x < 900 else 44.0
 var width := minf(1000,area.x-padding*2)
 _panel.position = Vector2((area.x-width)/2,padding)
 _panel.size = Vector2(width,maxf(300,area.y-padding*2))

func open_for(item: Dictionary, return_focus: Control, adapter: Object = null) -> void:
 generation += 1
 pending.clear()
 game = item.duplicate(true)
 provider = adapter
 _restore_focus = return_focus
 model = Model.new()
 comments.clear()
 hubs.clear()
 members.clear()
 selected_achievement = ""
 selected_hub = ""
 console_filter = ""
 view = "achievements"
 _sort_open = false
 _held.clear()
 _scroll_axis = 0.0
 var snapshot = host.get("media_input_snapshot") if is_instance_valid(host) else null
 _opening_gate = snapshot != null and not preload("res://cosmic/ui_input_gate.gd").neutral(snapshot,host)
 _focus_intent = ""
 _requested_focus = ""
 _return_row = ""
 _return_hub = ""
 show()
 move_to_front()
 _layout()
 _request()
 _close_button.grab_focus()

func close_panel() -> void:
 generation += 1
 pending.clear()
 hide()
 provider = null
 _held.clear()
 _scroll_axis = 0.0
 if is_instance_valid(_restore_focus) and _restore_focus.is_visible_in_tree(): _restore_focus.grab_focus()
 closed.emit()

func _navigate(next_view: String) -> void:
 generation += 1
 pending.clear()
 _sort_open = false
 _subview_focus = null
 if next_view == "achievement_comments": _return_row = selected_achievement
 if next_view == "hub_members": _return_hub = selected_hub
 view = next_view
 selected_achievement = "" if next_view != "achievement_comments" else selected_achievement
 selected_hub = "" if next_view != "hub_members" else selected_hub
 var focused := get_viewport().gui_get_focus_owner()
 if focused and is_ancestor_of(focused): focused.release_focus()
 page = 0
 has_more = false
 comments.clear()
 _request()

func _request(next_page: int = 0) -> void:
 if next_page > 0:
  var focused := get_viewport().gui_get_focus_owner()
  if focused is Button and is_ancestor_of(focused): _requested_focus = str(focused.get_meta("focus_key",""))
 request_serial += 1
 pending = {"generation":generation,"serial":request_serial,"game_id":str(game.get("ra_game_id","")),"view":view,
  "target_id":selected_achievement if view == "achievement_comments" else selected_hub,"page":next_page}
 error_text = ""
 # No personal RA identity is inferred from a local title or ROM filename.
 if pending.game_id.is_empty() or not is_instance_valid(provider) or not provider.has_method("request_read"):
  state = "unavailable"
  pending.clear()
  _render()
  return
 state = "loading"
 _render()
 var ticket := pending.duplicate(true)
 read_requested.emit(ticket)
 # Adapter must deliver via accept_response(ticket,result). It is read-only.
 provider.call_deferred("request_read",self,ticket)

func accept_response(ticket: Dictionary, result: Dictionary) -> bool:
 if not visible or pending.is_empty() or ticket != pending: return false
 pending.clear()
 if result.get("ok",false) != true:
  state = "error"
  error_text = str(result.get("error","Falha de leitura. Tente novamente.")).left(500)
  _render()
  return true
 var records: Variant = result.get("records",[])
 if not records is Array or records.size() > 5000:
  state = "error"
  error_text = "Resposta inválida. Nenhum dado foi aplicado."
  _render()
  return true
 state = "ready"
 match view:
  "achievements": model.set_records(records)
  "game_comments","achievement_comments":
   if int(ticket.page) == 0: comments.clear()
   for record in records:
    if record is Dictionary: comments.append(record.duplicate(true))
   page = int(ticket.page)
   has_more = result.get("has_more",false) == true
  "hubs": hubs = records.duplicate(true)
  "hub_members": members = records.duplicate(true)
 _render()
 return true

func _toggle_mode() -> void:
 model.mode = "softcore" if model.mode == "hardcore" else "hardcore"
 _render()

func _show_sort() -> void:
 if view != "achievements": return
 _sort_open = not _sort_open
 _render()
 if _sort_open and _content.get_child_count() > 0:
  var first = _content.find_children("*","Button",true,false)
  if not first.is_empty(): first[0].grab_focus()
 else: _sort_button.grab_focus()

func _clear_content() -> void:
 for node in _content.get_children():
  _content.remove_child(node)
  node.queue_free()
 for node in _footer.get_children():
  _footer.remove_child(node)
  node.queue_free()

func _render() -> void:
 if not is_instance_valid(_heading): return
 var focused_before := get_viewport().gui_get_focus_owner()
 if _requested_focus.is_empty() and focused_before is Button and is_ancestor_of(focused_before):
  var key := str(focused_before.get_meta("focus_key",""))
  if not key.is_empty(): _focus_intent = key
 _clear_content()
 _heading.text = str(game.get("title","Jogo")).left(180)
 _heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 _heading.clip_text = true
 var names := {"achievements":"Troféus","game_comments":"Comentários do jogo","achievement_comments":"Comentários da conquista","hubs":"Hubs","hub_members":"Jogos relacionados"}
 _subtitle.text = names.get(view,view) + "  /  " + model.mode.capitalize()
 _filters.visible = view == "achievements" and not _sort_open
 _sort_button.disabled = view != "achievements"
 for button in _toolbar.get_children():
  if button is Button and button.has_meta("tab_view"):
   var tab := str(button.get_meta("tab_view"))
   button.set_pressed_no_signal(tab == view or (tab == "hubs" and view == "hub_members") or (tab == "achievements" and view == "achievement_comments"))
 for button in _filters.get_children():
  button.modulate = Color("9bdcff") if button.get_meta("filter","") == model.filter else Color.WHITE
 _status.text = ""
 _footer.add_child(_button("back","Voltar",go_back))
 if _sort_open:
  _status.text = "Ordenação · " + model.sort.to_upper()
  var tips := {"ra":"Ordem RetroAchievements","az":"Título A → Z","za":"Título Z → A","points":"Pontos — maior primeiro","points_low":"Pontos — menor primeiro","rarity":"Raridade informada — menor percentual primeiro","rarity_common":"Raridade informada — maior percentual primeiro","status":"Desbloqueadas primeiro","locked_first":"Bloqueadas primeiro"}
  var options := HFlowContainer.new()
  options.add_theme_constant_override("h_separation",12)
  options.add_theme_constant_override("v_separation",12)
  _content.add_child(options)
  for key in Model.SORTS:
   var row := _button("sort",tips[key],func(): model.sort = key; _sort_open = false; _render(); _sort_button.grab_focus())
   row.accessibility_description = tips[key]
   row.icon = Icons.texture({"ra":"all","az":"az","za":"za","points":"points_high","points_low":"points_low","rarity":"rarity","rarity_common":"rarity_common","status":"unlocked","locked_first":"locked"}.get(key,"sort"))
   row.custom_minimum_size = Vector2(88,72)
   row.toggle_mode = true
   row.set_pressed_no_signal(key == model.sort)
   options.add_child(row)
  _wire_focus()
  return
 if state == "unavailable":
  _status.text = "RetroAchievements não conectado."
  _message("Sem provedor de leitura ou identificação RA confirmada para este jogo.\nNenhum progresso pessoal, comentário ou hub foi inventado.\nO acervo local e a inspeção 3D continuam disponíveis.")
 elif state == "loading":
  _status.text = "Carregando…"
  if not comments.is_empty(): _render_comments()
  else: _message("Aguardando dados de leitura. Voltar cancela esta solicitação.")
 elif state == "error":
  _status.text = "Não foi possível carregar."
  if not comments.is_empty(): _render_comments()
  _message(error_text)
  _footer.add_child(_button("retry","Tentar novamente",func(): _request(page+1 if not comments.is_empty() else 0)))
 elif view == "achievements":
  var summary := model.summary()
  _status.text = "%d / %d desbloqueadas · %d / %d pontos · %s" % [summary.unlocked,summary.total,summary.earned,summary.points,"Hardcore" if model.mode == "hardcore" else "Softcore"]
  if summary.complete: _status.text += " · conjunto completo neste modo"
  if model.filter == "beaten": _status.text += "\nBeaten Path: agrupamento por tipos; não comprova jogo concluído oficialmente."
  var rows := model.visible_records()
  if rows.is_empty(): _message("Nenhuma conquista neste filtro." if summary.total > 0 else "Nenhuma conquista informada pelo provedor.")
  for record in rows: _achievement_row(record)
 elif view in ["game_comments","achievement_comments"]:
  _status.text = "%d comentários carregados · somente leitura
PgUp/PgDn ou analógico direito: rolar" % comments.size()
  _render_comments()
  if comments.is_empty(): _message("Nenhum comentário nesta página.")
  if has_more: _footer.add_child(_button("next","Carregar próxima página",func(): _request(page+1)))
 elif view == "hubs":
  _status.text = "%d hubs carregados · listas podem ser parciais" % hubs.size()
  if hubs.is_empty(): _message("Nenhum hub informado para este jogo.")
  for raw in hubs:
   if not raw is Dictionary: continue
   var record: Dictionary = raw
   var id := str(record.get("id",""))
   var row := _data_row("hubs",str(record.get("name","Hub")),str(record.get("loaded_count",0))+" jogos disponíveis neste catálogo; lista parcial",func(): selected_hub = id; _navigate("hub_members"))
   row.set_meta("focus_key","hub:"+id)
   _content.add_child(row)
 elif view == "hub_members":
  _status.text = "Jogos do catálogo retornado · não representa a totalidade do hub\nConsole: "+(console_filter if not console_filter.is_empty() else "todos")
  var consoles: Array[String] = [""]
  for record in members:
   if record is Dictionary and str(record.get("console","")) not in consoles: consoles.append(str(record.get("console","")))
  for console in consoles:
   var console_button := _button("gamepad","Console: "+(console if not console.is_empty() else "todos"),func(): console_filter = console; _render())
   console_button.toggle_mode = true
   console_button.set_pressed_no_signal(console == console_filter)
   _footer.add_child(console_button)
  var shown := 0
  for record in members:
   if not record is Dictionary: continue
   if not console_filter.is_empty() and str(record.get("console","")) != console_filter: continue
   shown += 1
   var row := _data_row("gamepad",str(record.get("title","Jogo")),str(record.get("console","Console não informado")),Callable())
   _content.add_child(row)
  if shown == 0: _message("Nenhum jogo neste filtro de console.")
 _wire_focus()

func _message(value: String) -> void:
 var label := _label(value,18,Color("aabed8"))
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _content.add_child(label)

func _data_row(icon: String, title: String, detail: String, callback: Callable) -> Button:
 var row := _button(icon,title,callback if callback.is_valid() else func(): pass)
 row.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
 row.alignment = HORIZONTAL_ALIGNMENT_LEFT
 row.custom_minimum_size = Vector2(0,84)
 row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 row.clip_contents = true
 var margin := MarginContainer.new()
 margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 margin.add_theme_constant_override("margin_left",58)
 margin.add_theme_constant_override("margin_right",14)
 margin.add_theme_constant_override("margin_top",9)
 margin.add_theme_constant_override("margin_bottom",9)
 margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
 row.add_child(margin)
 var column := VBoxContainer.new()
 column.mouse_filter = Control.MOUSE_FILTER_IGNORE
 margin.add_child(column)
 var name_label := _label(title.left(300),18,Color("edf4ff"))
 name_label.clip_text = true
 name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 column.add_child(name_label)
 var description := _label(detail.left(3000),14,Color("a8bbd5"))
 description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 description.max_lines_visible = 2
 description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 column.add_child(description)
 row.accessibility_description = detail
 row.tooltip_text = title+"\n"+detail
 return row

func _achievement_row(record: Dictionary) -> void:
 var done := model.unlocked(record)
 var id := str(record.id)
 var row := _data_row("unlocked" if done else "locked",record.title,
  str(record.description),
  func(): selected_achievement = id; _navigate("achievement_comments"))
 row.custom_minimum_size.y = 120
 var details := row.get_child(0).get_child(0)
 var points := _label("%d pontos · %s · %s" % [record.points,"desbloqueada" if done else "bloqueada",model.mode],14,Color("9dd6ee"))
 details.add_child(points)
 # Adapter may supply an already validated texture; this UI never decodes a
 # provider path, downloads badge URLs, or trusts dimensions after allocation.
 var badge: Variant = record.get("badge_texture")
 if badge is Texture2D and badge.get_width() <= 1024 and badge.get_height() <= 1024:
  row.icon = badge
 row.set_meta("achievement_id",id)
 row.set_meta("focus_key","achievement:"+id)
 _content.add_child(row)

func _render_comments() -> void:
 for record in comments:
  if not record is Dictionary: continue
  var card := PanelContainer.new()
  card.add_theme_stylebox_override("panel",Icons.style(Color("101c2d"),Color("253951")))
  var column := VBoxContainer.new()
  card.add_child(column)
  var author := _label(str(record.get("user","Usuário")).left(160)+"  ·  "+str(record.get("submitted","")).left(80),15,Color("a5d5ef"))
  author.clip_text = true
  author.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
  column.add_child(author)
  var text := _label(str(record.get("text","")).left(10000),17,Color("d4dff0"))
  text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  column.add_child(text)
  _content.add_child(card)

func _wire_focus() -> void:
 _buttons.clear()
 _collect_buttons(self)
 for index in _buttons.size():
  var button := _buttons[index]
  var before := _buttons[posmod(index-1,_buttons.size())].get_path()
  var after := _buttons[(index+1)%_buttons.size()].get_path()
  button.focus_next = after
  button.focus_previous = before
  button.focus_neighbor_top = before
  button.focus_neighbor_bottom = after
  button.focus_neighbor_left = before
  button.focus_neighbor_right = after
 var focus := get_viewport().gui_get_focus_owner()
 for button in _buttons:
  if str(button.get_meta("focus_key","")) == (_requested_focus if not _requested_focus.is_empty() else _focus_intent):
   button.grab_focus()
   _focus_intent = str(button.get_meta("focus_key",""))
   _requested_focus = ""
   if _scroll.is_ancestor_of(button): _scroll.ensure_control_visible(button)
   return
 if not focus in _buttons and not _buttons.is_empty():
  var fallback: Button = _footer.get_child(_footer.get_child_count()-1) if _footer.get_child_count() > 1 else _trophy_button
  fallback.grab_focus()

func _collect_buttons(node: Node) -> void:
 for child in node.get_children():
  if child is Button and child.is_visible_in_tree() and not child.disabled: _buttons.append(child)
  _collect_buttons(child)

func go_back() -> void:
 if _sort_open:
  _sort_open = false
  _render()
  _sort_button.grab_focus()
 elif view == "hub_members":
  _requested_focus = "hub:"+selected_hub
  _navigate("hubs")
 elif view != "achievements":
  _requested_focus = "achievement:"+selected_achievement if view == "achievement_comments" else "Troféus"
  _navigate("achievements")
 else: close_panel()

func _restore_subfocus() -> void:
 # Removed rows cannot retain focus; identify the row again after response.
 _trophy_button.grab_focus()

func _input_id(event: InputEvent) -> String:
 if event is InputEventKey: return "k:%d" % (event.physical_keycode if event.physical_keycode else event.keycode)
 if event is InputEventJoypadButton: return "j:%d:%d" % [event.device,event.button_index]
 return ""

func route_input(event: InputEvent) -> bool:
 if not visible: return false
 _snapshot.observe(event)
 var snapshot = host.get("media_input_snapshot") if is_instance_valid(host) else null
 if snapshot == null: snapshot = _snapshot
 if host.get("application_focused") == false or host.get("scene_active") == false:
  _opening_gate = true
  _axis_held = false
  return true
 if _opening_gate:
  if preload("res://cosmic/ui_input_gate.gd").neutral(snapshot,host): _opening_gate = false
  return true
 var id := _input_id(event)
 if not id.is_empty():
  if not event.pressed: _held.erase(id); return true
  if _held.has(id): return true
  _held[id] = true
 if event is InputEventKey and event.echo: return true
 var profile = host.get("input_profile")
 var action: String = profile.action_for(event) if profile else ""
 if action == "back" or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE): go_back(); return true
 if action == "confirm" or (event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]):
  var focused := get_viewport().gui_get_focus_owner()
  if focused is Button and focused in _buttons: focused.pressed.emit()
  return true
 # Other remapped home actions never reach scene writers.
 if not action.is_empty(): return true
 var step := 0
 if event is InputEventKey and event.pressed:
  if event.keycode in [KEY_DOWN,KEY_RIGHT,KEY_TAB]: step = -1 if event.shift_pressed else 1
  elif event.keycode in [KEY_UP,KEY_LEFT]: step = -1
 if event is InputEventJoypadButton and event.pressed:
  if event.button_index in [JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_DPAD_DOWN]: step = 1
  elif event.button_index in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_UP]: step = -1
 if event is InputEventKey and event.pressed and event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN,KEY_HOME,KEY_END]:
  var amount := int(_scroll.size.y*0.8)
  if event.keycode == KEY_PAGEUP: _scroll.scroll_vertical -= amount
  elif event.keycode == KEY_PAGEDOWN: _scroll.scroll_vertical += amount
  elif event.keycode == KEY_HOME: _scroll.scroll_vertical = 0
  else: _scroll.scroll_vertical = int(_content.size.y)
  return true
 if event is InputEventJoypadMotion:
  if event.axis == JOY_AXIS_RIGHT_Y:
   _scroll_axis = event.axis_value if absf(event.axis_value) > 0.25 else 0.0
   return true
  if event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:
   if absf(event.axis_value) < 0.25: _axis_held = false
   elif absf(event.axis_value) > 0.65 and not _axis_held:
    _axis_held = true
    step = 1 if event.axis_value > 0 else -1
  if step == 0: return true
 if step != 0:
  var focused := get_viewport().gui_get_focus_owner()
  var index := _buttons.find(focused)
  if not _buttons.is_empty(): _buttons[posmod(index+step,_buttons.size())].grab_focus()
  return true
 # Pointer goes to this modal's GUI, never the underlying library or host.
 return not (event is InputEventMouseButton or event is InputEventMouseMotion)

func focus_changed(_value: bool) -> void:
 _held.clear()
 _axis_held = false
 _scroll_axis = 0.0
 _opening_gate = true
 # The host's physical snapshot reconciles releases lost while unfocused.

func _process(delta: float) -> void:
 if not visible or not is_instance_valid(host): return
 if host.get("application_focused") == false or host.get("scene_active") == false: return
 if _opening_gate:
  var snapshot = host.get("media_input_snapshot")
  if snapshot != null and preload("res://cosmic/ui_input_gate.gd").neutral(snapshot,host): _opening_gate = false
 elif absf(_scroll_axis) > 0.25:
  _scroll.scroll_vertical += roundi(_scroll_axis*420.0*delta)
