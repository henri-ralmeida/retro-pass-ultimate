extends RefCounted
## Pure modal capture state machine. Host supplies neutral snapshots and writes files.
const Profile = preload("res://cosmic/sms_mapping_profile.gd")
enum State { CLOSED, BROWSING, ARMING, CAPTURING, HELD_CANDIDATE, CONFLICT, RELEASE_GATE, SAVE_ERROR }
const NEUTRAL_SECONDS := 0.15
const AXIS_PRESS := 0.65
const AXIS_RELEASE := 0.25
const CANCEL_HOLD_SECONDS := 0.8
var state: State = State.CLOSED
var live = Profile.new()
var draft = Profile.new()
var focused := true
var device_connected := true
var target_device := -1 # Runtime only. Never a persisted hardware identity.
var selected_action := ""
var selected_channel := ""
var candidate: Dictionary = {}
var conflict_action := ""
var notice := ""
var neutral_elapsed := 0.0
var cancel_elapsed := 0.0
var cancel_hold_button := int(JOY_BUTTON_B) # For an unknown pad, host must select a verified raw button or -1.

func open(profile_snapshot: Dictionary) -> bool:
 if state != State.CLOSED: return false
 if not live.load_snapshot(profile_snapshot) or not draft.load_snapshot(profile_snapshot): return false
 state = State.BROWSING
 focused = true
 notice = "Selecione um botão no controle ou na lista."
 return true

func dirty() -> bool:
 return live.snapshot() != draft.snapshot()

func begin(action: String, channel: String, device: int = -1) -> bool:
 if state not in [State.BROWSING, State.SAVE_ERROR] or not focused: return false
 if action not in draft.actions() or channel not in Profile.CHANNELS: return false
 if channel == "gamepad" and (device < 0 or not device_connected): return false
 selected_action = action
 selected_channel = channel
 target_device = device if channel == "gamepad" else -1
 candidate.clear()
 conflict_action = ""
 neutral_elapsed = 0.0
 cancel_elapsed = 0.0
 state = State.ARMING
 notice = "Solte as teclas e botões para começar."
 return true

func advance(delta: float, all_neutral: bool, cancel_button_held := false) -> void:
 if not focused or state == State.CLOSED: return
 if state in [State.ARMING, State.RELEASE_GATE]:
  neutral_elapsed = neutral_elapsed + maxf(0.0, delta) if all_neutral else 0.0
  if neutral_elapsed >= NEUTRAL_SECONDS:
   state = State.CAPTURING if state == State.ARMING else State.BROWSING
   notice = "Pressione e solte uma entrada. Esc cancela." if state == State.CAPTURING else notice
 if state == State.HELD_CANDIDATE and candidate.get("kind", "") == "button" and int(candidate.get("code", -2)) == cancel_hold_button:
  cancel_elapsed = cancel_elapsed + maxf(0.0, delta) if cancel_button_held else 0.0
  if cancel_elapsed >= CANCEL_HOLD_SECONDS: cancel("Captura cancelada; nenhuma atribuição foi alterada.")

