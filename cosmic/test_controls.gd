extends SceneTree
const Profile = preload("res://cosmic/input_profile.gd")
var assertions := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
 assertions += 1
 if not value:
  failures.append(message)
  push_error(message)

func key(code: Key, echo: bool = false) -> InputEventKey:
 var event := InputEventKey.new()
 event.keycode = code
 event.pressed = true
 event.echo = echo
 return event

func pad(button: JoyButton, device: int = 27) -> InputEventJoypadButton:
 var event := InputEventJoypadButton.new()
 event.button_index = button
 event.device = device
 event.pressed = true
 return event

func _initialize() -> void: run.call_deferred()

func run() -> void:
 var profile := Profile.new()
 check(Profile.family_for_name("Sony DualSense Wireless Controller")=="playstation","Sony/DualSense identified")
 check(Profile.family_for_name("PS4 Controller")=="playstation","PS4 identified")
 check(Profile.family_for_name("Xbox Series Controller")=="xbox","Xbox identified")
 for name in ["XInput Controller","Wireless Controller","Steam Virtual Gamepad",""]:
  check(Profile.family_for_name(name)=="generic","Ambiguous name stays generic: "+name)
 check(profile.glyph("inspect",true,"Xbox Controller")=="X","Xbox inspection uses X face position")
 check(profile.glyph("inspect",true,"DualSense")=="ps_square","PlayStation inspection uses square")
 check(profile.glyph("confirm",true,"DualSense")=="ps_cross","PlayStation confirmation uses cross")
 check(profile.glyph("confirm",false)=="X" and profile.glyph("back",false)=="Z","Keyboard defaults are X and Z")
 profile.family_override="playstation"
 check(profile.glyph("inspect",true,"XInput Controller")=="ps_square","Manual family override resolves hidden identity")
 check(profile.rebind("confirm",KEY_I,false),"Keyboard remapping accepted")
 check(profile.keys.inspect==KEY_X and profile.keys.confirm==KEY_I,"Conflicting remap swaps actions without losing inspection")
 check(not profile.rebind("confirm",-1,true),"Invalid pad code rejected")
 var scene = load("res://cosmic/main.tscn").instantiate()
 scene.input_profile = Profile.new()
 scene.input_profile.config_path="res://evidence/cosmic/controls_fixture.cfg"
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene.input_profile.keys=Profile.KEYS.duplicate()
 scene.input_profile.buttons=Profile.BUTTONS.duplicate()
 scene.input_profile.family_override="auto"
 scene._refresh_controls()
 check(scene.ui.get_node_or_null("PrototypeLabel")==null,"Subtitle removed")
 check(scene.header.text=="RETRO PASS ULTIMATE","Application name preserved")
 check(not scene.hint.visible and not scene.status.visible,"Long instructions absent from presentation")
 check(scene.confirm_button.visible and not scene.back_button.visible,"Selection footer is contextual")
 scene.console_button.grab_focus()
 scene.cooldown=0
 scene._input(key(KEY_X))
 check(scene.selection_count==1 and not scene.inspect_mode,"Keyboard X confirms instead of opening inspection")
 scene.cooldown=0
 scene._input(key(KEY_X,true))
 check(scene.selection_count==1,"Held confirm does not repeat")
 scene.input_profile.family_override="playstation"
 scene._input(pad(JOY_BUTTON_X))
 check(scene.inspect_mode and scene.selection_count==1,"West face button opens inspection, never selects")
 check(scene.input_device=="gamepad" and scene.active_pad==27,"Active input switches to pad")
 check(scene.inspect_button.find_child("InputGlyph",true,false).symbol=="ps_square","UI draws square independently of keyboard X")
 check(scene.back_button.visible and scene.reset_button.visible and not scene.confirm_button.visible,"Inspection footer shows back/reset only")
 scene.rotate_inspection(Vector2(70,20))
 scene.zoom_inspection(50)
 check(is_equal_approx(scene.inspection_zoom,1.35),"Gamepad mode preserves safe zoom bound")
 scene._input(pad(JOY_BUTTON_B))
 check(not scene.inspect_mode and not scene.history_open,"Pad east face returns")
 scene._input(key(KEY_I))
 check(scene.inspect_mode and scene.input_device=="keyboard","Keyboard use restores keyboard prompts")
 scene._input(key(KEY_Z))
 check(not scene.inspect_mode,"Keyboard Z returns")
 scene.open_history()
 scene._input(key(KEY_Z))
 check(not scene.history_open and not scene.inspect_mode,"Z closes history independently")
 scene._settle_history_motion()
 scene._set_input_device("gamepad",27,"Xbox Controller")
 scene.input_profile.family_override="auto"
 scene._refresh_controls()
 check(scene.inspect_button.find_child("InputGlyph",true,false).symbol=="X","Xbox detection refreshes visible X")
 scene._set_input_device("gamepad",28,"DualSense")
 check(scene.inspect_button.find_child("InputGlyph",true,false).symbol=="ps_square","Switching between devices refreshes symbols")
 scene._joy_connection_changed(28,false)
 check(scene.active_pad != 28,"Disconnected active device is released")
 scene._set_input_device("keyboard")
 scene.toggle_control_settings()
 scene.cooldown=0
 scene.confirm_selection("behind_settings")
 check(scene.selection_count==1,"Modal controls block background confirmation")
 scene._begin_rebind("confirm")
 scene._input(key(KEY_C))
 check(scene.input_profile.keys.confirm==KEY_C and scene.capture_action.is_empty(),"Settings capture physical keyboard remap")
 var loaded := Profile.new()
 loaded.config_path=scene.input_profile.config_path
 loaded.load_settings()
 check(loaded.keys.confirm==KEY_C,"Remapping survives reload")
 scene._begin_rebind("inspect")
 scene._input(key(KEY_ESCAPE))
 check(scene.capture_action.is_empty() and scene.settings_panel.visible,"Escape cancels capture without closing settings")
 scene.toggle_control_settings()
 scene.console_button.grab_focus()
 scene.cooldown=0
 scene._input(key(KEY_X))
 check(scene.selection_count==1,"Old confirm binding no longer selects")
 scene._input(key(KEY_C))
 check(scene.selection_count==2,"Remapped confirm invokes the actual selection path")
 scene._focus_lost()
 scene._input(pad(JOY_BUTTON_X))
 check(not scene.inspect_mode,"Unfocused pad input is blocked")
 scene._focus_returned()
 scene.toggle_inspection()
 scene.inspection_dragging=true
 scene._set_input_device("gamepad",29,"Unknown")
 scene._joy_connection_changed(29,false)
 check(not scene.inspection_dragging and scene.inspect_mode,"Disconnect cancels drag without losing inspection state")
 scene.queue_free()
 await process_frame
 var result={"assertions":assertions,"failures":failures,"passed":failures.is_empty(),"mode":"headless synthetic input and device-name fixtures; no physical controller validation"}
 FileAccess.open("res://evidence/cosmic/controls_tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("CONTROLS_TESTS ",JSON.stringify(result))
 quit(0 if failures.is_empty() else 1)
