extends RefCounted
## Deterministic, display-only presentation of an existing GameBox rig.
## The owner supplies time and focus; no Tween, processing, input, or signals.
## Inspecting/configuring starts CLOSED. Confirm opens before extracting the
## same cartridge; Back reverses that path without changing its parent/basis.
## Call teardown() before discarding this helper to restore the owned rig.

const OPEN_SECONDS := 0.72
const EXTRACT_SECONDS := 0.58
const TOTAL_SECONDS := OPEN_SECONDS + EXTRACT_SECONDS
const OPEN_DEGREES := 115.0
const EXTRACTION_OFFSET := Vector3(0.0, 0.13, 0.0)

var available: bool:
	get: return _rig_matches()
var progress: float:
	get: return _time / TOTAL_SECONDS if available else 0.0
var busy: bool:
	get: return available and _time != _target_time
var lid_angle: float:
	get: return OPEN_DEGREES * _ease(_time / OPEN_SECONDS) if available else 0.0
var extraction_progress: float:
	get: return _ease((_time - OPEN_SECONDS) / EXTRACT_SECONDS) if available else 0.0
var state: StringName:
	get:
		if not available: return &"unavailable"
		if _time == 0.0: return &"opening" if busy else &"closed"
		if _time == TOTAL_SECONDS: return &"returning" if busy else &"presented"
		if _target_time > _time:
			return &"opening" if _time < OPEN_SECONDS else &"extracting"
		return &"returning" if _time > OPEN_SECONDS else &"closing"

var _box: Node3D
var _lid: Node3D
var _cartridge: Node3D
var _lid_parent: Node
var _cartridge_parent: Node
var _closed_lid_pose := Transform3D.IDENTITY
var _inside_pose := Transform3D.IDENTITY
var _presented_pose := Transform3D.IDENTITY
var _time := 0.0
var _target_time := 0.0

func configure(box: Node3D) -> bool:
	teardown()
	if not is_instance_valid(box) or box.is_queued_for_deletion(): return false
	if not box.has_method("set_lid_angle"): return false
	for property in ["lid", "cartridge", "inside_pose", "opened", "cartridge_out"]:
		if not _has_property(box, property): return false
	var lid_value: Variant = box.get("lid")
	var cartridge_value: Variant = box.get("cartridge")
	var pose_value: Variant = box.get("inside_pose")
	if not lid_value is Node3D or not cartridge_value is Node3D: return false
	if not is_instance_valid(lid_value) or not is_instance_valid(cartridge_value): return false
	if lid_value == cartridge_value: return false
	if lid_value.is_queued_for_deletion() or cartridge_value.is_queued_for_deletion(): return false
	if not box.is_ancestor_of(lid_value) or not box.is_ancestor_of(cartridge_value): return false
	if not pose_value is Transform3D or not pose_value.is_finite(): return false
	if not lid_value.transform.is_finite(): return false
	_box = box
	_lid = lid_value
	_cartridge = cartridge_value
	_lid_parent = _lid.get_parent()
	_cartridge_parent = _cartridge.get_parent()
	_inside_pose = pose_value
	_presented_pose = _inside_pose
	_presented_pose.origin += EXTRACTION_OFFSET
	_box.set_lid_angle(0.0)
	_closed_lid_pose = _lid.transform
	reset()
	return true

func confirm(reduced_motion: bool = false) -> bool:
	return _request(TOTAL_SECONDS, reduced_motion)

func back(reduced_motion: bool = false) -> bool:
	return _request(0.0, reduced_motion)

func tick(delta: float, focused: bool = true) -> void:
	if not _ensure_rig(): return
	# Never consume time while inactive, nor accumulate it for focus return.
	if not focused or not is_finite(delta) or delta <= 0.0 or not busy: return
	_time = move_toward(_time, _target_time, delta)
	_apply_pose()

func reset() -> void:
	_time = 0.0
	_target_time = 0.0
	if _ensure_rig(): _restore_pose()

func teardown() -> void:
	_restore_pose()
	_box = null
	_lid = null
	_cartridge = null
	_lid_parent = null
	_cartridge_parent = null
	_time = 0.0
	_target_time = 0.0

func _request(target: float, reduced_motion: bool) -> bool:
	if not _ensure_rig(): return false
	_target_time = target
	if reduced_motion:
		_time = target
		_apply_pose()
	return true

func _apply_pose() -> void:
	# Apply each pose from the captured baseline, never incrementally. Exact
	# assignment at both endpoints prevents drift after any number of reversals.
	if _time == 0.0:
		_restore_pose()
		return
	_lid.transform = _closed_lid_pose
	_box.set_lid_angle(lid_angle)
	_cartridge.transform = _inside_pose
	var extraction := extraction_progress
	if extraction == 1.0:
		_cartridge.transform = _presented_pose
	elif extraction > 0.0:
		_cartridge.position = _inside_pose.origin + EXTRACTION_OFFSET * extraction
	_box.set("opened", true)
	_box.set("cartridge_out", extraction > 0.0)

func _restore_pose() -> void:
	# When GameBox.configure() replaces its children, never overwrite the NEW
	# rig or its flags with a stale snapshot. Surviving old parts may be restored.
	if is_instance_valid(_lid) and _lid.get_parent() == _lid_parent:
		_lid.transform = _closed_lid_pose
	if is_instance_valid(_cartridge) and _cartridge.get_parent() == _cartridge_parent:
		_cartridge.transform = _inside_pose
	if _rig_matches():
		_box.set("opened", false)
		_box.set("cartridge_out", false)

func _ensure_rig() -> bool:
	if _rig_matches(): return true
	teardown()
	return false

func _rig_matches() -> bool:
	if not is_instance_valid(_box) or not is_instance_valid(_lid) or not is_instance_valid(_cartridge): return false
	if _box.is_queued_for_deletion() or _lid.is_queued_for_deletion() or _cartridge.is_queued_for_deletion(): return false
	return _box.get("lid") == _lid and _box.get("cartridge") == _cartridge \
		and _lid.get_parent() == _lid_parent and _cartridge.get_parent() == _cartridge_parent

static func _ease(value: float) -> float:
	var bounded := clampf(value, 0.0, 1.0)
	return bounded * bounded * (3.0 - 2.0 * bounded)

static func _has_property(object: Object, name: String) -> bool:
	for property in object.get_property_list():
		if property.name == name: return true
	return false
