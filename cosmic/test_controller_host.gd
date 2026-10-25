extends SceneTree
## Synthetic host/picker regressions. Prepared for the complete project checkout;
## NOT executed during isolated hook preparation. No emulator or personal media.
const Picker = preload("res://cosmic/controller_home_picker.gd")
const Snapshot = preload("res://cosmic/controller_input_snapshot.gd")
const Exhibit = preload("res://cosmic/exhibit_scene.gd")

class FakePanel:
 extends Control
 var opened := true
 var route_result := false
 var routed := 0
 var input_snapshot = Snapshot.new()
 func _init() -> void: input_snapshot.poll_physical = false
 func release_inputs_neutral() -> bool: return input_snapshot.neutral(27, true)
 func is_open() -> bool: return opened
 func route_input(_event: InputEvent) -> bool:
  routed += 1
  return route_result

class LibrarySpy:
 extends Node
 var events := 0
 func handle_event(_event: InputEvent) -> bool:
  events += 1
  return true

class TooltipHostProbe:
 extends "res://cosmic/main.gd"
 func _ready() -> void: pass

class HostProbe:
 extends "res://cosmic/main.gd"
 var observed := 0
 var picked_port := 0
 var pick_allowed := true
 var opened_ports: Array[int] = []
 var focus_restorations := 0
 func _ready() -> void: pass
 func _observe_input_device(_event: InputEvent) -> void: observed += 1
 func _pick_home_controller(_point: Vector2) -> int: return picked_port if pick_allowed else -1
 func _open_controller_settings(port: int, _return_focus: Control = null, _opening_event: InputEvent = null) -> void: opened_ports.append(port)
 func _set_background_blocked(value: bool) -> void: controller_background_blocked = value
 func _restore_controller_focus() -> void:
  focus_restorations += 1
  auto_history_armed = false
  reset_dwell()

var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
 run.call_deferred()

func check(value: bool, message: String) -> void:
 assertions += 1
 if not value:
  failures.append(message)
  push_error(message)

