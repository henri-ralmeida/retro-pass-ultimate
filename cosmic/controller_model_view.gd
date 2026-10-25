extends Control
## A new instance of the same HardwareMedia model. Original meshes/materials remain unchanged.
const HardwareMedia = preload("res://cosmic/hardware_media.gd")
const Regions = preload("res://cosmic/controller_hit_regions.gd")
signal action_selected(action: String)
signal action_hovered(action: String)
signal availability_changed(notice: String)
var viewport: SubViewport
var camera: Camera3D
var world: Node3D
var model: Node3D
var regions = Regions.new()
var source_path := ""
var notice := ""
var interactive := true
var focused_action := ""
var pressed_position := Vector2(-1, -1)
var pressed_action := ""
var hovered_action := ""
var highlight: MeshInstance3D
var body_bounds := AABB()
var texture: TextureRect
var zoom := 1.0

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_STOP
 custom_minimum_size = Vector2(260, 180)
 viewport = SubViewport.new()
 viewport.own_world_3d = true
 viewport.transparent_bg = true
 viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
 viewport.handle_input_locally = false
 add_child(viewport)
 texture = TextureRect.new()
 texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
 texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 texture.stretch_mode = TextureRect.STRETCH_SCALE
 texture.texture = viewport.get_texture()
 add_child(texture)
 world = Node3D.new()
 viewport.add_child(world)
 camera = Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.near = 0.001
 camera.far = 4.0
 camera.current = true
 world.add_child(camera)
 var environment := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color(0.02, 0.04, 0.08, 0.0)
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color(0.78, 0.85, 1.0)
 env.ambient_light_energy = 0.75
 environment.environment = env
 world.add_child(environment)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-64, -25, 0)
 light.light_energy = 1.15
 world.add_child(light)
 var fill := DirectionalLight3D.new()
 fill.rotation_degrees = Vector3(-35, 130, 0)
 fill.light_energy = 0.35
 world.add_child(fill)
 resized.connect(_fit)
 gui_input.connect(_on_gui_input)
 mouse_exited.connect(func(): hovered_action = ""; action_hovered.emit(""))
 _fit()

func load_approved_model() -> bool:
 clear_model()
 source_path = HardwareMedia.controller_path()
 if not FileAccess.file_exists(source_path):
  return _unavailable("Modelo do controle indisponível nesta instalação. Use a lista de comandos.")
 var document := GLTFDocument.new()
 var state := GLTFState.new()
 var result := document.append_from_file(ProjectSettings.globalize_path(source_path), state)
 if result != OK: return _unavailable("Não foi possível abrir o modelo aprovado. Use a lista de comandos.")
 var instance := document.generate_scene(state) as Node3D
 if instance == null: return _unavailable("Modelo inválido. A lista de comandos continua disponível.")
 if not install_instance(instance): return false
 notice = "Modelo neutro; a arte local não está instalada." if source_path == HardwareMedia.FALLBACK_CONTROLLER else "Selecione uma direção ou botão no controle, ou use a lista ao lado."
 availability_changed.emit(notice)
 return true

func install_instance(instance: Node3D) -> bool:
 # Injection point for deterministic synthetic geometry tests, never a replacement asset.
 clear_model()
 model = instance
 world.add_child(model)
 var bounds := {}
 var first := true
 for node in model.find_children("*", "MeshInstance3D", true, false):
  var mesh := node as MeshInstance3D
  if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
  var frame: Transform3D = model.global_transform.affine_inverse() * mesh.global_transform
  var local_bounds: AABB = frame * mesh.get_aabb()
  if str(mesh.name) in Regions.REQUIRED_MESHES: bounds[str(mesh.name)] = local_bounds
  body_bounds = local_bounds if first else body_bounds.merge(local_bounds)
  first = false
 if first: return _unavailable("O modelo não contém superfícies visíveis. Use a lista de comandos.")
 if not regions.configure(bounds):
  notice = "Geometria de seleção incompleta. Use a lista de comandos."
  availability_changed.emit(notice)
  _fit()
  return false
 highlight = MeshInstance3D.new()
 highlight.name = "SeparateSelectionOverlay"
 var material := StandardMaterial3D.new()
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 material.albedo_color = Color(0.25, 0.85, 1.0, 0.6)
 material.no_depth_test = false
 highlight.material_override = material
 model.add_child(highlight)
 highlight.visible = false
 zoom = 1.0
 _fit()
 return true

