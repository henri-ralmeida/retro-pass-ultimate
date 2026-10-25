extends SceneTree
## Headless deterministic rig tests, NOT visual/physical-controller QA.
## Run: godot --headless --path . --script cosmic/test_box_presentation.gd

const Presentation := preload("res://cosmic/box_presentation.gd")
var failures: Array[String] = []
var assertions := 0
var selections := 0

class FakeRig extends Node3D:
	signal selected
	var lid := Node3D.new()
	var cartridge := Node3D.new()
	var contents := Node3D.new()
	var inside_pose := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.0135, 0.036))
	var opened := false
	var cartridge_out := false
	var last_angle := 0.0

	func _init() -> void:
		lid.name = "ExistingLid"
		lid.position = Vector3(-0.0673, 0.023, 0.0)
		cartridge.name = "SameCartridge"
		cartridge.transform = inside_pose
		contents.name = "ExistingInteriorContents"
		contents.position = Vector3(0.023, 0.0, -0.05)
		add_child(lid)
		add_child(cartridge)
		add_child(contents)

	func set_lid_angle(angle: float) -> void:
		last_angle = clampf(angle, 0.0, 115.0)
		lid.rotation.z = deg_to_rad(last_angle)

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		push_error(message)

func _rig() -> FakeRig:
	var rig := FakeRig.new()
	rig.selected.connect(func(): selections += 1)
	root.add_child(rig)
	return rig

func _check_closed(presentation: RefCounted, rig: Node3D, closed_lid: Transform3D, label: String) -> void:
	check(presentation.state == &"closed" and not presentation.busy and presentation.progress == 0.0, label + ": closed state and exact progress")
	check(rig.lid.transform == closed_lid, label + ": exact closed lid transform")
	check(rig.cartridge.transform == rig.inside_pose, label + ": exact original cartridge inside pose")
	check(not rig.opened and not rig.cartridge_out, label + ": exact legacy flags")

func _check_bounded(presentation: RefCounted, rig: Node3D, baseline_lid: Transform3D, label: String) -> void:
	check(presentation.progress >= 0.0 and presentation.progress <= 1.0, label + ": progress bounded")
	check(presentation.lid_angle >= 0.0 and presentation.lid_angle <= 115.0, label + ": angle bounded")
	check(presentation.extraction_progress >= 0.0 and presentation.extraction_progress <= 1.0, label + ": extraction bounded")
	check(rig.lid.transform.is_finite() and rig.cartridge.transform.is_finite(), label + ": finite transforms")
	check(rig.lid.position == baseline_lid.origin, label + ": original hinge pivot does not drift")
	check(rig.cartridge.basis == rig.inside_pose.basis, label + ": original cartridge basis retained")
	var expected_origin: Vector3 = rig.inside_pose.origin + Presentation.EXTRACTION_OFFSET * presentation.extraction_progress
	check(rig.cartridge.position.is_equal_approx(expected_origin), label + ": bounded cartridge path")
	check(presentation.extraction_progress == 0.0 or presentation.lid_angle == 115.0, label + ": cartridge never moves through a partly closed lid")
	check(is_equal_approx(rad_to_deg(rig.lid.rotation.z), presentation.lid_angle), label + ": actual pose matches reported angle")

