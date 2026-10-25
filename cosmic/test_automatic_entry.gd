extends SceneTree
var failures: Array[String] = []
var checks := 0
var main
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures.append(message)
func freeze_tween() -> void:
 if main.entry_tween and main.entry_tween.is_valid(): main.entry_tween.kill()
func reveal_manually() -> void:
 freeze_tween()
 main._finish_library_entry(main.entry_generation)
 freeze_tween()
 main._complete_library_reveal(main.entry_generation,main.entry_library_id,main.entry_autostart_token)
func run() -> void:
 var view = preload("res://cosmic/atari_library_view.gd").new()
 root.add_child(view)
 view.configure(root)
 # Synthetic selection-policy fixture only, not multi-game Atari media support.
 var rng := RandomNumberGenerator.new()
 rng.seed=123
 view.catalog_choice = preload("res://cosmic/catalog_choice.gd").new(rng)
 view.ITEMS.assign([{ "id":"synthetic_a_variant_1" },{ "id":"synthetic_a_variant_2" },{ "id":"missing", "file_status":"missing" }])
 view.begin_catalog_visit()
 var selected: String=view.catalog_choice.get_selected_id()
 var rng_state: int=rng.state
 view.begin_catalog_visit()
 view.arm_entry_autostart()
 check(view.catalog_choice.get_selected_id()==selected and rng.state==rng_state,"Repeated begin plus arm consumes exactly one random draw and preserves variant ID")
 view.close()
 view.arm_entry_autostart()
 check(view.catalog_choice.get_selected_id()!=selected,"A new closed/reopened visit uses existing no-repeat eligible policy")
 view.free()
 main = load("res://cosmic/main.tscn").instantiate()
 root.add_child(main)
 await process_frame
 main.set_process(false)
 main.reduced_motion=true
 var sms = main.library_view
 var sms_patch := OS.get_environment("RETROPASS_SMS_MECHANICAL_PATCH")
 OS.set_environment("RETROPASS_SMS_MECHANICAL_PATCH", "")
 main.enter_library()
 check(main.library_view==sms and sms.has_method("complete_entry_autostart") and not sms.insertion_active,"SMS hook consumes visit but missing geometry cannot animate or substitute media")
 OS.set_environment("RETROPASS_SMS_MECHANICAL_PATCH", sms_patch)
 main.leave_library()
 main.navigate(1)
 var atari = main.library_view
 check(not atari.autostart_intent.pending,"System activation alone does not arm")
 main.reduced_motion=false
 main.enter_library()
 freeze_tween()
 var old_generation: int=main.entry_generation
 var old_id: int=main.entry_library_id
 var old_token: int=main.entry_autostart_token
 main._focus_lost()
 main._focus_returned()
 reveal_manually()
 check(atari.state=="collection","Focus loss before reveal cancels pending start")
 main._complete_library_reveal(old_generation,old_id,old_token)
 check(atari.state=="collection","Focus return and repeated callback never rearm")
 main.leave_library()
 main.enter_library()
 freeze_tween()
 var current_generation: int=main.entry_generation
 check(current_generation!=old_generation,"Each real visit gets a new transition generation")
 main._finish_library_entry(old_generation)
 check(main.library_state=="entering","Old transition finish cannot open new visit")
 main._finish_library_entry(current_generation)
 freeze_tween()
 check(atari.state=="collection","Wait until reveal completes, not model import")
 main._complete_library_reveal(old_generation,old_id,old_token)
 check(atari.state=="collection","Old reveal cannot trigger or cancel current visit")
 main._complete_library_reveal(current_generation,main.entry_library_id,main.entry_autostart_token)
 var private_media := not OS.get_environment("RETROPASS_ATARI_MEDIA_MANIFEST").is_empty()
 if private_media:
  atari.set_process(false)
  check(atari.state=="insertion","Eligible Atari visit starts automatically after reveal")
  check(atari.ITEMS.size()==1 and atari.catalog_choice.get_eligible_count()==1,"Only explicit Adventure is eligible")
  var cart: Node3D=atari.exhibit.canonical_cartridge
  var identity:=cart.get_instance_id()
  atari.advance_insertion(1.2)
  var pose:=cart.transform
  main._focus_lost()
  atari._process(10)
  check(cart.transform==pose,"Focus loss during active insertion pauses")
  main._focus_returned()
  atari.advance_insertion(0.1)
  check(cart.transform!=pose,"Active insertion resumes without starting another visit")
  atari.go_back()
  atari.advance_insertion(10)
  main._complete_library_reveal(current_generation,main.entry_library_id,main.entry_autostart_token)
  check(atari.state=="collection" and cart.get_instance_id()==identity,"Back-to-box never auto-restarts or duplicates cart")
 else:
  check(atari.state=="collection" and not atari.insertion_ready,"Missing media remains honest/manual-only, no invented geometry")
 # An old view callback cannot affect the next visit even if the same view is reused.
 var stale: int=main.entry_autostart_token
 main.leave_library()
 main.enter_library()
 freeze_tween()
 var pending: int=main.entry_autostart_token
 atari.complete_entry_autostart(stale)
 check(atari.autostart_intent.generation==pending,"Stale callback cannot cancel a newly armed visit")
 main.leave_library()
 main._finish_library_entry(main.entry_generation-1)
 main._complete_library_reveal(current_generation,old_id,stale)
 check(main.library_state=="system" and not atari.visible,"Close invalidates all callbacks")
 main.enter_library()
 freeze_tween()
 main._finish_library_entry(main.entry_generation)
 freeze_tween()
 main._focus_lost()
 main._focus_returned()
 main._complete_library_reveal(main.entry_generation,main.entry_library_id,main.entry_autostart_token)
 check(atari.state=="collection","Focus loss during reveal also cancels automatic intention")
 main.leave_library()
 main.reduced_motion=true
 main.enter_library()
 if private_media:
  check(atari.state=="insertion" and atari.exhibit.cartridge_seated,"Reduced motion reaches coherent automatic endpoint")
  atari.go_back()
  check(atari.state=="collection","Reduced Back does not rearm")
 else: check(atari.state=="collection","Reduced mode never creates unavailable media")
 main.leave_library()
 main.reduced_motion=false
 main.enter_library()
 await create_timer(0.1).timeout
 check(main.library_state=="entering" and atari.state=="closed","Natural tween never starts insertion during approach")
 await create_timer(1.7).timeout
 check(main.library_state=="library" and not main.entry_veil.visible,"Natural transition reaches a fully revealed library")
 check(atari.state==("insertion" if private_media else "collection"),"Natural reveal callback triggers only eligible Atari animation")
 main.leave_library()
 main.reduced_motion=true
 main.navigate(-1)
 var sms_pose: Transform3D=main.camera.transform
 main._apply_entry_for_visit(0.6,current_generation)
 main._complete_library_reveal(current_generation,old_id,stale)
 check(main.camera.transform==sms_pose,"Stale transition interpolation cannot move the new console camera")
 check(main.library_view==sms and main.library_state=="system","Console swap rejects Atari callback")
 main.free()
 for error in failures: push_error(error)
 print("AUTOMATIC ENTRY: ",checks," checks, ",failures.size()," failures")
 quit(0 if failures.is_empty() else 1)
