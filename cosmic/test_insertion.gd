extends SceneTree
const Rig = preload("res://cosmic/insertion_rig.gd")
const Selection = preload("res://cosmic/insertion_selection.gd")
const Path = preload("res://cosmic/insertion_path.gd")
var count := 0
var failures := 0
var opening := 0.0
var valid := true
func check(condition: bool, label: String) -> void:
 count += 1
 if not condition:
  failures += 1
  printerr("FAIL: " + label)
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var rng := RandomNumberGenerator.new()
 rng.seed = 12
 var entries: Array[Dictionary] = [{"system_id":"sms", "game_id":"missing"},
  {"system_id":"atari2600", "game_id":"explicit", "matching_media_present":true,
  "insertion_geometry_validated":true}]
 check(Selection.choose([], rng).is_empty(), "no fabricated random choice")
 for i in 20:
  check(Selection.choose(entries, rng).game_id == "explicit", "random excludes unavailable media")
 var native_entries: Array[Dictionary] = [{"system_id":"sega_master_system", "variant_id":"sms_us", "game_id":"catalog_confirmed", "matching_media_present":true,"insertion_geometry_validated":true,"rom_inventory_present":true}]
 check(Selection.choose(native_entries,rng).variant_id == "sms_us", "native system and variant IDs preserved; no ROM file check")
 var parent := Node3D.new()
 root.add_child(parent)
 parent.transform = Transform3D(Basis(Vector3.UP, 0.4), Vector3(3, 1, 2))
 var cart := Node3D.new()
 parent.add_child(cart)
 var original := cart.transform
 var identity := cart.get_instance_id()
 var start := cart.global_transform
 var extracted := start.translated(Vector3(0, 0.2, 0))
 var seat := Transform3D(start.basis, start.origin + Vector3(0.4, 0, 0))
 var approach := seat.translated(seat.basis.y * 0.2)
 var poses: Array[Transform3D] = [start, extracted, approach, seat]
 var setter := func(p: float) -> bool:
  opening = p
  return true
 var guard := func() -> bool: return valid
 var rig := Rig.new()
 check(not rig.configure(cart, poses, setter, guard), "geometry gate defaults closed")
 check(rig.configure(cart, poses, setter, guard, true), "rotated translated parent accepted")
 check(cart.transform == original, "configure no teleport")
 rig.insert()
 rig.tick(0.4)
 check(cart.transform.is_equal_approx(original) and opening > 0 and opening < 1, "opening before extraction")
 var paused: float = rig.clock.time
 rig.tick(4.0, false)
 rig.tick(NAN)
 rig.tick(-1)
 check(rig.clock.time == paused, "focus/NaN/negative time frozen")
 rig.tick(0.6)
 check(opening == 1.0 and cart.global_position.y > start.origin.y, "extract only after opening")
 var before_reverse := cart.global_transform
 rig.cancel()
 check(cart.global_transform.is_equal_approx(before_reverse), "reverse request no jump")
 rig.tick(10)
 check(cart.transform == original and opening == 0.0, "cancel restores exact baseline")
 for cycle in 100:
  rig.insert()
  for frame in 180: rig.tick(1.0 / 60.0)
  check(cart.global_transform.is_equal_approx(seat), "seat cycle %d" % cycle)
  check(cart.get_instance_id() == identity and cart.get_parent() == parent, "same node and parent %d" % cycle)
  rig.cancel()
  for frame in 180: rig.tick(1.0 / 60.0)
  check(cart.transform == original, "no drift %d" % cycle)
 rig.insert(true)
 check(cart.global_transform.is_equal_approx(seat), "reduced motion endpoint")
 rig.cancel(true)
 check(cart.transform == original, "reduced return exact")
 rig.insert()
 rig.tick(2.5)
 var entry := cart.global_transform
 rig.tick(0.1)
 check(cart.global_transform.basis.is_equal_approx(entry.basis), "no rotation within slot")
 check((cart.global_position-entry.origin).cross(seat.basis.y).length() < 0.00001, "axial slot travel")
 valid = false
 var stale := cart.transform
 check(not rig.tick(1) and cart.transform == stale, "stale identity rejects write")
 valid = true
 rig.teardown()
 check(cart.transform == original, "teardown exact")
 var wrong := poses.duplicate()
 wrong[2] = approach.rotated(Vector3.UP, 0.3)
 check(not rig.configure(cart, wrong, setter, guard, true), "reject rotation during insertion")
 check(rig.configure(cart, poses, setter, guard, true), "reconfigure repeat")
 parent.position.x += 1
 check(not rig.tick(1), "detect host parent movement")
 rig.teardown()
 parent.free()
 print("Insertion isolated: %d checks, %d failures" % [count, failures])
 quit(0 if failures == 0 else 1)
