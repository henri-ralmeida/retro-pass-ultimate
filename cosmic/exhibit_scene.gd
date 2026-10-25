extends Node3D
## Isolated, optional display module. No selection routing, launch, input, or private media scan.
## configure(system, selected_item) retains the selected game's box/cartridge pairing.
## All dimensions are meters. Caller owns camera, light, UI and voluntary manipulation.
const BoxScene = preload("res://cosmic/game_box.gd")
const CableRouting = preload("res://cosmic/controller_cable.gd")
const HardwareMedia = preload("res://cosmic/hardware_media.gd")
const ControllerConnector = preload("res://cosmic/controller_connector.gd")
const CABLE_RADIUS := 0.0015
const MANUAL_NOTICE := "Manual indisponível para esta edição. Nenhuma página substituta foi criada."
const REFERENCE_EXPOSED_HEIGHT := 0.026 # Approximate reference-photo fit, not a hardware specification.
const SLOT_CLIP_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 abs_color : source_color = vec4(0.02,0.02,0.02,1.0);
uniform float abs_roughness = 0.65;
uniform float abs_specular = 0.25;
uniform float abs_metallic = 0.0;
uniform bool use_normal = false;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_strength = 0.65;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform mat4 mesh_to_console;
uniform vec3 slot_min;
uniform vec3 slot_max;
varying vec3 console_point;
void vertex() {
 console_point = (mesh_to_console*vec4(VERTEX,1.0)).xyz;
 UV = UV*uv_scale+uv_offset;
}
void fragment() {
 if (all(greaterThan(console_point,slot_min)) && all(lessThan(console_point,slot_max))) discard;
 ALBEDO = abs_color.rgb;
 METALLIC = abs_metallic;
 ROUGHNESS = abs_roughness;
 SPECULAR = abs_specular;
 if (use_normal) {
  NORMAL_MAP = texture(normal_map,UV).rgb;
  NORMAL_MAP_DEPTH = normal_strength;
 }
}
"""
var slot_ready := false
var connectors: Array[Node3D] = []
var cable_exit_positions: Array[Vector3] = []
var slot_well: MeshInstance3D
var well_rest := Transform3D.IDENTITY
var well_display := Transform3D.IDENTITY
var dust_door_was_visible := true
var slot_surfaces: Array[Dictionary] = []
var slot_clip_min := Vector3.ZERO
var slot_clip_max := Vector3.ZERO
var original_slot_top := 0.0
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
var cable_diagnostics: Array[Dictionary] = []
var cable_jobs: Array[Dictionary] = []
var socket_positions: Array[Vector3] = []
var selected_item: Dictionary = {}
var presentation_basis := Basis.IDENTITY
var layout_offset := Vector3.ZERO
var hardware_art_missing := false
var manual_available := false
var configuration_errors: Array[String] = []

func _clear(item: Dictionary) -> void:
 _restore_dust_door()
 slot_surfaces.clear()
 slot_ready = false
 connectors.clear()
 cable_exit_positions.clear()
 slot_well = null
 inserted_cartridge = null
 dust_door = null
 for child in get_children():
  remove_child(child)
  child.queue_free()
 pads.clear()
 cables.clear()
 cable_paths.clear()
 cable_diagnostics.clear()
 cable_jobs.clear()
 socket_positions.clear()
 configuration_errors.clear()
 hardware_art_missing = false
 set_meta("hardware_art_missing",false)
 game_box = null
 console = null
 selected_item = item.duplicate(true)
 manual_available = false # Set only when a validated physical same-entry booklet is built.
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

func configure_extras(existing_console: Node3D, item: Dictionary = {}, view_basis: Basis = Basis.IDENTITY) -> bool:
 # Attach this module beside, not inside, the console's inspection pivot.
 # The caller hides this node during console-only inspection/history.
 _clear(item)
 presentation_basis = view_basis.orthonormalized()
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
  var connector := ControllerConnector.new()
  connector.name = "MoldedControllerConnector%d" % (index+1)
  add_child(connector)
  if not connector.configure(socket_transform,socket.get_aabb(),CABLE_RADIUS,0.0056):
   configuration_errors.append(connector.configuration_error)
   continue
  connectors.append(connector)
  var cable_exit: Vector3 = connector.get_cable_exit_anchor()
  cable_exit_positions.append(cable_exit)
  _controller(index,cable_exit,connector.get_outward_tangent())
 for job in cable_jobs: _route_controller_cable(job)
 if cable_paths.size()==2 and CableRouting.minimum_between_paths(cable_paths[0],cable_paths[1])<CABLE_RADIUS*3.0:
  configuration_errors.append("Controller cable lanes lack safe separation")
 if not item.is_empty():
  game_box = BoxScene.new()
  game_box.configure(item)
  manual_available = game_box.manual_book != null and game_box.manual_book.configured
  add_child(game_box)
  game_box.set_lid_angle(90.0) # Native bounds/fallback pose; HOME perspective renderer owns the visible calibrated box.
  game_box.opened = true
  # Undo GameBox's library display normalization, preserving exact native meters.
  var native_factor: float = game_box.original_model.scale.x
  game_box.scale = Vector3.ONE / native_factor
  _place_open_box_behind_console(console_bounds)
  _seat_matching_cartridge()
 _add_exhibit_fill()
 return configuration_errors.is_empty()

func _place_open_box_behind_console(console_bounds: AABB) -> void:
 var base := game_box.find_child("Case_back", true, false) as MeshInstance3D
 var lid := game_box.find_child("Case_lid", true, false) as MeshInstance3D
 if base == null or lid == null:
  configuration_errors.append("Original interior surfaces unavailable")
  return
 # Present the physical EXTERIOR wrap in a joined V: back, spine and front.
 var inverse_box := game_box.transform.affine_inverse()
 var base_frame := inverse_box * relative_transform(base)
 var lid_frame := inverse_box * relative_transform(lid)
 var normal := -((base_frame.basis*Vector3.UP).normalized() + (lid_frame.basis*Vector3.DOWN).normalized()).normalized()
 var up := (base_frame.basis*Vector3.FORWARD).normalized()
 var right := up.cross(normal).normalized()
 up = normal.cross(right).normalized()
 var uniform_scale: float = game_box.scale.x
 game_box.basis = presentation_basis * Basis(Vector3.RIGHT,deg_to_rad(-12.0)) * Basis(Vector3.UP,deg_to_rad(5.0)) * Basis(right,up,normal).inverse() * Basis.from_scale(Vector3.ONE*uniform_scale)
 var center := bounds_of(game_box).get_center()
 var target := console_bounds.get_center() - presentation_basis.z*0.26 - presentation_basis.x*0.15 + presentation_basis.y*0.10
 game_box.position += target-center
 # Keep the full physical box to the left of the console in screen projection.
 # Its depth stays behind the console, without artwork being hidden by it.
 var console_span := projected_horizontal_span(console)
 var box_span := projected_horizontal_span(game_box)
 game_box.position += presentation_basis.x*(console_span.x-0.018-box_span.y)
 game_box.set_meta("background_exterior_center",bounds_of(game_box).get_center())
 game_box.set_meta("native_scale",1.0)

func projected_horizontal_span(node: Node3D) -> Vector2:
 var span := Vector2(INF,-INF)
 for mesh in node.find_children("*","MeshInstance3D",true,false):
  if not mesh.visible or mesh.mesh == null: continue
  var frame := relative_transform(mesh)
  for corner in 8:
   var coordinate: float = (frame*mesh.get_aabb().get_endpoint(corner)).dot(presentation_basis.x)
   span.x = minf(span.x,coordinate)
   span.y = maxf(span.y,coordinate)
 return span

func _add_exhibit_fill() -> void:
 var fill := OmniLight3D.new()
 fill.name = "ExhibitSoftFill"
 fill.position = Vector3(-0.05,0.25,0.23) + layout_offset
 fill.light_color = Color.WHITE
 fill.light_energy = 0.20
 fill.omni_range = 0.8
 fill.omni_attenuation = 0.7
 fill.shadow_enabled = false
 add_child(fill)

func _seat_matching_cartridge() -> void:
 var candidate_well := console.find_child("Cartridge_well", true, false) as MeshInstance3D
 var candidate_door := console.find_child("Cartridge_dust_door", true, false) as Node3D
 if candidate_well == null or candidate_door == null or not is_instance_valid(game_box.cartridge):
  configuration_errors.append("Verified cartridge rig or slot unavailable")
  return
 slot_well = candidate_well
 dust_door = candidate_door
 dust_door_rest = dust_door.transform
 dust_door_display = dust_door_rest
 dust_door_was_visible = dust_door.visible
 well_rest = slot_well.transform
 well_display = well_rest
 var console_frame := relative_transform(console)
 var well_in_console := console_frame.affine_inverse()*relative_transform(slot_well)
 var well_bounds: AABB = well_in_console*slot_well.get_aabb()
 original_slot_top = well_bounds.end.y
 inserted_cartridge = game_box.cartridge
 var original_parent: Node = inserted_cartridge.get_parent()
 var original_pose := inserted_cartridge.transform
 inserted_cartridge.reparent(self, false)
 inserted_cartridge.transform = Transform3D.IDENTITY
 var cartridge_bounds := bounds_of(inserted_cartridge)
 if cartridge_bounds.size.x > well_bounds.size.x or cartridge_bounds.size.z > well_bounds.size.z:
  _abort_cartridge_seat("Selected cartridge does not fit verified slot footprint",original_parent,original_pose)
  return
 # The reference establishes a mostly concealed body, not an exact measurement.
 # Keep the same native cartridge; expose an approximate 26 mm above the rim.
 var seat := Vector3(well_bounds.get_center().x-cartridge_bounds.get_center().x, original_slot_top+REFERENCE_EXPOSED_HEIGHT-cartridge_bounds.end.y, well_bounds.get_center().z-cartridge_bounds.get_center().z)
 var seated_bounds := AABB(cartridge_bounds.position+seat,cartridge_bounds.size)
 slot_clip_min = Vector3(seated_bounds.position.x-0.001,seated_bounds.position.y-0.0015,seated_bounds.position.z-0.001)
 slot_clip_max = Vector3(seated_bounds.end.x+0.001,original_slot_top+0.001,seated_bounds.end.z+0.001)
 var lower := console.find_child("Lower_molded_shell",true,false) as MeshInstance3D
 if lower == null:
  _abort_cartridge_seat("Verified bottom shell unavailable",original_parent,original_pose)
  return
 var lower_bounds: AABB = console_frame.affine_inverse()*relative_transform(lower)*lower.get_aabb()
 if slot_clip_min.y <= lower_bounds.position.y+0.001:
  _abort_cartridge_seat("Requested seated depth would compromise original bottom shell",original_parent,original_pose)
  return
 if not _prepare_slot_clipping(console_frame):
  _abort_cartridge_seat("",original_parent,original_pose)
  return
 inserted_cartridge.transform = console_frame*Transform3D(Basis.IDENTITY,seat)
 # Move the existing floor below the cartridge, without modifying its mesh.
 var floor_top := seated_bounds.position.y-0.0016
 well_display.origin.y += floor_top-original_slot_top
 game_box.cartridge = null # One original cartridge, seated in the console; no loose HOME copy.
 inserted_cartridge.set_meta("selected_game_id",str(selected_item.get("id","unavailable")))
 insertion_status = "Original cartridge; approximately 26 mm exposed from photo reference. Reversible display-only slot clipping, not simulated mechanics."
 slot_ready = true
 _apply_slot_state(true)

func _abort_cartridge_seat(reason: String, original_parent: Node, original_pose: Transform3D) -> void:
 _apply_slot_state(false)
 slot_ready = false
 slot_surfaces.clear()
 if is_instance_valid(inserted_cartridge):
  inserted_cartridge.reparent(original_parent,false)
  inserted_cartridge.transform = original_pose
  game_box.cartridge = inserted_cartridge
 inserted_cartridge = null
 insertion_status = "Insertion unavailable; original cartridge remains in its box"
 if not reason.is_empty(): configuration_errors.append(reason)

func _prepare_slot_clipping(console_frame: Transform3D) -> bool:
 var shader := Shader.new()
 shader.code = SLOT_CLIP_SHADER
 for node_name in ["Upper_faceted_shell","Lower_molded_shell"]:
  var shell := console.find_child(node_name,true,false) as MeshInstance3D
  if shell == null:
   configuration_errors.append("Verified shell unavailable: "+node_name)
   return false
  for surface in shell.mesh.get_surface_count():
   var source := shell.get_active_material(surface) as StandardMaterial3D
   if source == null or source.albedo_texture != null or source.emission_enabled:
    configuration_errors.append("Unsupported shell material; refusing to approximate "+node_name)
    return false
   var display := ShaderMaterial.new()
   display.shader = shader
   display.set_shader_parameter("abs_color",source.albedo_color)
   display.set_shader_parameter("abs_roughness",source.roughness)
   display.set_shader_parameter("abs_specular",source.metallic_specular)
   display.set_shader_parameter("abs_metallic",source.metallic)
   display.set_shader_parameter("use_normal",source.normal_enabled and source.normal_texture != null)
   display.set_shader_parameter("normal_map",source.normal_texture)
   display.set_shader_parameter("normal_strength",source.normal_scale)
   display.set_shader_parameter("uv_scale",Vector2(source.uv1_scale.x,source.uv1_scale.y))
   display.set_shader_parameter("uv_offset",Vector2(source.uv1_offset.x,source.uv1_offset.y))
   display.set_shader_parameter("mesh_to_console",console_frame.affine_inverse()*relative_transform(shell))
   display.set_shader_parameter("slot_min",slot_clip_min)
   display.set_shader_parameter("slot_max",slot_clip_max)
   slot_surfaces.append({"mesh":shell,"surface":surface,"original_override":shell.get_surface_override_material(surface),"source_material":source,"display_material":display,"original_mesh":shell.mesh})
 return true

func set_exhibit_visible(value: bool) -> void:
 visible = value
 _apply_slot_state(value and is_instance_valid(inserted_cartridge))

func _apply_slot_state(active: bool) -> void:
 active = active and slot_ready
 for record in slot_surfaces:
  if is_instance_valid(record.mesh):
   record.mesh.set_surface_override_material(record.surface,record.display_material if active else record.original_override)
 if is_instance_valid(slot_well): slot_well.transform = well_display if active else well_rest
 if is_instance_valid(dust_door):
  dust_door.transform = dust_door_rest
  dust_door.visible = false if active else dust_door_was_visible

func _restore_dust_door() -> void:
 _apply_slot_state(false)

func _exit_tree() -> void:
 _apply_slot_state(false)

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

func get_visible_world_corners() -> PackedVector3Array:
 var points := PackedVector3Array()
 var seen := {}
 var roots: Array[Node3D] = [self]
 if is_instance_valid(console): roots.append(console)
 for root_node in roots:
  for mesh in root_node.find_children("*","MeshInstance3D",true,false):
   if mesh.mesh == null or not mesh.is_visible_in_tree() or seen.has(mesh.get_instance_id()): continue
   seen[mesh.get_instance_id()] = true
   var bounds: AABB = mesh.get_aabb()
   for index in 8: points.append(mesh.global_transform*bounds.get_endpoint(index))
 return points

func _controller(index: int, socket: Vector3, socket_outward: Vector3 = Vector3.BACK) -> void:
 var document := GLTFDocument.new()
 var state := GLTFState.new()
 var controller_path: String = HardwareMedia.controller_path()
 hardware_art_missing = hardware_art_missing or controller_path == HardwareMedia.FALLBACK_CONTROLLER
 set_meta("hardware_art_missing",hardware_art_missing)
 if document.append_from_file(ProjectSettings.globalize_path(controller_path), state) != OK:
  configuration_errors.append("Neutral controller unavailable")
  return
 var pad := document.generate_scene(state) as Node3D
 if pad == null:
  configuration_errors.append("Neutral controller could not be instantiated")
  return
 pad.name = "Controller%d" % (index+1)
 pad.set_meta("source_model",controller_path)
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
 cable_jobs.append({"index":index,"start":start,"tangent":tangent,"socket":socket,"outward":socket_outward})

func _route_controller_cable(job: Dictionary) -> void:
 var index: int = job.index
 var guides := PackedVector3Array([Vector3(-0.23,0.004,0.35),Vector3(-0.005,0.004,0.35),Vector3(-0.005,0.008,0.12)]) if index==0 else PackedVector3Array([Vector3(0.055,0.004,0.34),Vector3(0.025,0.004,0.20),Vector3(0.038,0.008,0.10)])
 for i in guides.size(): guides[i] += layout_offset
 var obstacles: Array = []
 for pad in pads: obstacles.append(bounds_of(pad))
 for connector in connectors: obstacles.append(connector.get_parent_bounds())
 var options := {"target_length":2.0,"radius":CABLE_RADIUS,"outer_radius_min":0.045,"outer_radius_max":0.100,"coil_center":Vector3(-0.13 if index==0 else 0.16,0.004,0.245)+layout_offset,"lead_out_guides":guides,"obstacles":obstacles}
 if job.tangent.z < -0.5:
  var incoming := PackedVector3Array([Vector3(-0.065,0.004,0.05),Vector3(-0.02,0.004,0.075),Vector3(-0.02,0.004,0.15)]) if index==0 else PackedVector3Array([Vector3(0.15,0.004,0.045),Vector3(0.21,0.004,0.075),Vector3(0.235,0.004,0.16)])
  for i in incoming.size(): incoming[i] += layout_offset
  options["lead_in_guides"] = incoming
 var routing := CableRouting.new()
 if not routing.build(job.start,job.tangent,job.socket,job.outward,options):
  configuration_errors.append("Controller cable %d: %s" % [index+1,routing.error])
  return
 var points: PackedVector3Array = routing.points
 cable_diagnostics.append(routing.diagnostics.duplicate(true))
 cable_paths.append(points)
 var cable := MeshInstance3D.new()
 cable.name = "ControllerCable%d" % (index+1)
 cable.mesh = _tube(points)
 var material := StandardMaterial3D.new()
 material.albedo_color = Color("08090b")
 material.roughness = 0.88
 material.metallic_specular = 0.16
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
