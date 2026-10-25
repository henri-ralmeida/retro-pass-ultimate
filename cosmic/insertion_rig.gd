extends RefCounted
## Exclusive writer for ONE existing cartridge. Never reparents or duplicates it.
## Supplied world poses must already be collision/camera validated by host QA.
## Cancellation retraces the same path; teardown restores exact local baseline.
const Path := preload("res://cosmic/insertion_path.gd")
var clock = Path.new()
var last_error := ""
var _cart: Node3D
var _parent: Node3D
var _parent_world := Transform3D.IDENTITY
var _rest := Transform3D.IDENTITY
var _poses: Array[Transform3D] = []
var _opening: Callable
var _valid: Callable

func configure(cart: Node3D, poses: Array[Transform3D], opening: Callable,
  identity_valid: Callable, geometry_validated: bool = false) -> bool:
 teardown()
 if not geometry_validated: return _fail("Geometry gate missing: do not infer a physical path from static exhibit poses.")
 if not is_instance_valid(cart) or not cart.is_inside_tree() or not cart.get_parent() is Node3D:
  return _fail("Existing in-tree canonical cartridge with Node3D parent required.")
 if poses.size() != 4 or not opening.is_valid() or not identity_valid.is_valid():
  return _fail("Four world poses, packaging callback and identity guard required.")
 for pose in poses:
  if not pose.is_finite() or absf(pose.basis.determinant()) < 0.000001:
   return _fail("Finite invertible world poses required.")
 if not poses[0].is_equal_approx(cart.global_transform):
  return _fail("First waypoint must match current cartridge pose; no setup teleport.")
 # Final movement must be straight on the cartridge's local +Y insertion axis;
 # no rotation or lateral correction is permitted while entering the slot.
 if not poses[2].basis.is_equal_approx(poses[3].basis): return _fail("Align before entering slot.")
 var travel := poses[2].origin - poses[3].origin
 if travel.length() < 0.001 or travel.normalized().dot(poses[3].basis.y.normalized()) < 0.99999:
  return _fail("Approach must lie above seat along the cartridge insertion axis.")
 if not bool(identity_valid.call()): return _fail("Canonical identity guard rejected rig.")
 _cart = cart
 _parent = cart.get_parent()
 _parent_world = _parent.global_transform
 _rest = cart.transform
 _poses.assign(poses)
 _opening = opening
 _valid = identity_valid
 clock = Path.new()
 last_error = ""
 return true

func insert(reduced_motion: bool = false) -> bool:
 if not _guard(): return false
 clock.reduced_motion = reduced_motion
 clock.request_insert()
 return _apply()

func cancel(reduced_motion: bool = false) -> bool:
 if not _guard(): return false
 clock.reduced_motion = reduced_motion
 clock.request_return()
 return _apply()

func tick(delta: float, focused: bool = true) -> bool:
 if not _guard(): return false
 var previous_time: float = clock.time
 clock.tick(delta, focused)
 if _apply(): return true
 clock.time = previous_time
 return false

func teardown() -> void:
 # Only restore our surviving original node, never a replacement rig.
 if is_instance_valid(_cart) and is_instance_valid(_parent) and _cart.get_parent() == _parent:
  _cart.transform = _rest
 if _valid.is_valid() and bool(_valid.call()) and _opening.is_valid():
  _opening.call(0.0)
 _cart = null
 _parent = null
 _poses.clear()
 _opening = Callable()
 _valid = Callable()
 clock = Path.new()

func _guard() -> bool:
 if not is_instance_valid(_cart) or not is_instance_valid(_parent):
  return _fail("Canonical node disappeared; host must teardown before changing game.")
 if not _cart.is_inside_tree() or _cart.is_queued_for_deletion() or _cart.get_parent() != _parent or not _valid.is_valid() or not bool(_valid.call()):
  return _fail("Rig identity changed; refusing stale writes.")
 if not _parent.global_transform.is_equal_approx(_parent_world):
  return _fail("Host moved model parent during exclusive insertion; stop and restore before reframing.")
 return true

func _apply() -> bool:
 var p: Dictionary = clock.sample()
 if not bool(_opening.call(p.open)): return _fail("Packaging rig refused pose; cartridge not moved.")
 if clock.time == 0.0:
  _cart.transform = _rest
 elif clock.time == Path.TOTAL:
  _cart.global_transform = _poses[3]
 elif p.extract < 1.0:
  _cart.global_transform = _poses[0].interpolate_with(_poses[1], p.extract)
 elif p.align < 1.0:
  _cart.global_transform = _poses[1].interpolate_with(_poses[2], p.align)
 else:
  _cart.global_transform = _poses[2].interpolate_with(_poses[3], p.insert)
 return true

func _fail(message: String) -> bool:
 last_error = message
 return false
