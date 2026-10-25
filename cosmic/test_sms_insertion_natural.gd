extends SceneTree
## Actual main/tweens/node _process, not sampled timeline jumps. Cloud headless QA.
const Session = preload("res://cosmic/sms_insertion_session.gd")
const ApprovedHome = preload("res://cosmic/perspective_box_view.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures.append(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 check(Session.OPEN_BASE_SPINE==ApprovedHome.BASE_SPINE_DEGREES and Session.OPEN_SPINE_LID==ApprovedHome.SPINE_LID_DEGREES,"Insertion uses exact approved sleeve-safe dual-hinge angles, never 90/90")
 if OS.get_environment("RETROPASS_SMS_MECHANICAL_PATCH").is_empty() or OS.get_environment("RETROPASS_SMS_MEDIA_BINDING").is_empty():
  print("SMS_NATURAL checks=",checks," failures=",failures," private runtime cycles=not run (override absent)")
  quit(0 if failures.is_empty() else 1)
  return
 root.size = Vector2i(1152,648)
 var old_cap := Engine.max_fps
 var app = load("res://cosmic/main.tscn").instantiate()
 root.add_child(app)
 await process_frame
 app.auto_history_armed = false
 for mode in ["60fps","30fps","irregular"]:
  Engine.max_fps = 30 if mode=="30fps" else 60
  app.reduced_motion = false
  app.enter_library()
  var view = app.sms_library_view
  var deadline := Time.get_ticks_msec()+22000
  var frames := 0
  var identity := 0
  var parent: Node
  var departure := Transform3D.IDENTITY
  var paused := false
  while Time.get_ticks_msec()<deadline:
   if mode=="irregular": Engine.max_fps = [60,30,45,20][(frames/9)%4]
   await process_frame
   frames += 1
   if view.insertion_failed:
    check(false,mode+" natural failure: "+view.insertion_session.last_error)
    break
   if view.insertion_active:
    if identity==0:
     identity=view.box.cartridge.get_instance_id()
     parent=view.box.cartridge.get_parent()
     departure=view.insertion_session._camera_rest
    check(view.box.cartridge.get_instance_id()==identity and view.box.cartridge.get_parent()==parent,mode+" same canonical node and parent")
    if not paused and view.insertion_session.time>2.0:
     paused=true
     app._focus_lost()
     var held: float = view.insertion_session.time
     await create_timer(0.18).timeout
     check(view.insertion_session.time==held,mode+" natural focus pause consumes no timeline")
     app._focus_returned()
    if view.insertion_session.state=="seated": break
  check(view.insertion_active and not view.insertion_failed and view.insertion_session.state=="seated",mode+" naturally reaches slot endpoint")
  if view.insertion_failed or not view.insertion_active: break
  view.go_back()
  while view.insertion_active and not view.insertion_failed and Time.get_ticks_msec()<deadline:
   if mode=="irregular": Engine.max_fps=[60,30,45,20][(frames/9)%4]
   await process_frame
   frames += 1
  check(not view.insertion_active and not view.insertion_failed,mode+" naturally reverses to collection")
  check(view.box.cartridge.transform==view.box.inside_pose,mode+" exact inside endpoint")
  check(view.camera.global_transform.is_equal_approx(departure),mode+" exact departure camera")
  print("SMS_NATURAL_CYCLE ",mode," frames=",frames," cart_id=",identity," failures=",failures)
  app.leave_library()
  await process_frame
  await process_frame
 Engine.max_fps=old_cap
 app.free()
 print("SMS_NATURAL checks=",checks," failures=",failures)
 quit(0 if failures.is_empty() else 1)