func mouse(position: Vector2, pressed: bool, double_click := false, index := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
 var event := InputEventMouseButton.new()
 event.position = position
 event.button_index = index
 event.pressed = pressed
 event.double_click = double_click
 return event

func motion(position: Vector2) -> InputEventMouseMotion:
 var event := InputEventMouseMotion.new()
 event.position = position
 return event

func make_host() -> HostProbe:
 var host := HostProbe.new()
 root.add_child(host)
 host.set_process(false)
 host.set_process_input(false)
 return host

func test_routing_and_release() -> void:
 var host := make_host()
 var panel := FakePanel.new()
 host.add_child(panel)
 host.controller_panel = panel
 var library := LibrarySpy.new()
 host.add_child(library)
 host.library_view = library
 host.library_state = "library"
 var key := InputEventKey.new()
 key.keycode = KEY_X
 key.physical_keycode = KEY_X
 key.pressed = true
 host._input(key)
 check(panel.routed == 1 and host.observed == 0 and library.events == 0,"Modal false permits its GUI but never device switching or library routing")
 panel.route_result = true
 host._input(key)
 check(panel.routed == 2 and host.observed == 0 and library.events == 0,"Modal consumed capture remains exclusive")
 host.elapsed = 12.0
 host._process(0.5)
 check(host.elapsed == 12.0,"Modal freezes HOME/background processing")
 host.dwell_elapsed = 7.9
 host._advance_dwell(1.0)
 check(host.dwell_elapsed == 0.0 and not host.history_open,"Modal cancels, rather than completes, dwell")
 host.confirm_selection("synthetic")
 check(host.selection_count == 0,"Direct selection callbacks cannot activate behind modal")
 panel.opened = false
 host.controller_background_blocked = true
 host._controller_panel_closed(0)
 var drift := InputEventJoypadMotion.new()
 drift.device = 99
 drift.axis = JOY_AXIS_LEFT_X
 drift.axis_value = 0.8
 panel.input_snapshot.observe(drift)
 check(host._controller_inputs_neutral(), "Other controller drift cannot block the host release gate")
 drift.device = 27
 panel.input_snapshot.observe(drift)
 check(not host._controller_inputs_neutral(), "Pinned controller still must release before returning")
 drift.axis_value = 0.0
 panel.input_snapshot.observe(drift)
 check(host._controller_inputs_neutral(), "Pinned neutral permits return despite unrelated drift")
 host._input(mouse(Vector2.ZERO,false))
 check(host.observed == 0 and library.events == 0,"Closing-release event cannot reach background")
 host._advance_controller_release_gate(0.14,true)
 check(host.controller_release_gate,"Gate requires continuous 150 ms neutrality")
 host._advance_controller_release_gate(1.0,false)
 check(host.controller_release_elapsed == 0.0,"Held input resets gate")
 host._advance_controller_release_gate(0.14,true)
 host._advance_controller_release_gate(0.02,true)
 check(not host.controller_release_gate and not host.controller_background_blocked,"Neutral gate eventually releases background")
 check(host.focus_restorations == 1 and host.cooldown >= 0.4,"Focus restores once with selection cooldown")
 host.free()

func test_click_gestures() -> void:
 var host := make_host()
 var start := Vector2(20,20)
 check(host._controller_click_input(mouse(start,true)),"Controller press is consumed before transparent console button")
 host._controller_click_input(motion(start+Vector2(6,0)))
 host._controller_click_input(mouse(start+Vector2(6,0),false))
 check(host.opened_ports == [0],"Click at 6 px threshold opens its player")
 host.controller_click_active = true
 host.dwell_elapsed = 7.9
 host._advance_dwell(1.0)
 check(host.dwell_elapsed == 0.0,"Held controller click cannot accumulate HOME history dwell")
 host.controller_click_active = false
 host._controller_click_input(mouse(start,true))
 host._controller_click_input(motion(start+Vector2(7,0)))
 host._controller_click_input(motion(start))
 host._controller_click_input(mouse(start,false))
 check(host.opened_ports == [0],"Dragging out and back cannot become a short click")
 host._controller_click_input(mouse(start,true))
 host.picked_port = 1
 host._controller_click_input(mouse(start,false))
 check(host.opened_ports == [0],"Release over a different player cannot open either")
 host._controller_click_input(mouse(start,true,true))
 host._controller_click_input(mouse(start,false))
 check(host.opened_ports == [0],"Double-click press cannot reopen configuration")
 host._controller_click_input(mouse(start,true))
 host._controller_click_input(mouse(start,true,false,MOUSE_BUTTON_WHEEL_UP))
 host._controller_click_input(mouse(start,false))
 check(host.opened_ports == [0],"Wheel/zoom cancels pending controller click")
 host.pick_allowed = false
 check(not host._controller_click_input(mouse(start,true)),"Disabled picker does not claim arbitrary HOME space")
 host.free()

func test_home_eligibility() -> void:
 var host := make_host()
 host.settings_panel = PanelContainer.new()
 host.add_child(host.settings_panel)
 host.settings_panel.hide()
 host.exhibit = Node3D.new()
 host.add_child(host.exhibit)
 host.camera = Camera3D.new()
 host.add_child(host.camera)
 check(host._controller_home_eligible(),"Normal HOME permits geometric controller picking")
 for property in ["inspect_mode","inspection_dragging","history_open","transition_busy"]:
  host.set(property,true)
  check(not host._controller_home_eligible(),"Controller click blocked by "+property)
  host.set(property,false)
 host.history_blend = 0.01
 check(not host._controller_home_eligible(),"Closing history transition remains blocked")
 host.history_blend = 0.0
 host.settings_panel.show()
 check(not host._controller_home_eligible(),"Interface settings overlay blocks HOME picker")
 host.settings_panel.hide()
 host.library_state = "library"
 check(not host._controller_home_eligible(),"Library cannot invoke HOME controller click")
 host.library_state = "system"
 host.application_focused = false
 check(not host._controller_home_eligible(),"Unfocused application cannot open controller modal")
 host.free()

func triangle() -> MeshInstance3D:
 var mesh := MeshInstance3D.new()
 var arrays: Array = []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1,-1,0),Vector3(1,-1,0),Vector3(0,1,0)])
 var geometry := ArrayMesh.new()
 geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 mesh.mesh = geometry
 return mesh