func _unavailable(message: String) -> bool:
 notice = message
 regions.regions.clear()
 availability_changed.emit(notice)
 return false

func clear_model() -> void:
 if is_instance_valid(model):
  model.get_parent().remove_child(model)
  model.queue_free()
 model = null
 highlight = null
 regions.regions.clear()
 body_bounds = AABB()
 pressed_action = ""
 focused_action = ""
 hovered_action = ""

func _fit() -> void:
 if not is_instance_valid(viewport): return
 viewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
 if not is_instance_valid(model) or body_bounds.size == Vector3.ZERO: return
 var center: Vector3 = model.global_transform * body_bounds.get_center()
 camera.position = center + Vector3(0.055, 0.45, 0.07)
 camera.look_at(center, Vector3.FORWARD)
 # Camera KEEP_HEIGHT means size is vertical; include width for narrow aspect ratios.
 camera.keep_aspect = Camera3D.KEEP_HEIGHT
 var aspect := maxf(0.1, float(viewport.size.x) / float(viewport.size.y))
 var low := Vector2(INF, INF)
 var high := Vector2(-INF, -INF)
 var camera_basis := camera.global_transform.basis.inverse()
 for corner in 8:
  var local := body_bounds.position + Vector3(body_bounds.size.x if corner & 1 else 0.0, body_bounds.size.y if corner & 2 else 0.0, body_bounds.size.z if corner & 4 else 0.0)
  var projected := camera_basis * (model.global_transform * local - center)
  var point := Vector2(projected.x, projected.y)
  low = low.min(point)
  high = high.max(point)
 var span := high - low
 camera.size = maxf(span.y, span.x / aspect) * 1.24 / zoom

func set_zoom(value: float) -> void:
 zoom = clampf(value, 0.8, 1.4)
 _fit()

func action_at(point: Vector2) -> String:
 if not interactive or not is_instance_valid(model) or not Rect2(Vector2.ZERO, size).has_point(point): return ""
 var mapped := Regions.viewport_point(point, Rect2(Vector2.ZERO, size), Vector2(viewport.size))
 var hit: Dictionary = regions.pick_world_ray(camera.project_ray_origin(mapped), camera.project_ray_normal(mapped), model.global_transform)
 return str(hit.get("action", ""))

func set_highlight(action: String) -> void:
 focused_action = action
 if not is_instance_valid(highlight): return
 highlight.visible = action in ["up", "down", "left", "right", "button_1", "button_2"] and not regions.regions.is_empty()
 if not highlight.visible: return
 var region: Dictionary = regions.regions["dpad" if action in ["up", "down", "left", "right"] else action]
 var center: Vector3 = region.center
 center.y = float(region.height) + 0.0005
 var radius: float = float(region.radius)
 if action in ["up", "down", "left", "right"]:
  var offset: Vector3 = {"up": Vector3.FORWARD, "down": Vector3.BACK, "left": Vector3.LEFT, "right": Vector3.RIGHT}[action]
  center += offset * radius * 0.65
  radius *= 0.26
 var disc := CylinderMesh.new()
 disc.top_radius = radius
 disc.bottom_radius = radius
 disc.height = 0.0003
 highlight.mesh = disc
 highlight.position = center

func _on_gui_input(event: InputEvent) -> void:
 if not interactive: return
 if event is InputEventMouseMotion:
  hovered_action = action_at(event.position)
  action_hovered.emit(hovered_action)
  if pressed_position.x >= 0 and event.position.distance_to(pressed_position) > 6.0: pressed_action = ""
 elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
  if event.pressed:
   pressed_position = event.position
   pressed_action = action_at(event.position)
  else:
   var action := pressed_action
   pressed_action = ""
   if not action.is_empty() and event.position.distance_to(pressed_position) <= 6.0 and action_at(event.position) == action: action_selected.emit(action)
   pressed_position = Vector2(-1, -1)
  accept_event()

func cancel_pointer() -> void:
 pressed_action = ""
 pressed_position = Vector2(-1, -1)
