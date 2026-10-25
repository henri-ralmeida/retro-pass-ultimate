extends RefCounted
## Factory callbacks for already-configured native packaging. No substitute mesh.
## Caller retains ownership and calls native restore on teardown as appropriate.
static func sms(dual_hinge: RefCounted, base_degrees: float, lid_degrees: float) -> Callable:
 return func(progress: float) -> bool:
  if not is_instance_valid(dual_hinge) or not dual_hinge.has_method("set_angles"): return false
  return bool(dual_hinge.set_angles(base_degrees * progress, lid_degrees * progress))

static func atari(exhibit: Node3D) -> Callable:
 return func(progress: float) -> bool:
  if not is_instance_valid(exhibit): return false
  var rests: Dictionary = exhibit.get("flap_rest")
  if rests.size() != 4: return false
  var keys := ["Top flap tuck hinge", "Carton main top flap hinge", "Dust flap hinge -1", "Dust flap hinge 1"]
  for key in keys:
   if not rests.has(key): return false
  for item in rests.values():
   if not is_instance_valid(item.node): return false
  # First release tuck, then main flap, then dust flaps; reverse closes in inverse order.
  var tuck := _ease(progress / 0.3)
  var main := _ease((progress - 0.2) / 0.5)
  var dust := _ease((progress - 0.65) / 0.35)
  for key in rests:
   var hinge: Node3D = rests[key].node
   hinge.transform = rests[key].transform
   match key:
    "Top flap tuck hinge": hinge.rotate_object_local(Vector3.RIGHT, deg_to_rad(70.0 * tuck))
    "Carton main top flap hinge": hinge.rotate_object_local(Vector3.RIGHT, deg_to_rad(-112.0 * main))
    "Dust flap hinge -1": hinge.rotate_object_local(Vector3.BACK, deg_to_rad(82.0 * dust))
    "Dust flap hinge 1": hinge.rotate_object_local(Vector3.BACK, deg_to_rad(-82.0 * dust))
    _: return false
  exhibit.set("carton_open", progress > 0.0)
  return true

static func _ease(value: float) -> float:
 var p := clampf(value, 0.0, 1.0)
 return p * p * (3.0 - 2.0 * p)
