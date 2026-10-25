extends SceneTree
const Path = preload("res://cosmic/sms_insertion_path.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  printerr("FAIL ",label)
func _init() -> void:
 var first := Path.sample(0)
 check(first.pose.origin == Path.INSIDE,"exact inside")
 check(first.door == Transform3D.IDENTITY,"exact closed door")
 check(first.opening == 0 and first.reveal == 0,"closed values")
 for value in [-1.0,NAN,INF]: check(Path.sample(value).pose == first.pose,"invalid time clamps safely")
 var edges := [Path.REVEAL,Path.REVEAL+Path.OPEN,Path.REVEAL+Path.OPEN+Path.EXTRACT,Path.REVEAL+Path.OPEN+Path.EXTRACT+Path.CLEAR,Path.SLOT_BEGIN-Path.TRANSFER,Path.SLOT_BEGIN,Path.TOTAL]
 for t in edges:
  var left := Path.sample(t-0.000001)
  var right := Path.sample(t+0.000001)
  check(left.pose.origin.distance_to(right.pose.origin)<0.00001,"continuous position")
  check(left.pose.basis.is_equal_approx(right.pose.basis),"continuous rotation")
 var at_slot := Path.sample(Path.SLOT_BEGIN)
 var expected: Transform3D = Transform3D(Basis.IDENTITY,Path.CONSOLE_ORIGIN)*Path.Slot.sample(0).cartridge_pose
 check(at_slot.pose.is_equal_approx(expected),"slot sampler join exact")
 for i in range(1001):
  var t := Path.TOTAL*i/1000.0
  var pose := Path.sample(t)
  var reverse := Path.sample(Path.TOTAL-(Path.TOTAL-t))
  check(pose.pose.is_equal_approx(reverse.pose),"time reversal same pose")
  check(pose.door.is_equal_approx(reverse.door),"time reversal same door")
  check(pose.pose.is_finite() and is_equal_approx(pose.pose.basis.determinant(),1.0),"rigid finite native pose")
  if t<Path.REVEAL+Path.OPEN: check(pose.pose.origin==Path.INSIDE,"no extraction before both hinges open")
 print("SMS_PATH checks=",checks," failures=",failures)
 quit(failures)