func _test_sequence() -> void:
	var rig := _rig()
	var presentation := Presentation.new()
	check(presentation.get_class() == "RefCounted", "Helper cannot autonomously process or receive input")
	check(not presentation.has_method("_process") and not presentation.has_method("_input"), "No autonomous clock or selection-input handler")
	for entry in presentation.get_signal_list():
		check(not str(entry.name) in ["selected", "selection", "system_selected", "game_selected", "launch"], "No selection/launch signal: " + str(entry.name))
	check(presentation.configure(rig), "Valid rig configures")
	var closed_lid := rig.lid.transform
	var original_box := rig.transform
	var contents_pose := rig.contents.transform
	var original_cartridge := rig.cartridge
	var original_parent := rig.cartridge.get_parent()
	var original_children := rig.get_child_count()
	_check_closed(presentation, rig, closed_lid, "Inspection starts closed")
	check(presentation.confirm() and presentation.state == &"opening" and presentation.busy, "Confirm requests opening without immediate jump")
	check(presentation.progress == 0.0 and rig.cartridge.transform == rig.inside_pose, "Confirm alone consumes no time")
	# Invert smoothstep so every quarter-degree angle from 0 through 115 is
	# visited through the PUBLIC clock rather than injecting internal state.
	for sample in range(461):
		presentation.reset()
		presentation.confirm()
		var fraction := float(sample) / 460.0
		var phase := 0.5 - sin(asin(1.0 - 2.0 * fraction) / 3.0)
		presentation.tick(Presentation.OPEN_SECONDS * phase)
		check(absf(presentation.lid_angle - float(sample) * 0.25) < 0.0001, "Quarter-degree opening sample " + str(sample))
		_check_bounded(presentation, rig, closed_lid, "Opening sample " + str(sample))
		check(rig.cartridge.transform == rig.inside_pose, "Cartridge remains inside throughout lid opening " + str(sample))
	check(presentation.state == &"extracting", "Fully open lid transitions to extraction phase")
	check(presentation.extraction_progress == 0.0, "Lid reaches full opening before extraction starts")
	var previous_extraction := 0.0
	for sample in range(120):
		presentation.tick(Presentation.EXTRACT_SECONDS / 120.0)
		_check_bounded(presentation, rig, closed_lid, "Extraction sample " + str(sample))
		check(presentation.extraction_progress >= previous_extraction, "Extraction remains monotonic " + str(sample))
		previous_extraction = presentation.extraction_progress
	presentation.tick(0.001)
	var presented_pose := rig.inside_pose
	presented_pose.origin += Presentation.EXTRACTION_OFFSET
	check(presentation.state == &"presented" and not presentation.busy and presentation.progress == 1.0, "Presentation reaches exact stable endpoint")
	check(rig.cartridge.transform == presented_pose, "Presentation uses exact deterministic target transform")
	check(rig.cartridge == original_cartridge and rig.cartridge.get_parent() == original_parent, "Same original cartridge and parent retained")
	check(rig.get_child_count() == original_children and rig.contents.transform == contents_pose, "No manufactured interior/manual or changed existing contents")
	check(rig.transform == original_box, "Presentation never owns box rotation, camera, or layout")
	check(presentation.back() and presentation.state == &"returning", "Back requests cartridge return first")
	previous_extraction = 1.0
	for sample in range(120):
		presentation.tick(Presentation.EXTRACT_SECONDS / 120.0)
		_check_bounded(presentation, rig, closed_lid, "Return sample " + str(sample))
		check(presentation.extraction_progress <= previous_extraction, "Cartridge return remains monotonic " + str(sample))
		previous_extraction = presentation.extraction_progress
	presentation.tick(0.001)
	check(presentation.state == &"closing" and rig.cartridge.transform == rig.inside_pose, "Cartridge is exactly inside before lid closes")
	for sample in range(120):
		presentation.tick(Presentation.OPEN_SECONDS / 120.0)
		_check_bounded(presentation, rig, closed_lid, "Closing sample " + str(sample))
	presentation.tick(0.001)
	_check_closed(presentation, rig, closed_lid, "Back completion")
	presentation.teardown()
	check(presentation.state == &"unavailable" and not presentation.available, "Teardown releases rig ownership")
	rig.free()

func _test_interruptions() -> void:
	var rig := _rig()
	var presentation := Presentation.new()
	presentation.configure(rig)
	var closed_lid := rig.lid.transform
	for time in [0.02, 0.19, Presentation.OPEN_SECONDS, 0.83, 1.12, 1.29]:
		presentation.reset()
		presentation.confirm()
		presentation.tick(time)
		var progress_before := presentation.progress
		var lid_before := rig.lid.transform
		var cartridge_before := rig.cartridge.transform
		for repeat_index in range(16):
			presentation.confirm()
		check(presentation.progress == progress_before and rig.lid.transform == lid_before and rig.cartridge.transform == cartridge_before, "Repeated confirm cannot restart or jump at " + str(time))
		presentation.back()
		check(presentation.progress == progress_before and rig.lid.transform == lid_before and rig.cartridge.transform == cartridge_before, "Interrupted Back preserves current pose at " + str(time))
		for repeat_index in range(16): presentation.back()
		presentation.tick(0.01)
		check(presentation.progress < progress_before, "Back advances toward closed from interruption " + str(time))
		progress_before = presentation.progress
		lid_before = rig.lid.transform
		cartridge_before = rig.cartridge.transform
		presentation.confirm()
		check(presentation.progress == progress_before and rig.lid.transform == lid_before and rig.cartridge.transform == cartridge_before, "Confirm reverses return without snapping at " + str(time))
		presentation.tick(0.01)
		check(presentation.progress > progress_before, "Reconfirmed presentation advances outward at " + str(time))
		_check_bounded(presentation, rig, closed_lid, "Interrupted sequence " + str(time))
		presentation.back()
		presentation.tick(100.0)
		_check_closed(presentation, rig, closed_lid, "Interrupted sequence closed " + str(time))
	for cycle in range(300):
		presentation.confirm()
		presentation.tick(float(cycle % 39) * 0.037)
		presentation.back()
		presentation.tick(0.021)
		presentation.confirm()
		presentation.tick(0.023)
		_check_bounded(presentation, rig, closed_lid, "Repeated reversal " + str(cycle))
		presentation.back()
		presentation.tick(100.0)
		_check_closed(presentation, rig, closed_lid, "Exact cycle restoration " + str(cycle))
	presentation.teardown()
	rig.free()

