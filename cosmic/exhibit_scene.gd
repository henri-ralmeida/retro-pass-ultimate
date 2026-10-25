extends Node3D
## Isolated, optional display module. No selection routing, launch, input, or private media scan.
## configure(system, selected_item) retains the selected game's box/cartridge pairing.
## All dimensions are meters. Caller owns camera, light, UI and voluntary manipulation.
const BoxScene = preload("res://cosmic/game_box.gd")
const PAD_PATH := "res://assets/exhibit_models/SMS_Controller_neutral.glb"
const CABLE_RADIUS := 0.0015
const MANUAL_NOTICE := "Manual indisponível para esta edição. Nenhuma página substituta foi criada."
var inserted_cartridge: Node3D
var dust_door: Node3D
var dust_door_rest := Transform3D.IDENTITY
var dust_door_display := Transform3D.IDENTITY
var insertion_status := "No selected cartridge"
var console: Node3D
var game_box: Node3D
var pads: Array[Node3D] = []
var cables: Array[MeshInstance3D] = []
var cable_paths: Array[PackedVector3Array] = []
var socket_positions: Array[Vector3] = []
var selected_item: Dictionary = {}
var layout_offset := Vector3.ZERO
var manual_available := false
var configuration_errors: Array[String] = []

func _clear(item: Dictionary) -> void:
 _restore_dust_door()
 inserted_cartridge = null
 dust_door = null
 for child in get_children():
  remove_child(child)
  child.queue_free()
 pads.clear()
 cables.clear()
 cable_paths.clear()
 socket_positions.clear()
 configuration_errors.clear()
 game_box = null
 console = null
 selected_item = item.duplicate(true)
 manual_available = false # No verified manual asset is presently supplied.
 set_meta("manual_notice", MANUAL_NOTICE)
 set_meta("selected_game_id", str(item.get("id", "unavailable")))

func configure(system: Resource, item: Dictionary = {}) -> bool:
 _clear(item)
 if system == null or system.model == null:
  configuration_errors.append("Console model unavailable")
  return false
 console = system.model.instantiate() as Node3D
 add_child(console)
 console.transform = system.presentation_transform
 var console_bounds := bounds_of(console)
 console.position += Vector3(0.025-console_bounds.get_center().x, -console_bounds.position.y, -0.075-console_bounds.get_center().z)
 return _populate(item)

func configure_extras(existing_console: Node3D, item: Dictionary = {}) -> bool:
 # Attach this module beside, not inside, the console's inspection pivot.
 # The caller hides this node during console-only inspection/history.
 _clear(item)
 console = existing_console
 if not is_instance_valid(console):
  configuration_errors.append("Existing console unavailable")
  return false
 return _populate(item)

func _populate(item: Dictionary) -> bool:
 var console_bounds := bounds_of(console)
 layout_offset = Vector3(console_bounds.get_center().x-0.025, console_bounds.position.y, console_bounds.get_center().z+0.075)
 for index in 2:
  var socket := console.find_child("Controller_port_socket_%d" % index, true, false) as MeshInstance3D
  if socket == null:
   configuration_errors.append("Verified front socket %d unavailable" % index)
   continue
  var socket_transform := relative_transform(socket)
  var socket_center := socket_transform * socket.get_aabb().get_center()
  # Use the front surface rather than the recessed socket center.
  socket_center.z = (socket_transform * socket.get_aabb()).end.z + 0.001
  socket_positions.append(socket_center)
  _controller(index, socket_center)
 if not item.is_empty():
  game_box = BoxScene.new()
  game_box.configure(item)
  add_child(game_box)
  game_box.toggle_lid()
  game_box.lid.rotation.z = deg_to_rad(70.0)
  game_box.rotation = Vector3(-PI*0.5, PI, 0)
  # Existing same-game model includes its matching cartridge, never another game.
  game_box.scale = Vector3.ONE * (0.18 / 2.44)
  var box_bounds := bounds_of(game_box)
  game_box.position += Vector3(-0.245-box_bounds.get_center().x, -box_bounds.position.y, -0.095-box_bounds.get_center().z) + layout_offset
  _seat_matching_cartridge()
 _add_exhibit_fill()
 return configuration_errors.is_empty()