func handle(event: InputEvent) -> bool:
 if state == State.CLOSED: return false
 if not focused: return true
 if state not in [State.ARMING, State.CAPTURING, State.HELD_CANDIDATE, State.CONFLICT, State.RELEASE_GATE]: return false
 if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_F1]:
  if state != State.RELEASE_GATE: cancel()
  return true
 # The host MUST stop background routing while this modal is open. Returning false
 # permits its own GUI Cancel button and conflict choices, not the underlying HOME.
 if event is InputEventMouseButton or event is InputEventMouseMotion: return false
 if state == State.CONFLICT: return false
 # Capture owns other raw inputs, including rejected events from other devices.
 if state in [State.ARMING, State.RELEASE_GATE]: return true
 if selected_channel == "keyboard":
  if not event is InputEventKey or event.echo: return true
  if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed: return true
  var code: int = event.physical_keycode if event.physical_keycode else event.keycode
  if state == State.CAPTURING and event.pressed:
   _hold_candidate({"kind": "key", "code": code})
  elif state == State.HELD_CANDIDATE and not event.pressed and int(candidate.get("code", -1)) == code:
   _accept_candidate()
 elif (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device == target_device and device_connected:
  if event is InputEventJoypadButton:
   if state == State.CAPTURING and event.pressed:
    _hold_candidate({"kind": "button", "code": int(event.button_index)})
   elif state == State.HELD_CANDIDATE and candidate.get("kind", "") == "button" and int(candidate.code) == event.button_index and not event.pressed:
    _accept_candidate()
  elif event is InputEventJoypadMotion:
   if state == State.CAPTURING and is_finite(event.axis_value) and absf(event.axis_value) >= AXIS_PRESS:
    _hold_candidate({"kind": "axis", "code": int(event.axis), "sign": -1 if event.axis_value < 0 else 1})
   elif state == State.HELD_CANDIDATE and candidate.get("kind", "") == "axis" and int(candidate.code) == event.axis and absf(event.axis_value) <= AXIS_RELEASE:
    _accept_candidate()
 return true

func _hold_candidate(value: Dictionary) -> void:
 if not Profile.valid_binding(value, selected_channel): return
 candidate = value
 cancel_elapsed = 0.0
 state = State.HELD_CANDIDATE
 notice = "Solte para atribuir. Segurar Voltar cancela." if selected_channel == "gamepad" else "Solte a tecla para atribuir."

func _accept_candidate() -> void:
 conflict_action = draft.conflict_for(selected_action, selected_channel, candidate)
 if not conflict_action.is_empty():
  state = State.CONFLICT
  notice = "Entrada já usada por %s. Trocar as duas ou cancelar?" % conflict_action
 else:
  draft.rebind(selected_action, selected_channel, candidate)
  _release_gate("Atribuição preparada. Salvar aplica; Cancelar descarta.")

func resolve_conflict(swap: bool) -> bool:
 if state != State.CONFLICT or not focused: return false
 if swap: draft.rebind(selected_action, selected_channel, candidate, true)
 _release_gate("As duas atribuições foram trocadas no rascunho." if swap else "Conflito cancelado; atribuições preservadas.")
 return true

func cancel(message := "Captura cancelada; nenhuma atribuição foi alterada.") -> void:
 if state == State.CLOSED: return
 _release_gate(message)

func _release_gate(message: String) -> void:
 candidate.clear()
 conflict_action = ""
 selected_action = ""
 neutral_elapsed = 0.0
 cancel_elapsed = 0.0
 state = State.RELEASE_GATE
 notice = message

func focus_changed(value: bool) -> void:
 focused = value
 if not value and state != State.CLOSED:
  _release_gate("Captura interrompida. As alterações preparadas foram preservadas.")

func disconnected(device: int) -> void:
 if device != target_device: return
 device_connected = false
 if state != State.CLOSED: _release_gate("Controle desconectado. Escolha-o novamente; nada foi salvo.")

func assign_device(device: int) -> bool:
 if state != State.BROWSING or not focused or device < 0: return false
 target_device = device
 device_connected = true
 return true

func save_with(writer: Callable) -> Error:
 if state not in [State.BROWSING, State.SAVE_ERROR] or not focused: return ERR_BUSY
 var data: Dictionary = draft.snapshot()
 var verification = Profile.new()
 if not verification.load_snapshot(data): return ERR_INVALID_DATA
 # Writer must use an atomic replace and preserve the old valid file on failure.
 # This stage never writes the user's existing controls.cfg.
 var result: Error = writer.call(data.duplicate(true))
 if result != OK:
  state = State.SAVE_ERROR
  notice = "Não foi possível salvar. Rascunho mantido; configuração anterior continua ativa."
  return result
 live.load_snapshot(data)
 state = State.BROWSING
 notice = "Configuração salva."
 return OK

func close(discard: bool = false) -> bool:
 if state == State.CLOSED: return true
 if dirty() and not discard: return false
 draft.load_snapshot(live.snapshot())
 candidate.clear()
 state = State.CLOSED
 return true
