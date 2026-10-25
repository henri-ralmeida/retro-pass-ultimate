extends SceneTree
const Library = preload("res://cosmic/atari_library_view.gd")
class Host extends Node:
 var application_focused := true
 var scene_active := true
 var reduced_motion := false
var failures: Array[String] = []
var checks := 0
var exits := 0
var expected_exits := 1
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures.append(message)
func run() -> void:
 var host := Host.new()
 root.add_child(host)
 var view := Library.new()
 root.add_child(view)
 view.configure(host)
 view.set_process(false)
 view.exit_requested.connect(func(): exits += 1)
 view.open()
 if OS.get_environment("RETROPASS_ATARI_MEDIA_MANIFEST").is_empty():
  check(not view.insertion_ready and not view.start_insertion(),"Missing media never starts or invents animation")
  check(view.ITEMS.size()==1 and view.exhibit.canonical_cartridge==null,"Missing media stays honest")
 else:
  check(view.insertion_ready,"Source-hash-bound insertion prepares")
  var cart: Node3D = view.exhibit.canonical_cartridge
  var identity := cart.get_instance_id()
  var parent := cart.get_parent()
  var inside := cart.transform
  var camera_pose: Transform3D = view.camera.transform
  var camera_size: float = view.camera.size
  check(view.ITEMS.size()==1,"Only explicitly supplied Adventure remains eligible")
  for stop in [0.2,0.9,1.7,2.5,2.9]:
   check(view.start_insertion(),"Start from collection")
   check(not view.start_insertion(),"Repeated start is idempotent")
   view._activate_focused_action()
   check(not view.insertion_returning,"Repeated confirm cannot cancel through focused Back")
   view.advance_insertion(stop)
   var mid := cart.transform
   var time: float = view.insertion_session.rig.clock.time
   host.application_focused=false
   view._process(20.0)
   check(cart.transform==mid and view.insertion_session.rig.clock.time==time,"Focus loss freezes without accumulated delta")
   host.application_focused=true
   check(not view.inspect("manual"),"Inspection cannot overwrite active cartridge")
   view.reset_inspection()
   check(view.camera.transform==camera_pose and view.camera.size==camera_size,"Active camera remains approved/fixed")
   view.go_back()
   check(cart.transform.is_equal_approx(mid),"Back request does not teleport")
   view.go_back()
   check(exits==0,"Repeated Back does not skip reversal or exit")
   view.advance_insertion(10)
   check(view.state=="collection" and cart.transform==inside,"Return exact inside baseline")
   check(not view.exhibit.carton_open and not view.exhibit.cartridge_seated,"Return clears packaging/seat flags")
   check(cart.get_instance_id()==identity and cart.get_parent()==parent,"One canonical node, same parent")
  for role in ["box","cartridge","manual"]:
   check(view.inspect(role),"Native inspection still opens")
   if role=="box": view._toggle_carton()
   if role=="manual": view.turn_manual(1)
   view.go_back()
   check(view.state=="collection" and view.insertion_ready,"Inspection return reprepares hidden rig")
   check(cart.transform==inside and cart.get_instance_id()==identity,"Inspection return keeps exact same inside cart")
  host.reduced_motion=true
  check(view.start_insertion(),"Reduced motion starts")
  view.advance_insertion(0)
  check(view.exhibit.cartridge_seated,"Reduced motion endpoint coherent")
  view.go_back()
  check(view.state=="collection" and cart.transform==inside,"Reduced motion return coherent")
  host.reduced_motion=false
  for repeat in 4:
   view.close()
   view.open()
   check(view.insertion_ready and view.exhibit.canonical_cartridge.get_instance_id()==identity,"Open/close does not duplicate native assets")
  view.start_insertion()
  view.advance_insertion(1.1)
  view.close()
  check(not view.visible and view.state=="closed","Forced close hides before teardown")
  view.open()
  check(view.insertion_ready and cart.transform==inside,"Interrupted forced close reopens closed safely")
  view.start_insertion()
  view.advance_insertion(0.4)
  view.pivot.position.x += 0.01
  view.advance_insertion(0.1)
  var failure_notice: String = view.status.text
  view._refresh_status()
  view.advance_insertion(1.0)
  check(view.insertion_failed and view.status.text==failure_notice,"Guard-false is latched and failure status preserved")
  view.go_back()
  check(exits==1 and not view.exhibit.visible,"Guard-false Back hides before exit")
  view.close()
  view.close()
  view.open()
  check(view.insertion_ready and view.pivot.transform==Transform3D.IDENTITY,"Guard-false reload restores clean layout")
  cart = view.exhibit.canonical_cartridge
  view.start_insertion()
  view.advance_insertion(0.4)
  cart.free()
  view.advance_insertion(0.1)
  check(view.insertion_failed,"Deleted canonical freezes with explicit failure")
  view.go_back()
  check(exits==2 and not view.exhibit.visible,"Failure Back hides and exits without claiming reverse")
  view.close()
  view.close()
  view.open()
  check(view.insertion_ready and is_instance_valid(view.exhibit.canonical_cartridge),"Failed rig reloads native models on reopen")
  for role in ["console","box"]:
   view.start_insertion()
   view.exhibit.asset_roots[role].free()
   view.advance_insertion(0.1)
   check(view.insertion_failed,"Removed "+role+" is a guarded failure, not a stale dereference")
   view.go_back()
   view.close()
   view.close()
   view.open()
   check(view.insertion_ready,"Removed "+role+" safely rebuilds on reopen")
  view.exhibit.asset_roots.box.free()
  check(not view.start_insertion() and view.insertion_failed,"Guard failure before first tick enters safe latched state")
  view.go_back()
  view.close()
  view.close()
  view.open()
  check(view.insertion_ready,"Failed start also rebuilds safely")
  expected_exits=6
 view.go_back()
 check(exits==expected_exits,"Collection Back exits normally")
 view.close()
 view.free()
 host.free()
 for failure in failures: push_error(failure)
 print("ATARI INSERTION LIBRARY: ",checks," checks, ",failures.size()," failures")
 quit(0 if failures.is_empty() else 1)