func _add_exhibit_fill() -> void:
 var fill := OmniLight3D.new()
 fill.name = "ExhibitSoftFill"
 fill.position = Vector3(-0.05,0.25,0.23) + layout_offset
 fill.light_color = Color("e2eaff")
 fill.light_energy = 0.65
 fill.omni_range = 0.8
 fill.omni_attenuation = 0.7
 fill.shadow_enabled = false
 add_child(fill)

func _seat_matching_cartridge() -> void:
 var well := console.find_child("Cartridge_well", true, false) as MeshInstance3D
 dust_door = console.find_child("Cartridge_dust_door", true, false) as Node3D
 if well == null or dust_door == null or not is_instance_valid(game_box.cartridge):
  configuration_errors.append("Verified cartridge rig or slot unavailable")
  return
 var well_bounds: AABB = relative_transform(well) * well.get_aabb()
 inserted_cartridge = game_box.cartridge
 inserted_cartridge.reparent(self, false)
 inserted_cartridge.transform = Transform3D.IDENTITY
 # Original cartridge rig is already in meters, upright, with label facing +Z.
 var cartridge_bounds := bounds_of(inserted_cartridge)
 if cartridge_bounds.size.x > well_bounds.size.x or cartridge_bounds.size.z > well_bounds.size.z:
  configuration_errors.append("Selected cartridge does not fit verified slot footprint")
  inserted_cartridge.reparent(game_box.original_model, false)
  inserted_cartridge.transform = game_box.inside_pose
  inserted_cartridge = null
  return
 inserted_cartridge.position = Vector3(well_bounds.get_center().x-cartridge_bounds.get_center().x, well_bounds.end.y+0.0003-cartridge_bounds.position.y, well_bounds.get_center().z-cartridge_bounds.get_center().z)
 game_box.cartridge = null # There is one cartridge, moved from the open box, not copied.
 inserted_cartridge.set_meta("selected_game_id", str(selected_item.get("id", "unavailable")))
 dust_door_rest = dust_door.transform
 dust_door_display = dust_door_rest
 # Static depressed flap: preserve geometry and restore exact pose for inspection.
 # The source has a solid well floor; do not invent a deeper cavity or animation.
 dust_door_display.origin.y -= 0.006
 dust_door.transform = dust_door_display
 insertion_status = "Same-game cartridge seated above verified well floor; static display, not insertion simulation"

func set_exhibit_visible(value: bool) -> void:
 visible = value
 if is_instance_valid(dust_door):
  dust_door.transform = dust_door_display if value and is_instance_valid(inserted_cartridge) else dust_door_rest

func _restore_dust_door() -> void:
 if is_instance_valid(dust_door): dust_door.transform = dust_door_rest

func _exit_tree() -> void:
 _restore_dust_door()

func relative_transform(node: Node3D) -> Transform3D:
 if is_inside_tree() and node.is_inside_tree():
  return global_transform.affine_inverse() * node.global_transform
 var result := Transform3D.IDENTITY
 var current: Node = node
 while current != self and current != null:
  if current is Node3D: result = current.transform * result
  current = current.get_parent()
 return result

func bounds_of(node: Node3D) -> AABB:
 var result := AABB()
 var first := true
 var meshes := node.find_children("*", "MeshInstance3D", true, false)
 if node is MeshInstance3D: meshes.append(node)
 for mesh in meshes:
  if mesh.mesh == null: continue
  var bounds: AABB = relative_transform(mesh) * mesh.get_aabb()
  result = bounds if first else result.merge(bounds)
  first = false
 return result

func get_local_bounds() -> AABB:
 return bounds_of(self)

