extends Control
## One persistent panel/service/journal owner, independent of modal visibility.
signal opened
signal closed
const OptinPanel = preload("res://cosmic/media_optin_panel.gd")
const Store = preload("res://cosmic/media_optin_store.gd")
var store := Store.new()
var panel
var overlay: ColorRect
var frame: PanelContainer
var summary: Label
var close_button: Button
var launcher: Button
var profile
var catalog_getter: Callable
var catalog_apply: Callable
var can_apply: Callable
var _snapshot: Array = []
var _pending_association: Dictionary = {}
var _private_state: Dictionary = {}
var _read_errors := 0
var _read_omissions := 0
var _status := "Opcional · sem download"

func _ready() -> void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 overlay = ColorRect.new()
 overlay.color = Color(0.005,0.012,0.035,0.94)
 overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(overlay)
 frame = PanelContainer.new()
 overlay.add_child(frame)
 var style := StyleBoxFlat.new()
 style.bg_color = Color("101e35")
 style.border_color = Color("58c5da")
 style.set_border_width_all(1)
 style.set_corner_radius_all(12)
 style.content_margin_left = 20
 style.content_margin_right = 20
 style.content_margin_top = 16
 style.content_margin_bottom = 16
 frame.add_theme_stylebox_override("panel",style)
 var column := VBoxContainer.new()
 frame.add_child(column)
 close_button = Button.new()
 close_button.text = "Voltar à navegação"
 close_button.pressed.connect(close_panel)
 column.add_child(close_button)
 var scroll := ScrollContainer.new()
 scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 column.add_child(scroll)
 panel = OptinPanel.new()
 panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 scroll.add_child(panel)
 panel.before_start = _before_start
 panel.confirm_dialog.profile = profile
 panel.system_picker.get_popup().set_script(preload("res://cosmic/media_system_popup.gd"))
 panel.system_picker.get_popup().profile = profile
 panel.dismissed.connect(_dismissed)
 panel.processing_finished.connect(_finished)
 summary = Label.new()
 summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 summary.text = "Só mídias explicitamente relacionadas no inventário. Originais preservados.\nPDF não vira páginas; screenshot não vira capa. Associação vale nesta sessão."
 column.add_child(summary)
 _private_state = store.load_state()
 panel.offer_resume(_private_state.get("plan",{}))
 overlay.hide()
 resized.connect(_layout)
 _layout()

func _layout() -> void:
 if not is_instance_valid(frame): return
 var available := get_viewport_rect().size
 frame.position = Vector2(maxf(12,(available.x-680)/2),20)
 frame.size = Vector2(minf(680,available.x-24),maxf(200,available.y-40))

func is_open() -> bool:
 return is_instance_valid(overlay) and overlay.visible

func open_panel() -> void:
 if is_open(): return
 if not panel.service.is_busy() and _pending_association.is_empty():
  panel.set_inventory(catalog_getter.call() if catalog_getter.is_valid() else [])
  panel.offer_resume(_private_state.get("plan",{}))
 overlay.show()
 panel.show()
 _layout()
 _layout.call_deferred()
 opened.emit()
 panel.start_button.grab_focus()

func close_panel() -> void:
 if not is_open(): return
 panel._invalidate_confirmation()
 overlay.hide()
 closed.emit()

func _before_start(plan: Dictionary) -> Error:
 _snapshot = panel.inventory_items.duplicate(true)
 var error: int = store.save_plan(plan)
 if error == OK:
  _private_state = {"decision":plan.config.duplicate(true),"plan":plan.duplicate(true)}
  _pending_association = {}
 return error

func _dismissed(decision: Dictionary) -> void:
 var error: int = store.save_decision(decision)
 if error != OK:
  panel.show()
  panel.status_label.text = "Não foi possível salvar a decisão privada: %s" % error
  return
 _private_state = store.load_state()
 close_panel()

func _finished(_result: Dictionary) -> void:
 _read_errors = int(_result.get("files_error",0))
 _read_omissions = int(_result.get("associations_omitted",0))
 _pending_association = panel.service.association_result()
 if _pending_association.is_empty():
  _status = "Leitura finalizada · nenhum vínculo aplicado"
 else:
  _status = "Validado · aguardando navegação estável"

func _process(_delta: float) -> void:
 if not is_instance_valid(panel): return
 close_button.text = "Voltar à navegação · processo continua" if panel.service.is_busy() else "Voltar à navegação"
 var progress_caption := "Mídia local"
 if panel.service.is_busy():
  var p: Dictionary = panel.service.poll()
  progress_caption = "Validando mídia" if p.get("status","") == "validating_images" else "Local %d/%d" % [p.get("files_done",0),p.get("files_total",0)]
  _status = "Validando imagens locais" if p.get("status","") == "validating_images" else "Leitura local %d/%d arquivos" % [p.get("files_done",0),p.get("files_total",0)]
 if not _pending_association.is_empty() and (not can_apply.is_valid() or can_apply.call()):
  var current: Array = catalog_getter.call() if catalog_getter.is_valid() else []
  if current != _snapshot:
   _status = "Catálogo mudou · nada aplicado; revise novamente"
  else:
   var count: int = catalog_apply.call(_pending_association) if catalog_apply.is_valid() else 0
   # Our own provenance updates are not an external catalog change. Refresh the
   # next consent snapshot without changing the approved saved plan.
   if catalog_getter.is_valid(): panel.inventory_items = catalog_getter.call().duplicate(true)
   _status = "%d vínculos aplicados · %d erros de arquivo · %d omissões · %d não aplicados" % [count,_read_errors,_read_omissions,_pending_association.get("issues",[]).size()]
  summary.text = _status + "\nCatálogo desta sessão; exibição na próxima entrada.
Retomar exige confirmação e validação atuais."
  _pending_association = {}
 if is_instance_valid(launcher):
  launcher.tooltip_text = "Mídia local · " + _status
  var label := launcher.find_child("ActionLabel",true,false)
  if label != null: label.text = progress_caption

func route_input(event: InputEvent) -> bool:
 if not is_open(): return false
 if panel.confirm_dialog.visible: return false # Exclusive Window owns its GUI.
 panel.last_input_event = event
 var focused := get_viewport().gui_get_focus_owner()
 # Do not interpret remapped letters as shortcuts while typing a path.
 if focused is LineEdit and event is InputEventKey and event.keycode != KEY_ESCAPE: return false
 var action: String = profile.action_for(event) if profile != null else ""
 if action == "back" or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
  close_panel()
  return true
 if action == "confirm":
  if focused is OptionButton and not focused.disabled:
   focused.show_popup()
  elif focused is BaseButton and not focused.disabled:
   if focused.toggle_mode: focused.button_pressed = not focused.button_pressed
   focused.pressed.emit()
  return true
 if event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]:
  if focused != null:
   var next: Control = focused.find_prev_valid_focus() if event.button_index in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_LEFT] else focused.find_next_valid_focus()
   if next != null: next.grab_focus()
  return true
 return event is InputEventJoypadButton or event is InputEventJoypadMotion

func _exit_tree() -> void:
 if is_instance_valid(panel): panel.service.shutdown()