func test_triangle_occlusion() -> void:
 var picker := Picker.new()
 var world := Node3D.new()
 root.add_child(world)
 var pad := triangle()
 world.add_child(pad)
 var source_mesh := pad.mesh
 var source_faces := pad.mesh.get_faces()
 var hit: Dictionary = picker.nearest_hit([world],Vector3(0,0,2),Vector3.FORWARD)
 check(hit.get("mesh") == pad and is_equal_approx(hit.get("distance",0.0),2.0),"Triangle hit returns actual nearest surface")
 check(picker.nearest_hit([world],Vector3(0.9,0.9,2),Vector3.FORWARD).is_empty(),"Empty part of mesh AABB cannot select a controller")
 var occluder := triangle()
 occluder.position.z = 1.0
 world.add_child(occluder)
 check(picker.nearest_hit([world],Vector3(0,0,2),Vector3.FORWARD).get("mesh") == occluder,"Closer console/cable geometry occludes controller")
 occluder.hide()
 check(picker.nearest_hit([world],Vector3(0,0,2),Vector3.FORWARD).get("mesh") == pad,"Hidden surfaces do not occlude")
 occluder.show()
 occluder.layers = 0
 check(picker.nearest_hit([world],Vector3(0,0,2),Vector3.FORWARD).get("mesh") == pad,"Non-rendered perspective bounds proxy does not occlude")
 pad.transform = Transform3D(Basis(Vector3.UP,0.6).scaled(Vector3(-2,0.7,1.8)),Vector3(0.2,0.1,-0.4))
 var center := pad.to_global(Vector3.ZERO)
 var normal := (pad.global_basis.inverse().transposed()*Vector3.BACK).normalized()
 hit = picker.nearest_hit([world],center+normal*3.0,-normal)
 check(hit.get("mesh") == pad and is_equal_approx(hit.get("distance",0.0),3.0),"Ray distance survives mirrored/nonuniform transformed mesh")
 check(pad.mesh == source_mesh and pad.mesh.get_faces() == source_faces,"Picker never edits shared geometry")
 check(picker.nearest_hit([world],Vector3.ZERO,Vector3.ZERO).is_empty(),"Degenerate ray fails closed")
 world.free()

func test_exhibit_player_identity() -> void:
 var exhibit := Exhibit.new()
 root.add_child(exhibit)
 var player_2 := Node3D.new()
 player_2.set_meta("controller_port",1)
 exhibit.add_child(player_2)
 player_2.add_child(triangle())
 exhibit.pads.append(player_2)
 check(exhibit.pick_controller(Vector3(0,0,2),Vector3.FORWARD) == 1,"P2 remains P2 even if P1 failed to load")
 var console := triangle()
 console.position.z = 1.0
 root.add_child(console)
 exhibit.console = console
 check(exhibit.pick_controller(Vector3(0,0,2),Vector3.FORWARD) == -1,"Sibling console really occludes pad")
 console.hide()
 check(exhibit.pick_controller(Vector3(0,0,2),Vector3.FORWARD) == 1,"Visible pad is picked through hidden console only")
 exhibit.free()
 console.free()

func test_background_tooltip_state() -> void:
 var host := TooltipHostProbe.new()
 root.add_child(host)
 host.set_process(false)
 host.set_process_input(false)
 host.footer = HFlowContainer.new()
 host.add_child(host.footer)
 host.console_button = Button.new()
 host.console_button.tooltip_text = "Selecionar Master System"
 host.console_button.mouse_filter = Control.MOUSE_FILTER_STOP
 host.add_child(host.console_button)
 var footer_button := Button.new()
 footer_button.tooltip_text = "Original footer tooltip"
 footer_button.mouse_filter = Control.MOUSE_FILTER_PASS
 footer_button.disabled = true
 footer_button.hide()
 host.footer.add_child(footer_button)
 host._set_background_blocked(true)
 check(host.console_button.tooltip_text.is_empty() and footer_button.tooltip_text.is_empty(), "Blocked HOME controls cannot start background tooltips")
 check(host.console_button.mouse_filter == Control.MOUSE_FILTER_IGNORE and footer_button.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Blocked controls leave the hover chain")
 check(host.console_button.visible and not footer_button.visible, "Tooltip cleanup preserves original visibility within the frame")
 host._set_background_blocked(false)
 check(host.console_button.tooltip_text == "Selecionar Master System" and footer_button.tooltip_text == "Original footer tooltip", "Closing restores exact tooltip text")
 check(host.console_button.mouse_filter == Control.MOUSE_FILTER_STOP and footer_button.mouse_filter == Control.MOUSE_FILTER_PASS, "Closing restores original pointer behavior")
 check(not host.console_button.disabled and footer_button.disabled, "Closing preserves each prior disabled state")
 host.free()

func run() -> void:
 test_background_tooltip_state()
 test_routing_and_release()
 test_click_gestures()
 test_home_eligibility()
 test_triangle_occlusion()
 test_exhibit_player_identity()
 print(JSON.stringify({"suite":"controller_host","assertions":assertions,"failures":failures}))
 quit(0 if failures.is_empty() else 1)