func get_combined_bounds() -> AABB:
 var result := get_local_bounds()
 return result.merge(bounds_of(console)) if is_instance_valid(console) else result

func _controller(index: int, socket: Vector3) -> void:
 var document := GLTFDocument.new()
 var state := GLTFState.new()
 if document.append_from_file(ProjectSettings.globalize_path(PAD_PATH), state) != OK:
  configuration_errors.append("Neutral controller unavailable")
  return
 var pad := document.generate_scene(state) as Node3D
 if pad == null:
  configuration_errors.append("Neutral controller could not be instantiated")
  return
 pad.name = "Controller%d" % (index+1)
 add_child(pad)
 pad.position = Vector3(-0.095 if index == 0 else 0.115, 0, 0.105) + layout_offset
 pads.append(pad)
 var anchor := pad.find_child("ControllerCableAnchor", true, false) as Node3D
 if anchor == null:
  configuration_errors.append("Controller cable anchor unavailable")
  return
 var anchor_transform := relative_transform(anchor)
 var start := anchor_transform.origin
 var tangent := anchor_transform.basis.x.normalized()
 var curve := Curve3D.new()
 curve.bake_interval = 0.002
 curve.add_point(start, Vector3.ZERO, tangent*0.026)
 # Separate slack lanes keep the cables clear of pad faces and game packaging.
 var slack: Vector3
 if tangent.z < -0.5:
  slack = Vector3(-0.055 if index == 0 else 0.100, 0.004, 0.055) + layout_offset
  curve.add_point(slack, Vector3(-0.014 if index == 0 else 0.014,0,0.012), Vector3(0.014 if index == 0 else -0.014,0,-0.008))
 else:
  slack = Vector3(-0.030 if index == 0 else 0.235, 0.004, 0.232 if index == 0 else 0.222) + layout_offset
  curve.add_point(slack, Vector3(0.025,0,0), Vector3(-0.025,0,-0.012))
 var approach := Vector3(socket.x, layout_offset.y+0.008, socket.z+0.020)
 curve.add_point(approach, Vector3(-0.010 if index == 0 else 0.010,0,0.008), Vector3(0,0,-0.008))
 curve.add_point(socket, Vector3(0,0,0.015), Vector3.ZERO)
 var points := PackedVector3Array()
 var length := curve.get_baked_length()
 for sample in 65: points.append(curve.sample_baked(length*sample/64.0, true))
 cable_paths.append(points)
 var cable := MeshInstance3D.new()
 cable.name = "ControllerCable%d" % (index+1)
 cable.mesh = _tube(points)
 var material := StandardMaterial3D.new()
 material.albedo_color = Color("101113")
 material.roughness = 0.72
 material.cull_mode = BaseMaterial3D.CULL_DISABLED
 cable.material_override = material
 add_child(cable)
 cables.append(cable)

func _tube(points: PackedVector3Array) -> ArrayMesh:
 var surface := SurfaceTool.new()
 surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 var rings: Array[PackedVector3Array] = []
 for index in points.size():
  var direction := (points[mini(index+1,points.size()-1)]-points[maxi(index-1,0)]).normalized()
  var normal := direction.cross(Vector3.UP).normalized()
  if normal.length_squared() < 0.1: normal = direction.cross(Vector3.RIGHT).normalized()
  var binormal := direction.cross(normal).normalized()
  var ring := PackedVector3Array()
  for side in 8:
   var angle := TAU*side/8.0
   ring.append(points[index]+CABLE_RADIUS*(cos(angle)*normal+sin(angle)*binormal))
  rings.append(ring)
 for index in points.size()-1:
  for side in 8:
   var next := (side+1)%8
   for vertex in [rings[index][side],rings[index+1][side],rings[index+1][next],rings[index][side],rings[index+1][next],rings[index][next]]:
    surface.add_vertex(vertex)
 surface.generate_normals()
 return surface.commit()