func _test_pause_and_reduced_motion() -> void:
	var rig := _rig()
	var presentation := Presentation.new()
	presentation.configure(rig)
	var closed_lid := rig.lid.transform
	for time in [0.21, 0.87, 1.17]:
		presentation.reset()
		presentation.confirm()
		presentation.tick(time)
		var saved_progress := presentation.progress
		var saved_lid := rig.lid.transform
		var saved_cartridge := rig.cartridge.transform
		for invalid_delta in [0.0, -1.0, NAN, INF, -INF]: presentation.tick(invalid_delta)
		for pause_step in range(30): presentation.tick(300.0, false)
		check(presentation.progress == saved_progress and rig.lid.transform == saved_lid and rig.cartridge.transform == saved_cartridge, "Focus pause and invalid time never alter pose at " + str(time))
		presentation.tick(0.01, true)
		check(is_equal_approx(presentation.progress, saved_progress + 0.01 / Presentation.TOTAL_SECONDS), "Focus return consumes only current delta at " + str(time))
		presentation.back()
		saved_progress = presentation.progress
		presentation.tick(100.0, false)
		check(presentation.progress == saved_progress and presentation.busy, "Focus pause also freezes reverse animation at " + str(time))
		presentation.confirm(true)
		check(presentation.state == &"presented" and presentation.progress == 1.0 and not presentation.busy, "Reduced-motion confirm immediately completes interrupted transition")
		var presented_pose := rig.cartridge.transform
		presentation.confirm(true)
		check(rig.cartridge.transform == presented_pose and not presentation.busy, "Repeated reduced-motion confirm is idempotent")
		presentation.back(true)
		_check_closed(presentation, rig, closed_lid, "Reduced-motion Back")
		presentation.back(true)
		_check_closed(presentation, rig, closed_lid, "Repeated reduced-motion Back")
	# Caller delta partition does not change the corresponding pose.
	presentation.confirm()
	presentation.tick(0.93)
	var direct_lid := rig.lid.transform
	var direct_cartridge := rig.cartridge.transform
	presentation.reset()
	presentation.confirm()
	for step in range(93): presentation.tick(0.01)
	check(rig.lid.transform.is_equal_approx(direct_lid) and rig.cartridge.transform.is_equal_approx(direct_cartridge), "Deterministic timeline is independent of frame partition to float precision")
	presentation.reset()
	_check_closed(presentation, rig, closed_lid, "Reset during transition")
	presentation.confirm()
	presentation.tick(1000000.0)
	check(presentation.progress == 1.0 and not presentation.busy, "Huge finite delta clamps to endpoint")
	presentation.teardown()
	check(rig.lid.transform == closed_lid and rig.cartridge.transform == rig.inside_pose and not rig.opened and not rig.cartridge_out, "Teardown restores both parts and flags exactly")
	rig.free()

