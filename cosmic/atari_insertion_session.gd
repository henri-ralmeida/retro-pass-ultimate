extends RefCounted
## Adapter for a hidden, freshly-laid-out one-world Atari stage. No HOME changes.
## Source hashes bind the sampled geometry proof to the exact native meshes.
const Calibration = preload("res://cosmic/atari_insertion_calibration.gd")
const Rig = preload("res://cosmic/insertion_rig.gd")
const Packaging = preload("res://cosmic/insertion_packaging.gd")
var rig = Rig.new()
var last_error := ""
var _exhibit: Node3D
var _cart: Node3D
var _original := Transform3D.IDENTITY
var _id := 0
var _box_pose := Transform3D.IDENTITY
var _console_pose := Transform3D.IDENTITY
func prepare_hidden(exhibit: Node3D) -> bool:
 teardown()
 if not is_instance_valid(exhibit) or not exhibit.is_inside_tree() or exhibit.is_visible_in_tree():
  return _fail("Prepare only while stage is hidden, before revealing it; no setup teleport.")
 if exhibit.carton_open or exhibit.cartridge_seated:
  return _fail("Fresh closed unseated source layout required.")
 for key in Calibration.SOURCE_HASHES:
  if not exhibit.asset_roots.has(key): return _fail("Native asset missing: " + key)
  var root: Variant = exhibit.asset_roots[key]
  if not is_instance_valid(root): return _fail("Native asset disappeared: " + key)
  if root.get_child_count() != 1 or root.get_child(0).get_meta("source_sha256", "") != Calibration.SOURCE_HASHES[key]:
   return _fail("Calibrated source hash differs: " + key)
 # Calibration is in exhibit-local space and assumes original relative layout.
 if not exhibit.asset_roots.box.transform.is_equal_approx(Transform3D(Basis(Vector3.UP,deg_to_rad(12.0)),Vector3(-0.25,0,-0.06))) or not exhibit.asset_roots.console.transform.is_equal_approx(Transform3D(Basis.IDENTITY,Vector3(0.08,0,-0.10))):
  return _fail("Source layout moved; recalibrate instead of guessing.")
 _exhibit = exhibit
 _cart = exhibit.canonical_cartridge
 if not is_instance_valid(_cart): return _fail("Canonical cartridge missing.")
 _id = _cart.get_instance_id()
 _original = _cart.transform
 _box_pose = exhibit.asset_roots.box.transform
 _console_pose = exhibit.asset_roots.console.transform
 var poses: Array[Transform3D] = []
 for key in ["inside", "extracted", "approach", "seated"]:
  var entry: Dictionary = Calibration.WAYPOINTS[key]
  var rows: Array = entry.basis_rows
  poses.append(exhibit.global_transform * Transform3D(Basis(_vec(rows[0]),_vec(rows[1]),_vec(rows[2])).transposed(),_vec(entry.origin)))
 _cart.global_transform = poses[0]
 var guard := func() -> bool:
  if not is_instance_valid(_exhibit) or not is_instance_valid(_cart): return false
  var box_root: Variant = _exhibit.asset_roots.get("box")
  var console_root: Variant = _exhibit.asset_roots.get("console")
  return is_instance_valid(box_root) and is_instance_valid(console_root) and _exhibit.canonical_cartridge == _cart and _cart.get_instance_id() == _id and box_root.transform.is_equal_approx(_box_pose) and console_root.transform.is_equal_approx(_console_pose)
 if not rig.configure(_cart,poses,Packaging.atari(exhibit),guard,true):
  var reason: String = rig.last_error
  teardown()
  return _fail(reason)
 last_error = ""
 return true
func insert(reduced: bool = false) -> bool:
 if not rig.insert(reduced): return _fail(rig.last_error)
 if is_instance_valid(_exhibit): _exhibit.cartridge_seated = rig.clock.state() == "seated"
 return true
func cancel(reduced: bool = false) -> bool:
 if not rig.cancel(reduced): return _fail(rig.last_error)
 if is_instance_valid(_exhibit): _exhibit.cartridge_seated = false
 return true
func tick(delta: float, focused: bool = true) -> bool:
 if not rig.tick(delta,focused): return _fail(rig.last_error)
 if is_instance_valid(_exhibit): _exhibit.cartridge_seated = rig.clock.state() == "seated"
 return true
func teardown() -> void:
 rig.teardown()
 if is_instance_valid(_exhibit) and is_instance_valid(_cart) and _exhibit.canonical_cartridge == _cart:
  _cart.transform = _original
  _exhibit.cartridge_seated = false
 _exhibit = null
 _cart = null
func _fail(reason: String) -> bool:
 last_error = reason
 return false
static func _vec(a: Array) -> Vector3:
 return Vector3(float(a[0]),float(a[1]),float(a[2]))
