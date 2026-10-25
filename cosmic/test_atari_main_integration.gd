extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func _expect(ok: bool, message: String) -> void:
 if not ok: failures.append(message)
func _run() -> void:
 var main = load("res://cosmic/main.tscn").instantiate()
 root.add_child(main)
 await process_frame
 main.set_process(false)
 main.reduced_motion = true
 var sms_camera_basis: Basis = main.camera.basis
 var sms_library = main.library_view
 _expect(main.systems.size() == 2,"Two system descriptors registered")
 _expect(main.systems[0].system_id == "sega_master_system","SMS remains first")
 for repeat in 3:
  main.dwell_elapsed = 7.0
  main.navigate(1)
  _expect(main.current_index == 1,"Selector reaches Atari")
  _expect(is_zero_approx(main.dwell_elapsed),"System change clears automatic history timer")
  main.console_button.grab_focus()
  main.auto_history_armed = true
  main._advance_dwell(main.dwell_seconds + 1.0)
  _expect(main.history_open,"Atari automatic history opens once")
  _expect(main.systems[1].history_text in main.history_body.text,"Atari history never inherits SMS text")
  main.close_history()
  main._advance_dwell(main.dwell_seconds + 1.0)
  _expect(not main.history_open,"History cannot immediately rearm after Back")
  var repeat_key := InputEventKey.new()
  repeat_key.keycode = KEY_RIGHT
  repeat_key.pressed = true
  repeat_key.echo = true
  main._input(repeat_key)
  _expect(main.current_index == 1,"Held navigation cannot wrap during slow private import")
  _expect(main.exhibit == null,"Atari never instantiates SMS extras")
  _expect(not main.perspective_box_view.visible,"Atari never inherits SMS perspective box")
  _expect(main.library_view == main.atari_library_view,"Atari uses independent library")
  if OS.get_environment("RETROPASS_ATARI_MEDIA_MANIFEST").is_empty():
   main.toggle_inspection()
   _expect(not main.inspect_mode,"Absent console cannot open empty inspection")
   _expect(main.inspect_button.disabled,"Absent console inspection button disabled")
   _expect(main.camera.size > 0.0,"Absent console retains positive camera size")
  main._open_controller_settings(0)
  _expect(not main.controller_panel.is_open(),"SMS controller panel not misrepresented as Atari")
  if repeat == 0:
   _expect(not main.library_view.media_loaded,"Library models are lazy before first open")
  main.enter_library()
  _expect(main.library_state == "library","Atari enters library")
  main._advance_dwell(main.dwell_seconds + 1.0)
  _expect(not main.history_open,"Automatic history never interrupts Atari library")
  if not OS.get_environment("RETROPASS_ATARI_MEDIA_MANIFEST").is_empty():
   _expect(main.library_view.inspect("manual"),"Original 3D manual inspection")
   main.library_view.turn_manual(1)
   main.library_view.go_back()
   _expect(main.library_state == "library","Inspection Back stays in library")
  main.library_view.go_back()
  _expect(main.library_state == "system","Library Back returns selector")
  main.navigate(-1)
  _expect(main.current_index == 0,"Selector returns SMS")
  _expect(main.library_view == sms_library,"SMS library instance retained")
  _expect(is_instance_valid(main.exhibit),"SMS original exhibit restored")
  _expect(main.camera.basis.is_equal_approx(sms_camera_basis),"Approved SMS view basis preserved")
 main.navigate(1)
 main.reduced_motion = false
 main.enter_library()
 _expect(main.library_state == "entering","Animated entry starts")
 main._focus_lost()
 main._focus_returned()
 main.leave_library()
 _expect(main.library_state == "system","Interrupted entry cancellation returns selector")
 main.free()
 for failure in failures: push_error(failure)
 print("ATARI MAIN INTEGRATION FAILURES: ", failures.size())
 quit(0 if failures.is_empty() else 1)