func _test_lifecycle_and_missing_rigs() -> void:
	var presentation := Presentation.new()
	check(not presentation.configure(null), "Null rig is unavailable")
	var empty := Node3D.new()
	check(not presentation.configure(empty), "Nonarticulated rig is unavailable without missing-property errors")
	empty.free()
	check(not presentation.confirm() and not presentation.back(true), "Unavailable rig rejects direction requests safely")
	presentation.tick(100.0)
	presentation.reset()
	presentation.teardown()
	check(presentation.state == &"unavailable" and presentation.progress == 0.0 and not presentation.busy, "Unavailable operations remain inert")
	var invalid := _rig()
	invalid.inside_pose.origin.x = NAN
	check(not presentation.configure(invalid), "Nonfinite inside pose cannot enter animation")
	invalid.free()
	var first := _rig()
	var second := _rig()
	presentation.configure(first)
	var first_lid := first.lid.transform
	presentation.confirm(true)
	check(presentation.configure(second), "Configure can change the owned box")
	check(first.lid.transform == first_lid and first.cartridge.transform == first.inside_pose and not first.opened and not first.cartridge_out, "Configure restores previous box exactly before switching")
	var second_lid := second.lid.transform
	_check_closed(presentation, second, second_lid, "Replacement begins closed")
	presentation.confirm()
	presentation.tick(0.91)
	check(presentation.configure(second), "Reconfiguring same box is supported mid-transition")
	_check_closed(presentation, second, second_lid, "Same-box configure restores exact baseline")
	presentation.confirm(true)
	check(not presentation.configure(null), "Invalid replacement releases old rig")
	check(second.lid.transform == second_lid and second.cartridge.transform == second.inside_pose and not second.opened and not second.cartridge_out, "Even invalid configure restores old box exactly")
	presentation.configure(second)
	presentation.confirm()
	presentation.tick(0.93)
	var replaced_lid := second.lid
	var replaced_cartridge := second.cartridge
	second.lid = Node3D.new()
	second.cartridge = Node3D.new()
	second.add_child(second.lid)
	second.add_child(second.cartridge)
	second.lid.position = Vector3(0.12, 0.34, 0.56)
	second.cartridge.position = Vector3(0.65, 0.43, 0.21)
	var new_lid_pose := second.lid.transform
	var new_cartridge_pose := second.cartridge.transform
	second.opened = true
	second.cartridge_out = true
	check(not presentation.available, "Externally replaced rig invalidates old ownership immediately")
	presentation.tick(1.0)
	check(presentation.state == &"unavailable" and not presentation.busy, "Replacement during transition safely releases stale ownership")
	check(second.lid.transform == new_lid_pose and second.cartridge.transform == new_cartridge_pose and second.opened and second.cartridge_out, "Stale helper never writes transforms or flags to new rig")
	check(replaced_lid.transform == second_lid and replaced_cartridge.transform == second.inside_pose, "Surviving original rig parts are restored before release")
	first.free()
	second.free()
	var freed := _rig()
	presentation.configure(freed)
	presentation.confirm()
	presentation.tick(0.3)
	freed.free()
	check(not presentation.available, "Freed owner invalidates availability immediately")
	presentation.tick(1.0)
	check(not presentation.confirm() and not presentation.back() and not presentation.busy, "Freed owner cannot leave stale running animation")
	presentation.teardown()

func _test_original_rig() -> void:
	var box = load("res://cosmic/game_box.gd").new()
	box.configure({"id": "presentation_regression", "title": "Presentation regression"})
	root.add_child(box)
	var presentation := Presentation.new()
	check(presentation.configure(box), "Actual approved GameBox rig configures")
	if not presentation.available:
		box.free()
		return
	var closed_lid: Transform3D = box.lid.transform
	var original_cartridge: Node3D = box.cartridge
	var original_parent := original_cartridge.get_parent()
	var original_meshes: Array[Node] = box.find_children("*", "MeshInstance3D", true, false)
	var model_pose: Transform3D = box.original_model.transform
	_check_closed(presentation, box, closed_lid, "Approved rig begins closed")
	for sample in range(261):
		presentation.confirm()
		presentation.tick(0.005)
		_check_bounded(presentation, box, closed_lid, "Approved model forward sample " + str(sample))
	check(presentation.state == &"presented", "Approved model reaches presentation")
	check(box.cartridge == original_cartridge and box.cartridge.get_parent() == original_parent, "Approved model presents original cartridge, never a replacement")
	check(box.find_children("*", "MeshInstance3D", true, false) == original_meshes, "Approved geometry, contents, and mesh identities retained")
	check(box.original_model.transform == model_pose, "Approved model root/framing untouched")
	for sample in range(261):
		presentation.back()
		presentation.tick(0.005)
		_check_bounded(presentation, box, closed_lid, "Approved model reverse sample " + str(sample))
	_check_closed(presentation, box, closed_lid, "Approved model closes exactly")
	presentation.confirm(true)
	box.configure({"id": "replacement_regression", "title": "Replacement regression"})
	var rebuilt_lid: Transform3D = box.lid.transform
	var rebuilt_cartridge: Transform3D = box.cartridge.transform
	presentation.tick(1.0)
	check(not presentation.available and not box.opened and not box.cartridge_out, "Actual GameBox.configure invalidates old animation without changing new flags")
	check(box.lid.transform == rebuilt_lid and box.cartridge.transform == rebuilt_cartridge, "Actual reconfigured geometry never receives stale poses")
	check(presentation.configure(box), "Rebuilt GameBox can be adopted cleanly")
	_check_closed(presentation, box, rebuilt_lid, "Rebuilt approved model starts closed")
	presentation.teardown()
	box.free()

func run() -> void:
	_test_sequence()
	_test_interruptions()
	_test_pause_and_reduced_motion()
	_test_lifecycle_and_missing_rigs()
	_test_original_rig()
	check(selections == 0, "All presentation paths leave selection signals untouched")
	print("BOX_PRESENTATION_TESTS ", JSON.stringify({
		"assertions": assertions,
		"passed": failures.is_empty(),
		"failures": failures,
		"lid_quarter_degree_samples": 461,
		"reversal_cycles": 300,
		"engine": Engine.get_version_info().string,
		"mode": "headless deterministic rig behavior; NOT visual or physical-controller QA"
	}))
	quit(0 if failures.is_empty() else 1)
