extends PanelContainer
## Opt-in local processing; host owns lifecycle and private persistence.
signal dismissed(decision: Dictionary)
signal processing_finished(summary: Dictionary)
const Config = preload("res://cosmic/media_optin_config.gd")
const Planner = preload("res://cosmic/media_optin_plan.gd")
const Service = preload("res://cosmic/media_processing_service.gd")
var last_input_event: InputEvent
var before_start: Callable
var inventory_items: Array = []
var journal_path := "user://retropass_local_media_queue.json"
var service := Service.new()
var system_picker: OptionButton
var root_input: LineEdit
var categories: Dictionary = {}
var status_label: Label
var progress_bar: ProgressBar
var confirm_dialog: ConfirmationDialog
var start_button: Button
var resume_button: Button
var cancel_button: Button
var skip_button: Button
var later_button: Button
var _pending_plan: Dictionary = {}
var _last_plan: Dictionary = {}
var _resume := false
var _was_running := false

func _ready() -> void:
 var column := VBoxContainer.new()
 add_child(column)
 var heading := Label.new()
 heading.text = "Mídia local — configuração opcional"
 column.add_child(heading)
 var explanation := Label.new()
 explanation.text = "Escolha sistema, raiz e categorias. Arquivos de mídia só serão processados após sua confirmação.\nSomente referências exatas do inventário; edição não verificada."
 explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 column.add_child(explanation)
 system_picker = OptionButton.new()
 for system in Config.SYSTEMS: system_picker.add_item({"master_system":"Master System","mark_iii":"Mark III","atari_2600":"Atari 2600"}.get(system,system))
 system_picker.selected = -1
 column.add_child(system_picker)
 system_picker.item_selected.connect(func(_index: int): _invalidate_confirmation())
 root_input = LineEdit.new()
 root_input.placeholder_text = "Raiz local absoluta (digite ou cole; não varre pastas)"
 root_input.accessibility_name = "Raiz local das mídias"
 column.add_child(root_input)
 root_input.text_changed.connect(func(_text: String): _invalidate_confirmation())
 var labels := {"covers":"Capas e labels explícitos", "images":"Imagens (não usadas como capas)", "wheel":"Wheel / logo", "manual":"Manuais locais (sem conversão PDF)"}
 for category in Config.CATEGORIES:
  var checkbox := CheckBox.new()
  checkbox.text = labels[category]
  categories[category] = checkbox
  column.add_child(checkbox)
  checkbox.toggled.connect(func(_pressed: bool): _invalidate_confirmation())
 var actions := HFlowContainer.new()
 actions.add_theme_constant_override("h_separation",8)
 actions.add_theme_constant_override("v_separation",8)
 column.add_child(actions)
 start_button = _button(actions, "Revisar processamento local", _review)
 resume_button = _button(actions, "Retomar / tentar novamente", _review_resume)
 resume_button.disabled = _last_plan.is_empty()
 cancel_button = _button(actions, "Cancelar processamento", service.request_cancel)
 cancel_button.disabled = true
 skip_button = _button(actions, "Pular", func(): _dismiss(true))
 later_button = _button(actions, "Configurar depois", func(): _dismiss(false))
 progress_bar = ProgressBar.new()
 progress_bar.show_percentage = false
 column.add_child(progress_bar)
 status_label = Label.new()
 status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 status_label.text = "Nada selecionado. Processamento local, sem download."
 column.add_child(status_label)
 confirm_dialog = preload("res://cosmic/media_confirmation_dialog.gd").new()
 confirm_dialog.dialog_autowrap = true
 confirm_dialog.wrap_controls = false
 confirm_dialog.min_size = Vector2i(640,380)
 var dialog_style := StyleBoxFlat.new()
 dialog_style.bg_color = Color("101e35")
 dialog_style.border_color = Color("58c5da")
 dialog_style.set_border_width_all(1)
 dialog_style.set_content_margin_all(12)
 confirm_dialog.add_theme_stylebox_override("panel",dialog_style)
 confirm_dialog.cancel_button_text = "Cancelar"
 confirm_dialog.title = "Autorizar leitura das mídias locais selecionadas"
 confirm_dialog.ok_button_text = "Confirmar processamento local"
 preload("res://cosmic/ui_icons.gd").iconify(confirm_dialog.get_ok_button(),"unlocked","Confirmar processamento local — autorizar leitura")
 preload("res://cosmic/ui_icons.gd").iconify(confirm_dialog.get_cancel_button(),"close","Cancelar — não autorizar leitura")
 confirm_dialog.confirmed.connect(_confirm)
 confirm_dialog.canceled.connect(func(): _pending_plan = {})
 add_child(confirm_dialog)
 start_button.grab_focus()

func _button(column: Container, text: String, action: Callable) -> Button:
 var button := Button.new()
 var icon := "inspect"
 if "Retomar" in text: icon = "retry"
 elif "Cancelar" in text: icon = "close"
 elif "Pular" in text: icon = "next"
 elif "depois" in text: icon = "back"
 preload("res://cosmic/ui_icons.gd").iconify(button,icon,text)
 button.pressed.connect(action)
 column.add_child(button)
 return button

func set_inventory(items: Array) -> void:
 if service.is_busy(): return
 inventory_items = items.duplicate(true)
 _last_plan = {}
 if is_node_ready():
  _invalidate_confirmation()
  resume_button.disabled = true

func _invalidate_confirmation() -> void:
 _pending_plan = {}
 if confirm_dialog != null: confirm_dialog.hide()

func _review() -> void:
 if service.is_busy(): return
 if system_picker.selected < 0:
  status_label.text = "Escolha explicitamente um sistema."
  return
 var selected: Array = []
 for category in categories:
  if categories[category].button_pressed: selected.append(category)
 var config := Config.choose(Config.SYSTEMS[system_picker.selected], root_input.text, selected)
 if not config.ok:
  status_label.text = "Informe um sistema e uma raiz local absoluta válidos."
  return
 _pending_plan = Planner.build(config, inventory_items)
 if _pending_plan.games_total == 0 and not config.categories.is_empty():
  status_label.text = "Nenhuma referência exata disponível neste inventário/sistema. Nada será lido. Atari requer adaptador de metadados compatível."
  _pending_plan = {}
  return
 _resume = false
 _show_review()

func _review_resume() -> void:
 if service.is_busy() or _last_plan.is_empty(): return
 _pending_plan = _last_plan.duplicate(true)
 _resume = true
 _show_review()

func offer_resume(plan: Dictionary) -> void:
 # Host may restore the last explicit configuration from its private settings.
 # Supplying a plan never starts I/O: user must review and confirm again.
 if service.is_busy(): return
 _last_plan = plan.duplicate(true)
 if is_node_ready(): resume_button.disabled = _last_plan.is_empty()

func _show_review() -> void:
 confirm_dialog.arm_opening_event(last_input_event)
 confirm_dialog.dialog_text = "Processamento local: %d arquivos para %d jogos.\n%d associações indisponíveis ou não suportadas.\nSistema: %s\nRaiz: %s\nCategorias: %s\nLer novamente e calcular hash atual de todos estes arquivos (inclusive os concluídos anteriormente)? Validar imagens suportadas e associar referências exatas ao catálogo desta sessão. Não altera originais nem confirma edição. PDFs não serão convertidos." % [
  _pending_plan.files_total, _pending_plan.games_total, _pending_plan.issues.size(),
  _pending_plan.config.system, _pending_plan.config.root, ", ".join(_pending_plan.config.categories)]
 confirm_dialog.popup_centered_clamped(Vector2i(640, 380),0.90)

func _confirm() -> void:
 if _pending_plan.is_empty() or service.is_busy(): return
 if before_start.is_valid():
  var saved: int = before_start.call(_pending_plan)
  if saved != OK:
   status_label.text = "Configuração privada não foi salva; nenhuma mídia lida: %s" % saved
   return
 _last_plan = _pending_plan.duplicate(true)
 _pending_plan = {}
 var error := service.begin(_last_plan, journal_path, true, _resume, inventory_items)
 if error != OK:
  status_label.text = "Não foi possível iniciar o processamento local: %s" % error
  return
 _was_running = true
 _set_busy(true)

func _set_busy(busy: bool) -> void:
 start_button.disabled = busy
 resume_button.disabled = busy or _last_plan.is_empty()
 cancel_button.disabled = not busy
 skip_button.disabled = busy
 later_button.disabled = busy
 system_picker.disabled = busy
 root_input.editable = not busy
 for checkbox in categories.values(): checkbox.disabled = busy

func _process(_delta: float) -> void:
 if not _was_running: return
 var snapshot := service.poll()
 progress_bar.max_value = maxi(1, int(snapshot.get("files_total", 0)))
 progress_bar.value = snapshot.get("files_done", 0)
 status_label.text = "Processamento local: %s\nArquivos concluídos %d / %d · erros %d · jogos com leitura completa %d / %d\nAssociações omitidas %d · fontes alteradas %d\nBytes lidos %d · tamanho descoberto %d (não é estimativa total)" % [
  {"done":"Leitura concluída","completed_with_errors":"Leitura concluída com erros","cancelled":"Cancelado","validating_images":"Validando imagens","running":"Lendo arquivos"}.get(snapshot.status,snapshot.status), snapshot.get("files_done", 0), snapshot.get("files_total", 0), snapshot.get("files_error", 0),
  snapshot.get("games_done", 0), snapshot.get("games_total", 0), snapshot.get("associations_omitted", 0), snapshot.get("files_changed", 0), snapshot.get("bytes_read", 0), snapshot.get("bytes_total_discovered", 0)]
 for issue in snapshot.get("issues", []).slice(0, 5):
  status_label.text += "\nOmitido: %s · %s" % [issue.get("tag", "") if not str(issue.get("tag", "")).is_empty() else issue.get("category", ""), issue.get("status", "")]
 for failure in snapshot.get("file_failures", []).slice(0, 5):
  status_label.text += "\nFalha de arquivo: %s" % failure.get("error", "")
 if snapshot.get("issues", []).size() > 5 or snapshot.get("file_failures", []).size() > 5:
  status_label.text += "\nResumo limitado; detalhes completos preservados no resultado local."
 if not service.is_busy() and snapshot.status in ["done", "completed_with_errors", "cancelled", "storage_error", "setup_error", "thread_error"]:
  _was_running = false
  _set_busy(false)
  processing_finished.emit(snapshot)

func _dismiss(skipped: bool) -> void:
 if service.is_busy(): return
 _invalidate_confirmation()
 hide()
 dismissed.emit(Config.defer_setup(skipped))

func _exit_tree() -> void:
 service.shutdown()
