extends Control
## A local-image, genuinely 3D booklet. Each physical leaf owns faces 2*n/2*n+1.
## Stable spreads: 0=[-,0], 1=[1,2], ..., leaf_count=[last,-]. No guessed art.
## Public host API matches manual_reader.gd. Additional integration:
## bind_source_book(ManualBook, projected_rect, optional_source_camera) before open_item; a validated proxy
## uses that SAME booklet's dimensions/cover/geometry and temporarily hides only
## its root. Its prior visibility is restored on return. Never changes the case.
## Extraction is a projected-screen proxy, not an OEM paper/clip simulation.
## 0.8 mm fallback thickness is a thin DEMONSTRATION, never a measured OEM value.
## No embedded media paths, PDF decoder, network, emulation, or original edits.
## 3D runtime textures: max 6 pages, 24 MiB including mip levels, max edge 1024.
## Decode input is limited by the flat reader's 8 MiB/4096 px bounds, one image at
## a time. Original 4K files remain intact. Driver/viewport and transient decode
## storage are additional; source-model textures belong to the host, not cache.
## Reading/zoom stays in THIS 3D world with unchanged book meshes. Camera lens
## and bounded pan focus the selected original face. No 2D reader is created.
## Reading cache: two visible faces, max 64 MiB; selected face up to 3072 px,
## other visible face 1024 px. Current 1039x1455 scans remain native-resolution.
## No DOF, blur shader, motion blur, invented detail, or source-file changes.
## Host must route input here FIRST, consume releases, and reset its drag state.
signal closed
signal extracted(item_id: String)
signal returned_to_box(item_id: String)
signal reading_mode_changed(reading: bool)

const FlatReader = preload("res://cosmic/manual_reader.gd")
const MAX_CACHE_PAGES := 6
const MAX_CACHE_BYTES := 24 * 1024 * 1024
const RUNTIME_MAX_EDGE := 1024
const READING_MAX_EDGE := 3072
const READING_MAX_CACHE_BYTES := 64 * 1024 * 1024
const READING_MAX_CACHE_PAGES := 2
const READING_ZOOM_MIN := 1.0
const READING_ZOOM_MAX := 4.0
const BASE_CAMERA_FOV := 32.0
const MAX_VIEWPORT_EDGE := 1600
const DEFAULT_HEIGHT_M := 0.16
const DEMONSTRATION_THICKNESS_M := 0.0008
const TURN_SECONDS := 0.62
const TRANSFER_SECONDS := 0.48
const ZOOM_MIN := 0.8
const ZOOM_MAX := 2.5
const CURL_SEGMENTS := 16


var host: Node
var item_id := ""
var pages: Array[String] = []
var current_page := 0
var turned_leaves := 0
var leaf_count := 0
var zoom := 1.0
var last_error := ""
var cache: Dictionary = {}
var cache_bytes := 0
var dragging := false
var reduced_motion := false
var reading_mode := false
var flip_active := false
var flip_progress := 0.0
var _item: Dictionary = {}
var _validator = FlatReader.new()
var reading_zoom := 1.15
var pan := Vector2.ZERO
var pan_axis := Vector2.ZERO
var zoom_axis := 0.0
var _reference_directions: Dictionary = {}
var _reference_zooms: Dictionary = {}
var _reference_stick := Vector2.ZERO
var _built := false
var _window_focused := true
var _layout_size := Vector2.ZERO
var _leaf_size := Vector2(0.114, 0.16)
var _thickness := DEMONSTRATION_THICKNESS_M
var _source_ref: WeakRef
var _source_root_ref: WeakRef
var _source_was_visible := false
var _source_report: Dictionary = {}
var _entry_rect := Rect2()
var _entry_bound := false
var _source_view_valid := false
var _source_cover_in_camera := Transform3D.IDENTITY
var _source_vertical_fov := BASE_CAMERA_FOV
var _source_view_limit := "No source camera supplied; legacy rectangle-only transfer."
var _transfer := 0.0
var _transfer_direction := 0
var _previous_focus: WeakRef
var _page_errors: Dictionary = {}
var _protected_pages: Array[int] = []
var _held: Dictionary = {}
var _axis_ready: Dictionary = {}
var _axis_latched: Dictionary = {}
var _rotate_axis := Vector2.ZERO
var _zoom_axis := 0.0
var _triggers := Vector2.ZERO
var _drag_button := 0
var _clicked_button: Button
var _book_angles := Vector2(-0.16, -0.10)
var _flip_source := 0
var _flip_target := 0
var _flip_leaf := 0
var _flip_start_angle := 0.0
var _flip_end_angle := 0.0
var _flip_angle := 0.0
var _flip_elapsed := 0.0
var _flip_duration := TURN_SECONDS
var _flip_commit := true
var _pending_page := -1
var _font: Font = preload("res://assets/fonts/ChakraPetch-Regular.ttf")
var _heading_font: Font = preload("res://assets/fonts/Orbitron.ttf")
var _shade: ColorRect
var _title: Label
var _status: Label
var _help: Label
var _warning: Label
var _stage: Control
var _display: TextureRect
var _toolbar: HBoxContainer
var _buttons: Array[Button] = []
var _previous: Button
var _next: Button
var _read: Button
var _view_reset: Button
var _zoom_out: Button
var _zoom_in: Button
var _back: Button
var _viewport: SubViewport
var _world: Node3D
var _book_root: Node3D
var _camera: Camera3D
var _left_stack: MeshInstance3D
var _right_stack: MeshInstance3D
var _spine: MeshInstance3D
var _left_page: MeshInstance3D
var _right_page: MeshInstance3D
var _turn_root: Node3D
var _turn_front: MeshInstance3D
var _turn_back: MeshInstance3D
var _closed_proxy: Node3D
var _paper_material: StandardMaterial3D
var _page_shader: Shader

func configure(owner_node: Node) -> void:
 host = owner_node
 if is_instance_valid(host):
  if host.get("chakra") is Font: _font = host.get("chakra")
  if host.get("orbitron") is Font: _heading_font = host.get("orbitron")
 if is_inside_tree(): _build()

func _ready() -> void:
 name = "ManualBookReader"
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter = Control.MOUSE_FILTER_STOP
 z_index = 100
 hide()
 _build()

func _exit_tree() -> void:
 _restore_source()
 if is_instance_valid(_validator): _validator.free()

func _build() -> void:
 if _built: return
 _built = true
 _shade = ColorRect.new()
 _shade.color = Color("080d18")
 _shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(_shade)
 _title = _label("", 20, Color("eef1f7"))
 _title.add_theme_font_override("font", _heading_font)
 _title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 _status = _label("", 13, Color("b6cbdb"))
 _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 _warning = _label("", 13, Color("efc09c"))
 _warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _stage = Control.new()
 _stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(_stage)
 _display = TextureRect.new()
 _display.mouse_filter = Control.MOUSE_FILTER_IGNORE
 _display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
 _display.stretch_mode = TextureRect.STRETCH_SCALE
 _display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
 _stage.add_child(_display)
 _toolbar = HBoxContainer.new()
 _toolbar.tooltip_text = "Extensão de interface: Tab seleciona botões; Enter/Espaço ativa. Confirmar nativo continua abrindo leitura/zoom."
 _toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
 _toolbar.add_theme_constant_override("separation", 7)
 _toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
 add_child(_toolbar)
 _previous = _button("‹ Folha", "Virar folha anterior", func(): navigate(-1))
 _next = _button("Folha ›", "Virar próxima folha", func(): navigate(1))
 _read = _button("Ampliar página", "Ampliar a face selecionada no mesmo livreto 3D", enter_reading_mode)
 _zoom_out = _button("−", "Afastar livreto", func(): change_zoom(-0.15))
 _zoom_in = _button("+", "Aproximar livreto", func(): change_zoom(0.15))
 _view_reset = _button("Vista 3D", "Extensão 3D: repor vista sem virar páginas", reset_view)
 _back = _button("Devolver", "Devolver o mesmo livreto à caixa", close)
 _help = _label("", 12, Color("9db2c7"))
 _help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
 _help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _build_world()
 layout()

func _label(value: String, font_size: int, color: Color) -> Label:
 var label := Label.new()
 label.text = value
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 label.add_theme_font_override("font", _font)
 label.add_theme_font_size_override("font_size", font_size)
 label.add_theme_color_override("font_color", color)
 add_child(label)
 return label

func _button(value: String, description: String, callback: Callable) -> Button:
 var button := Button.new()
 var icon := "manual"
 if "anterior" in description: icon = "previous"
 elif "próxima" in description: icon = "next"
 elif "Afastar" in description: icon = "zoom_out"
 elif "Aproximar" in description or "Ampliar" in description: icon = "zoom_in"
 elif "repor" in description: icon = "reset"
 elif "Devolver" in description: icon = "back"
 preload("res://cosmic/ui_icons.gd").iconify(button,icon,description)
 button.tooltip_text = description
 button.accessibility_name = description
 button.custom_minimum_size = Vector2(42, 38)
 button.add_theme_font_override("font", _font)
 button.add_theme_font_size_override("font_size", 14)
 button.pressed.connect(callback)
 _toolbar.add_child(button)
 _buttons.append(button)
 return button

func _build_world() -> void:
 _viewport = SubViewport.new()
 _viewport.name = "BoundedBookViewport"
 _viewport.own_world_3d = true
 _viewport.transparent_bg = true
 _viewport.handle_input_locally = false
 _viewport.gui_disable_input = true
 _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 _viewport.msaa_3d = Viewport.MSAA_2X
 _viewport.positional_shadow_atlas_size = 0
 add_child(_viewport)
 _display.texture = _viewport.get_texture()
 _world = Node3D.new()
 _viewport.add_child(_world)
 var environment := WorldEnvironment.new()
 environment.environment = Environment.new()
 environment.environment.background_mode = Environment.BG_COLOR
 environment.environment.background_color = Color(0, 0, 0, 0)
 environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color = Color.WHITE
 environment.environment.ambient_light_energy = 0.7
 _world.add_child(environment)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-24, -22, 0)
 light.light_energy = 0.3
 light.shadow_enabled = false
 _world.add_child(light)
 _camera = Camera3D.new()
 _camera.fov = BASE_CAMERA_FOV
 _camera.keep_aspect = Camera3D.KEEP_HEIGHT
 _camera.near = 0.002
 _camera.far = 10
 _world.add_child(_camera)
 _camera.make_current()
 _book_root = Node3D.new()
 _world.add_child(_book_root)
 _paper_material = StandardMaterial3D.new()
 _paper_material.albedo_color = Color("e7e2d7")
 _paper_material.roughness = 0.94
 _page_shader = Shader.new()
 _page_shader.code = """shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D page_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float source_aspect = 0.714;
uniform float leaf_aspect = 0.714;
uniform bool has_page = false;
void fragment() {
 vec2 q = UV;
 if (source_aspect > leaf_aspect) q.y = (q.y - 0.5) * source_aspect / leaf_aspect + 0.5;
 else q.x = (q.x - 0.5) * leaf_aspect / source_aspect + 0.5;
 vec3 paper = vec3(0.94, 0.93, 0.89);
 if (!has_page) paper = vec3(0.54, 0.57, 0.61);
 if (has_page && q.x >= 0.0 && q.x <= 1.0 && q.y >= 0.0 && q.y <= 1.0) paper = texture(page_texture, q).rgb;
 ALBEDO = paper;
 ROUGHNESS = 1.0;
}
"""
 _left_stack = _solid("LeftLeafStack")
 _right_stack = _solid("RightLeafStack")
 _spine = _solid("DemonstrationSpine")
 _left_page = _page_mesh("LeftPrintedFace")
 _right_page = _page_mesh("RightPrintedFace")
 _turn_root = Node3D.new()
 _turn_root.name = "TwoSidedTurningLeaf"
 _book_root.add_child(_turn_root)
 _turn_front = _page_mesh("EvenFrontFace", _turn_root)
 _turn_back = _page_mesh("OddReverseFace", _turn_root)
 _turn_root.hide()

func _solid(node_name: String) -> MeshInstance3D:
 var mesh := MeshInstance3D.new()
 mesh.name = node_name
 mesh.mesh = BoxMesh.new()
 mesh.material_override = _paper_material
 _book_root.add_child(mesh)
 return mesh

func _page_mesh(node_name: String, parent: Node3D = null) -> MeshInstance3D:
 var mesh := MeshInstance3D.new()
 mesh.name = node_name
 mesh.mesh = ArrayMesh.new()
 var material := ShaderMaterial.new()
 material.shader = _page_shader
 mesh.material_override = material
 (parent if parent != null else _book_root).add_child(mesh)
 return mesh

func availability(item: Dictionary) -> bool:
 return status_for(item).is_empty()

func status_for(item: Dictionary) -> String:
 return _validator.status_for(item)

func bind_source_book(book: RefCounted, projected_rect: Rect2 = Rect2(), source_camera: Camera3D = null) -> bool:
 # Binding never moves the original. A new invalid binding clears the old one.
 if visible: return false
 _source_ref = null
 _source_report.clear()
 _entry_bound = false
 _entry_rect = Rect2()
 _source_view_valid = false
 _source_view_limit = "No source camera supplied; legacy rectangle-only transfer."
 if not is_instance_valid(book) or not book.has_method("get_report"): return false
 var report: Dictionary = book.get_report()
 if not bool(report.get("configured", false)): return false
 var page_size: Variant = report.get("page_size_m")
 var thickness: float = float(report.get("thickness_m", 0))
 if not page_size is Vector2 or not page_size.is_finite() or page_size.x <= 0 or page_size.y <= 0 or not is_finite(thickness) or thickness <= 0: return false
 _source_ref = weakref(book)
 _source_report = report.duplicate(true)
 if projected_rect.position.is_finite() and projected_rect.size.is_finite() and projected_rect.size.x >= 2 and projected_rect.size.y >= 2:
  _entry_rect = projected_rect
  _entry_bound = true
 if is_instance_valid(source_camera): _capture_source_view(book, source_camera)
 return true

func _capture_source_view(book: RefCounted, source_camera: Camera3D) -> void:
 # All transforms are rigid after removing the host's UNIFORM display scale.
 # The complete camera-relative origin is retained, including off-axis position;
 # keeping only a basis would still lose perspective foreshortening.
 var cover: Variant = book.get("cover")
 if not cover is MeshInstance3D or not is_instance_valid(cover): return
 if source_camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
  _source_view_limit = "Exact handoff currently supports perspective source cameras only."
  return
 var relative: Transform3D = source_camera.get_camera_transform().affine_inverse() * cover.global_transform
 var scale_value := relative.basis.get_scale()
 var uniform := (scale_value.x + scale_value.y + scale_value.z) / 3.0
 if not scale_value.is_finite() or uniform <= 0 or relative.basis.determinant() <= 0 or absf(scale_value.x - uniform) > uniform * 0.0001 or absf(scale_value.y - uniform) > uniform * 0.0001 or absf(scale_value.z - uniform) > uniform * 0.0001:
  _source_view_limit = "Exact handoff rejects mirrored, nonuniform or invalid source display scale."
  return
 relative.basis = relative.basis.orthonormalized()
 relative.origin /= uniform
 var fov := source_camera.fov
 if source_camera.keep_aspect == Camera3D.KEEP_WIDTH:
  var source_size := source_camera.get_viewport().get_visible_rect().size
  var aspect := source_size.x / maxf(source_size.y, 1)
  fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(fov * 0.5)) / aspect))
 if not is_finite(fov) or fov <= 1 or fov >= 175: return
 var page_size: Vector2 = _source_report.page_size_m
 for x in [-page_size.x * 0.5, page_size.x * 0.5]:
  for y in [-page_size.y * 0.5, page_size.y * 0.5]:
   if (relative * Vector3(x, y, 0)).z >= -0.0001:
    _source_view_limit = "Source cover crosses or lies behind its camera."
    return
 _source_cover_in_camera = relative
 _source_vertical_fov = fov
 _source_view_valid = _entry_bound
 _source_view_limit = "Perspective pose/FOV preserved; projection is subject only to viewport pixel rounding."

func set_reduced_motion(enabled: bool) -> void:
 reduced_motion = enabled
 if enabled:
  if flip_active: _finish_flip()
  if _transfer_direction != 0:
   _transfer = 1.0 if _transfer_direction > 0 else 0.0
   _finish_transfer()

func open_item(item: Dictionary) -> bool:
 if not is_inside_tree():
  last_error = "Leitor ainda não está disponível."
  return false
 _build()
 var source := _source_ref
 var report := _source_report.duplicate(true)
 var entry := _entry_rect
 var entry_bound := _entry_bound
 var source_view := _source_view_valid
 var source_cover_pose := _source_cover_in_camera
 var source_fov := _source_vertical_fov
 var source_limit := _source_view_limit
 var old_focus := get_viewport().gui_get_focus_owner()
 _clear_session()
 _source_ref = source
 _source_report = report
 _entry_rect = entry
 _entry_bound = entry_bound
 _source_view_valid = source_view
 _source_cover_in_camera = source_cover_pose
 _source_vertical_fov = source_fov
 _source_view_limit = source_limit
 last_error = status_for(item)
 if not last_error.is_empty(): return false
 if not _source_report.is_empty() and str(_source_report.get("item_id", "")) != str(item.id):
  last_error = "O livreto sob as presilhas não corresponde ao jogo selecionado."
  return false
 _item = item.duplicate(true)
 item_id = str(item.id)
 for path in item.manual_pages: pages.append(path)
 leaf_count = ceili(pages.size() / 2.0)
 _protected_pages = [0]
 var cover := _load_page(0)
 if cover.is_empty():
  last_error = str(_page_errors.get(0, "Capa indisponível."))
  _clear_session()
  return false
 var aspect: float = cover.size.x / cover.size.y
 _leaf_size = Vector2(DEFAULT_HEIGHT_M * aspect, DEFAULT_HEIGHT_M)
 _thickness = DEMONSTRATION_THICKNESS_M
 if not _source_report.is_empty():
  _leaf_size = _source_report.page_size_m
  _thickness = float(_source_report.thickness_m)
  if absf(_leaf_size.x / _leaf_size.y - aspect) > 0.002:
   last_error = "A proporção da capa difere do livreto de origem."
   _clear_session()
   return false
 if is_instance_valid(old_focus): _previous_focus = weakref(old_focus)
 _title.text = str(item.get("title", item_id)).left(180) + " · livreto 3D"
 _title.tooltip_text = _title.text
 _window_focused = true
 visible = true
 _take_source()
 _block_held_inputs()
 cancel_drag()
 layout()
 _show_spread()
 _back.grab_focus()
 _transfer = 0.0 if _entry_bound and not reduced_motion else 1.0
 _transfer_direction = 1 if _transfer < 1.0 else 0
 _apply_transfer()
 if _transfer_direction == 0: extracted.emit(item_id)
 _apply_activity()
 return true

func _take_source() -> void:
 if _source_ref == null: return
 var source: Variant = _source_ref.get_ref()
 if not is_instance_valid(source): return
 var root: Variant = source.get("root")
 if not root is Node3D or not is_instance_valid(root): return
 _source_root_ref = weakref(root)
 _source_was_visible = root.visible
 root.hide()
 _make_closed_proxy()

func _drop_closed_proxy() -> void:
 if is_instance_valid(_closed_proxy):
  _closed_proxy.get_parent().remove_child(_closed_proxy)
  _closed_proxy.free()
 _closed_proxy = null

func _make_closed_proxy() -> void:
 _drop_closed_proxy()
 if _source_ref == null or not cache.has(0): return
 var source: Variant = _source_ref.get_ref()
 if not is_instance_valid(source): return
 var root: Variant = source.get("root")
 if not root is Node3D or not is_instance_valid(root): return
 # Exact closed geometry proxy. It uses the same cover image through our LOD
 # cache, not an invented/independent book. Open leaves derive its dimensions.
 var cover: Variant = source.get("cover")
 if not cover is MeshInstance3D: return
 _closed_proxy = root.duplicate() as Node3D
 _closed_proxy.name = "SameSourceBookProxy"
 _closed_proxy.transform = Transform3D(cover.basis.inverse(), Vector3(_leaf_size.x * 0.5, 0, 0))
 _closed_proxy.visible = true
 _book_root.add_child(_closed_proxy)
 for child in _closed_proxy.get_children():
  if child is MeshInstance3D and str(child.name) == str(cover.name):
   var material: Material = child.material_override.duplicate()
   if material is StandardMaterial3D:
    material.albedo_texture = cache[0].texture
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
   child.material_override = material

func _restore_source() -> void:
 if _source_root_ref != null:
  var root: Variant = _source_root_ref.get_ref()
  if is_instance_valid(root) and root is Node3D: root.visible = _source_was_visible
 _source_root_ref = null

func close() -> void:
 if not visible: return
 if reading_mode:
  exit_reading_mode()
  return
 cancel_drag()
 _cancel_flip_immediate()
 if _entry_bound and not reduced_motion and _transfer > 0:
  # Return closed, with the original first-page cover, to its original clips.
  turned_leaves = 0
  current_page = 0
  _show_spread()
  _transfer_direction = -1
 else: _complete_close()

func finish_close() -> void:
 # Host teardown/selection changes MUST use this, not hierarchical user Back.
 # Synchronous in every state: zoom, turning, extraction, return, and focus loss.
 if visible: _complete_close()
 else: _clear_session()

func _complete_close() -> void:
 var old_id := item_id
 # A parent _exit_tree runs AFTER its children have left the tree. Teardown
 # must still restore source/cache without dereferencing a missing viewport.
 var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
 if is_instance_valid(focus) and is_ancestor_of(focus): focus.release_focus()
 var previous := _previous_focus
 _clear_session()
 if previous:
  var old: Variant = previous.get_ref()
  if is_instance_valid(old) and old is Control and old.is_visible_in_tree(): old.grab_focus()
 returned_to_box.emit(old_id)
 closed.emit()

func _clear_session() -> void:
 _restore_source()
 reading_mode = false
 reading_zoom = 1.15
 pan = Vector2.ZERO
 flip_active = false
 _transfer_direction = 0
 _transfer = 0
 visible = false
 cancel_drag()
 _drop_texture_references()
 _item.clear()
 pages.clear()
 item_id = ""
 current_page = 0
 turned_leaves = 0
 leaf_count = 0
 zoom = 1.0
 _book_angles = Vector2(-0.16, -0.10)
 _page_errors.clear()
 _protected_pages.clear()
 _source_ref = null
 _source_report.clear()
 _entry_bound = false
 _source_view_valid = false
 _source_cover_in_camera = Transform3D.IDENTITY
 _source_vertical_fov = BASE_CAMERA_FOV
 _previous_focus = null
 _held.clear()
 _apply_activity()

func _drop_texture_references() -> void:
 for mesh in [_left_page, _right_page, _turn_front, _turn_back]:
  if is_instance_valid(mesh):
   mesh.hide()
   mesh.material_override.set_shader_parameter("page_texture", null)
 _drop_closed_proxy()
 cache.clear()
 cache_bytes = 0

func _max_turned() -> int:
 return floori(pages.size() / 2.0)

func spread_for(leaves: int) -> Vector2i:
 var count := clampi(leaves, 0, _max_turned())
 var left := count * 2 - 1
 var right := count * 2
 return Vector2i(left if left >= 0 and left < pages.size() else -1, right if right < pages.size() else -1)

func _spread_indices(leaves: int) -> Array[int]:
 var spread := spread_for(leaves)
 var result: Array[int] = []
 if spread.x >= 0: result.append(spread.x)
 if spread.y >= 0: result.append(spread.y)
 return result

func _mip_bytes(size_value: Vector2i) -> int:
 var total := 0
 while true:
  total += size_value.x * size_value.y * 4
  if size_value == Vector2i.ONE: break
  size_value = Vector2i(maxi(1, size_value.x / 2), maxi(1, size_value.y / 2))
 return total

func _load_page(index: int, optional: bool = false) -> Dictionary:
 if cache.has(index): return cache[index]
 if index < 0 or index >= pages.size() or _page_errors.has(index): return {}
 var path := pages[index]
 var file := FileAccess.open(path, FileAccess.READ)
 if file == null: return _page_failed(index, "Página %d indisponível." % (index + 1))
 var count := file.get_length()
 if count <= 0 or count > FlatReader.MAX_FILE_BYTES:
  file.close()
  return _page_failed(index, "Página %d vazia ou acima de 8 MiB." % (index + 1))
 var bytes := file.get_buffer(count)
 file.close()
 if bytes.size() != count: return _page_failed(index, "Leitura incompleta da página %d." % (index + 1))
 var dimensions: Vector2i = _validator._header_size(bytes, path.get_extension().to_lower())
 if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x > FlatReader.MAX_EDGE or dimensions.y > FlatReader.MAX_EDGE or dimensions.x * dimensions.y > FlatReader.MAX_PIXELS:
  return _page_failed(index, "Página %d inválida ou acima de 4096 px." % (index + 1))
 var edge_limit := READING_MAX_EDGE if reading_mode and index == current_page else RUNTIME_MAX_EDGE
 var ratio := minf(1.0, edge_limit / float(maxi(dimensions.x, dimensions.y)))
 var lod := Vector2i(maxi(1, roundi(dimensions.x * ratio)), maxi(1, roundi(dimensions.y * ratio)))
 var needed := _mip_bytes(lod)
 if not _make_room(needed):
  if not optional: return _page_failed(index, "Orçamento de textura insuficiente para a página %d." % (index + 1))
  return {}
 var decoded := Image.new()
 var error := decoded.load_png_from_buffer(bytes) if path.get_extension().to_lower() == "png" else decoded.load_jpg_from_buffer(bytes)
 if error != OK or decoded.is_empty() or decoded.get_size() != dimensions: return _page_failed(index, "Página %d corrompida ou não suportada." % (index + 1))
 decoded.convert(Image.FORMAT_RGBA8)
 if dimensions != lod: decoded.resize(lod.x, lod.y, Image.INTERPOLATE_LANCZOS)
 decoded.generate_mipmaps()
 var actual := decoded.get_data_size()
 if actual > needed or cache_bytes + actual > _cache_budget(): return _page_failed(index, "Textura excedeu o orçamento declarado.")
 var entry := {"texture": ImageTexture.create_from_image(decoded), "size": Vector2(dimensions), "runtime_size": lod, "bytes": actual}
 cache[index] = entry
 cache_bytes += actual
 return entry

func _page_failed(index: int, message: String) -> Dictionary:
 _page_errors[index] = message
 return {}

func _cache_budget() -> int:
 return READING_MAX_CACHE_BYTES if reading_mode else MAX_CACHE_BYTES

func _cache_page_limit() -> int:
 return READING_MAX_CACHE_PAGES if reading_mode else MAX_CACHE_PAGES

func _make_room(needed: int) -> bool:
 while cache.size() >= _cache_page_limit() or cache_bytes + needed > _cache_budget():
  var victim := -1
  var farthest := -1
  for key in cache:
   if int(key) in _protected_pages: continue
   var distance := absi(int(key) - current_page)
   if distance > farthest:
    victim = int(key)
    farthest = distance
  if victim < 0: return false
  cache_bytes -= int(cache[victim].bytes)
  cache.erase(victim)
 return true

func _prune_cache(allowed: Array[int]) -> void:
 for key in cache.keys():
  if int(key) not in allowed:
   cache_bytes -= int(cache[key].bytes)
   cache.erase(key)

func _show_spread(prefetch: bool = true) -> void:
 if not _built or pages.is_empty(): return
 for mesh in [_left_page, _right_page, _turn_front, _turn_back]:
  mesh.material_override.set_shader_parameter("page_texture", null)
 _drop_closed_proxy()
 var spread := spread_for(turned_leaves)
 _protected_pages = _spread_indices(turned_leaves)
 var neighbors := _protected_pages.duplicate()
 for leaves in [turned_leaves + 1, turned_leaves - 1]:
  for index in _spread_indices(leaves):
   if index not in neighbors: neighbors.append(index)
 _prune_cache(neighbors)
 for index in _protected_pages: _load_page(index)
 if current_page not in _protected_pages: current_page = spread.y if spread.y >= 0 else spread.x
 var height_per_leaf := _thickness / maxf(1, leaf_count)
 _stack(_left_stack, turned_leaves, true, height_per_leaf)
 _stack(_right_stack, leaf_count - turned_leaves, false, height_per_leaf)
 var left_z := height_per_leaf * turned_leaves
 var right_z := height_per_leaf * (leaf_count - turned_leaves)
 _assign_page(_left_page, spread.x, true, left_z)
 _assign_page(_right_page, spread.y, false, right_z)
 _spine.visible = turned_leaves > 0 and turned_leaves < leaf_count
 (_spine.mesh as BoxMesh).size = Vector3(maxf(_thickness * 0.4, 0.00012), _leaf_size.y, _thickness)
 _spine.position = Vector3(0, 0, _thickness * 0.45)
 _turn_root.hide()
 if turned_leaves == 0: _make_closed_proxy()
 if is_instance_valid(_closed_proxy):
  _closed_proxy.visible = turned_leaves == 0
  if turned_leaves == 0:
   _right_stack.hide()
   _right_page.hide()
   _closed_proxy.position.z = _thickness * 0.5
 if prefetch:
  for index in neighbors:
   if index not in _protected_pages: _load_page(index, true)
 _update_labels()
 _frame_camera()
 _invalidate_render()

func _stack(mesh: MeshInstance3D, leaves: int, left: bool, per_leaf: float) -> void:
 mesh.visible = leaves > 0
 if leaves <= 0: return
 var depth := per_leaf * leaves
 (mesh.mesh as BoxMesh).size = Vector3(_leaf_size.x, _leaf_size.y, depth)
 mesh.position = Vector3((-1 if left else 1) * _leaf_size.x * 0.5, 0, depth * 0.5)

func _assign_page(mesh: MeshInstance3D, index: int, left: bool, depth: float) -> void:
 mesh.visible = index >= 0 and index < pages.size()
 mesh.set_meta("page_index", index)
 if not mesh.visible:
  mesh.material_override.set_shader_parameter("page_texture", null)
  return
 _surface(mesh.mesh, 0, false)
 mesh.rotation.y = 0
 mesh.position = Vector3(-_leaf_size.x if left else 0.0, 0, depth + 0.000003)
 _set_page_material(mesh, index)

func _set_page_material(mesh: MeshInstance3D, index: int) -> void:
 var entry: Dictionary = cache.get(index, {})
 var material := mesh.material_override as ShaderMaterial
 material.set_shader_parameter("page_texture", entry.get("texture", null))
 material.set_shader_parameter("has_page", not entry.is_empty())
 material.set_shader_parameter("leaf_aspect", _leaf_size.x / _leaf_size.y)
 material.set_shader_parameter("source_aspect", entry.size.x / entry.size.y if not entry.is_empty() else _leaf_size.x / _leaf_size.y)
 mesh.set_meta("page_index", index)

func _surface(mesh: ArrayMesh, bend: float, reverse: bool) -> void:
 var vertices := PackedVector3Array()
 var normals := PackedVector3Array()
 var uvs := PackedVector2Array()
 var indices := PackedInt32Array()
 for column in CURL_SEGMENTS + 1:
  var u := column / float(CURL_SEGMENTS)
  var z := sin(u * PI) * bend
  var slope := cos(u * PI) * PI * bend / _leaf_size.x
  var normal := Vector3(-slope, 0, 1).normalized() * (-1 if reverse else 1)
  for row in 2:
   vertices.append(Vector3(u * _leaf_size.x, (0.5 - row) * _leaf_size.y, z + (-0.000002 if reverse else 0.000002)))
   normals.append(normal)
   uvs.append(Vector2(1 - u if reverse else u, row))
 for column in CURL_SEGMENTS:
  var a := column * 2
  # Godot treats CLOCKWISE winding as front-facing. Keep printed face normals
  # outward, but triangle order clockwise when viewed from that printed side.
  if reverse: indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 2, a + 1, a + 3]))
  else: indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 2, a + 3, a + 1]))
 var arrays := []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = vertices
 arrays[Mesh.ARRAY_NORMAL] = normals
 arrays[Mesh.ARRAY_TEX_UV] = uvs
 arrays[Mesh.ARRAY_INDEX] = indices
 mesh.clear_surfaces()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func navigate(direction: int) -> void:
 if not visible or reading_mode or direction == 0 or _transfer_direction != 0: return
 var step := 1 if direction > 0 else -1
 if flip_active:
  if step == -signi(_flip_target - _flip_source): cancel_flip()
  return
 var target := clampi(turned_leaves + step, 0, _max_turned())
 if target == turned_leaves: return
 cancel_drag()
 if reduced_motion:
  turned_leaves = target
  _show_spread()
  return
 _flip_source = turned_leaves
 _flip_target = target
 _flip_leaf = turned_leaves if step > 0 else turned_leaves - 1
 _flip_start_angle = 0.0 if step > 0 else PI
 _flip_end_angle = PI if step > 0 else 0.0
 _flip_angle = _flip_start_angle
 _flip_elapsed = 0
 _flip_duration = TURN_SECONDS
 _flip_commit = true
 _pending_page = -1
 flip_progress = 0
 flip_active = true
 _protected_pages = _spread_indices(_flip_source)
 for index in _spread_indices(_flip_target):
  if index not in _protected_pages: _protected_pages.append(index)
 _prune_cache(_protected_pages)
 for index in _protected_pages: _load_page(index)
 _drop_closed_proxy()
 var left_index := _flip_leaf * 2 - 1
 var right_index := _flip_leaf * 2 + 2
 var unit := _thickness / maxf(1, leaf_count)
 _stack(_left_stack, _flip_leaf, true, unit)
 _stack(_right_stack, leaf_count - _flip_leaf - 1, false, unit)
 _assign_page(_left_page, left_index, true, unit * _flip_leaf)
 _assign_page(_right_page, right_index if right_index < pages.size() else -1, false, unit * (leaf_count - _flip_leaf - 1))
 _set_page_material(_turn_front, _flip_leaf * 2)
 _set_page_material(_turn_back, _flip_leaf * 2 + 1)
 _turn_front.show()
 _turn_back.visible = _flip_leaf * 2 + 1 < pages.size()
 _turn_root.show()
 _update_turn_mesh()
 _update_labels()
 _apply_activity()

func navigate_page(direction: int) -> void:
 # RetroBat image navigation advances ONE face, not one two-sided sheet. A
 # left/right face selection inside the same spread needs no physical turn.
 # This makes every verso reachable by keyboard/controller without a mouse.
 if not visible or reading_mode or direction == 0 or _transfer_direction != 0: return
 if flip_active:
  navigate(direction)
  return
 var target_page := clampi(current_page + (1 if direction > 0 else -1), 0, pages.size() - 1)
 if target_page == current_page: return
 var target_leaves := ceili(target_page / 2.0)
 if target_leaves == turned_leaves:
  current_page = target_page
  _update_labels()
  return
 navigate(1 if target_leaves > turned_leaves else -1)
 if flip_active: _pending_page = target_page
 else:
  current_page = target_page
  _update_labels()

func cancel_flip() -> void:
 if not flip_active: return
 if reduced_motion:
  _cancel_flip_immediate()
  return
 _flip_start_angle = _flip_angle
 _flip_end_angle = 0.0 if _flip_target > _flip_source else PI
 _flip_elapsed = 0
 _flip_duration = maxf(0.08, TURN_SECONDS * absf(_flip_end_angle - _flip_start_angle) / PI)
 _flip_commit = false
 flip_progress = 0

func _cancel_flip_immediate() -> void:
 if not flip_active: return
 turned_leaves = _flip_source
 _pending_page = -1
 flip_active = false
 _show_spread()

func _finish_flip() -> void:
 if not flip_active: return
 turned_leaves = _flip_target if _flip_commit else _flip_source
 if _flip_commit and _pending_page >= 0: current_page = _pending_page
 _pending_page = -1
 flip_active = false
 flip_progress = 1
 _show_spread()
 _apply_activity()

func _update_turn_mesh() -> void:
 var bend := sin(_flip_angle) * _leaf_size.x * 0.065
 _surface(_turn_front.mesh, bend, false)
 _surface(_turn_back.mesh, bend, true)
 _turn_root.rotation.y = -_flip_angle
 var unit := _thickness / maxf(1, leaf_count)
 var start_z := unit * (leaf_count - _flip_leaf)
 var end_z := unit * (_flip_leaf + 1)
 _turn_root.position.z = lerpf(start_z, end_z, _flip_angle / PI)
 _frame_camera()
 _invalidate_render()

func enter_reading_mode() -> void:
 if not visible or reading_mode or flip_active or _transfer_direction != 0: return
 cancel_drag()
 reading_mode = true
 reading_zoom = 1.15
 pan = Vector2.ZERO
 _reload_visible_quality()
 _block_held_inputs()
 _back.grab_focus()
 _update_labels()
 _frame_camera()
 _invalidate_render()
 reading_mode_changed.emit(true)

func exit_reading_mode() -> void:
 if not reading_mode: return
 reading_mode = false
 cancel_drag()
 pan = Vector2.ZERO
 _reload_visible_quality()
 _block_held_inputs()
 _read.grab_focus()
 _update_labels()
 _frame_camera()
 _invalidate_render()
 reading_mode_changed.emit(false)

func _reload_visible_quality() -> void:
 # Keep the same nodes, meshes, pose, viewport and original face identities.
 # Only texture quality changes. Unbind before eviction so byte accounting is
 # not defeated by hidden material references to old high-resolution textures.
 for mesh in [_left_page, _right_page, _turn_front, _turn_back]:
  mesh.material_override.set_shader_parameter("page_texture", null)
 if is_instance_valid(_closed_proxy):
  for child in _closed_proxy.get_children():
   if child is MeshInstance3D and child.material_override is StandardMaterial3D:
    if child.material_override.albedo_texture != null: child.material_override.albedo_texture = null
 cache.clear()
 cache_bytes = 0
 _protected_pages = _spread_indices(turned_leaves)
 _load_page(current_page)
 for index in _protected_pages:
  if index != current_page: _load_page(index)
 for mesh in [_left_page, _right_page]:
  var index: int = mesh.get_meta("page_index", -1)
  if index >= 0: _set_page_material(mesh, index)
 if is_instance_valid(_closed_proxy) and cache.has(0):
  for child in _closed_proxy.get_children():
   if child is MeshInstance3D and child.name == "ValidatedFirstPage" and child.material_override is StandardMaterial3D:
    child.material_override.albedo_texture = cache[0].texture
 if not reading_mode:
  for leaves in [turned_leaves + 1, turned_leaves - 1]:
   for index in _spread_indices(leaves):
    if index not in _protected_pages: _load_page(index, true)

func change_zoom(amount: float) -> void:
 if not visible or not is_finite(amount): return
 if reading_mode: reading_zoom = clampf(reading_zoom + amount, READING_ZOOM_MIN, READING_ZOOM_MAX)
 else: zoom = clampf(zoom + amount, ZOOM_MIN, ZOOM_MAX)
 _frame_camera()
 _update_labels()
 _invalidate_render()

func _pan_reading(amount: Vector2) -> void:
 if not reading_mode or not amount.is_finite(): return
 pan += amount
 _frame_camera()
 _invalidate_render()

func reset_view() -> void:
 cancel_drag()
 if reading_mode:
  reading_zoom = 1.0
  pan = Vector2.ZERO
 else:
  zoom = 1.0
  _book_angles = Vector2(-0.16, -0.10)
 _frame_camera()
 _update_labels()
 _invalidate_render()

func layout() -> void:
 if not _built or not is_inside_tree(): return
 var view := get_viewport().get_visible_rect().size
 _layout_size = view
 var margin := clampf(view.x * 0.035, 14, 38)
 _title.position = Vector2(margin, 17)
 _title.size = Vector2(maxf(90, view.x - margin * 2 - 230), 30)
 _title.add_theme_font_size_override("font_size", 16 if view.x < 900 else 20)
 _status.position = Vector2(view.x - margin - 225, 18)
 _status.size = Vector2(225, 30)
 _warning.position = Vector2(margin, 52)
 _warning.size = Vector2(view.x - margin * 2, 38)
 _stage.position = Vector2(margin, 88)
 _stage.size = Vector2(maxf(1, view.x - margin * 2), maxf(1, view.y - 188))
 _toolbar.position = Vector2(margin, view.y - 87)
 _toolbar.size = Vector2(view.x - margin * 2, 38)
 _help.position = Vector2(margin, view.y - 42)
 _help.size = Vector2(view.x - margin * 2, 38)
 var scale_value := minf(1, MAX_VIEWPORT_EDGE / maxf(_stage.size.x, _stage.size.y))
 _viewport.size = Vector2i(maxi(1, roundi(_stage.size.x * scale_value)), maxi(1, roundi(_stage.size.y * scale_value)))
 _update_labels()
 _frame_camera()
 _apply_transfer()
 _invalidate_render()

func _frame_camera() -> void:
 if not _built: return
 if reading_mode:
  _frame_reading_camera()
  return
 _camera.fov = BASE_CAMERA_FOV
 var span := _leaf_size.x * 2.15
 var aspect := maxf(0.1, _viewport.size.x / float(maxi(1, _viewport.size.y)))
 var required_half := maxf(_leaf_size.y * 0.65, span * 0.5 / aspect)
 var distance := required_half / tan(deg_to_rad(_camera.fov * 0.5)) / zoom
 # Tight depth range keeps micrometre-scale paper/print separation stable.
 var depth_radius := _leaf_size.length() * 1.2
 _camera.near = maxf(0.003, distance - depth_radius)
 _camera.far = maxf(_camera.near + 0.02, distance + depth_radius)
 var center_x := 0.0
 if not flip_active:
  if turned_leaves == 0: center_x = _leaf_size.x * 0.5
  elif turned_leaves == leaf_count: center_x = -_leaf_size.x * 0.5
 else:
  # Smooth framing during opening/closing, not an automatic model rotation.
  var source_x := _leaf_size.x * 0.5 if _flip_source == 0 else (-_leaf_size.x * 0.5 if _flip_source == leaf_count else 0.0)
  var target_x := _leaf_size.x * 0.5 if _flip_target == 0 else (-_leaf_size.x * 0.5 if _flip_target == leaf_count else 0.0)
  var fraction := _flip_angle / PI if _flip_target > _flip_source else 1 - _flip_angle / PI
  center_x = lerpf(source_x, target_x, fraction)
 _book_root.transform = Transform3D(Basis.from_euler(Vector3(_book_angles.x, _book_angles.y, 0)), Vector3.ZERO)
 var center := _book_root.transform * Vector3(center_x, 0, _thickness * 0.5)
 _camera.position = center + Vector3(0, 0, distance)
 _camera.look_at(center, Vector3.UP)

func _frame_reading_camera() -> void:
 # This remains a perspective Camera3D viewing the unchanged original leaf.
 # Optical zoom avoids crossing/intersecting paper at extreme magnification.
 var aspect := maxf(0.1, _viewport.size.x / float(maxi(1, _viewport.size.y)))
 var required_half := maxf(_leaf_size.y * 0.55, _leaf_size.x * 0.55 / aspect)
 var distance := required_half / tan(deg_to_rad(BASE_CAMERA_FOV * 0.5))
 _camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(BASE_CAMERA_FOV * 0.5)) / reading_zoom))
 _book_root.transform = Transform3D(Basis.from_euler(Vector3(_book_angles.x, _book_angles.y, 0)), Vector3.ZERO)
 var spread := spread_for(turned_leaves)
 var left := current_page == spread.x
 var local_x := _leaf_size.x * (-0.5 if left else 0.5)
 var thickness_per_leaf := _thickness / maxf(1, leaf_count)
 var local_z := thickness_per_leaf * (turned_leaves if left else leaf_count - turned_leaves)
 var center := _book_root.transform * Vector3(local_x, 0, local_z)
 var half_height := required_half / reading_zoom
 var half_view := Vector2(half_height * aspect, half_height)
 var projected_half := Vector2(absf(_book_root.basis.x.x) * _leaf_size.x + absf(_book_root.basis.y.x) * _leaf_size.y, absf(_book_root.basis.x.y) * _leaf_size.x + absf(_book_root.basis.y.y) * _leaf_size.y) * 0.5
 var limit := (projected_half - half_view + Vector2.ONE * 0.002).max(Vector2.ZERO)
 pan = pan.clamp(-limit, limit)
 center += Vector3(pan.x, -pan.y, 0)
 _camera.near = maxf(0.003, distance - _leaf_size.length() * 1.2)
 _camera.far = distance + _leaf_size.length() * 1.2
 _camera.position = center + Vector3(0, 0, distance)
 _camera.look_at(center, Vector3.UP)

func _update_labels() -> void:
 if not _built or pages.is_empty(): return
 var spread := spread_for(turned_leaves)
 var printed := "Capa · 1/%d" % pages.size() if turned_leaves == 0 else ("Contracapa · %d/%d" % [pages.size(), pages.size()] if spread.y < 0 else "Páginas %d–%d / %d" % [spread.x + 1, spread.y + 1, pages.size()])
 _status.text = "Página %d/%d · zoom %d%%" % [current_page + 1, pages.size(), roundi(reading_zoom * 100)] if reading_mode else printed + (" · virando" if flip_active else "")
 _previous.disabled = turned_leaves <= 0 and not flip_active
 _next.disabled = turned_leaves >= _max_turned() and not flip_active
 _read.disabled = flip_active or _transfer_direction != 0
 _read.tooltip_text = "Ampliar página %d" % (current_page + 1)
 _read.accessibility_name = _read.tooltip_text
 _read.visible = not reading_mode
 _previous.visible = not reading_mode
 _next.visible = not reading_mode
 _view_reset.tooltip_text = "Centralizar" if reading_mode else "Vista 3D"
 _view_reset.accessibility_name = _view_reset.tooltip_text
 _back.text = ""
 _back.tooltip_text = "Sair do zoom e conservar esta página no mesmo livreto 3D" if reading_mode else "Devolver o mesmo livreto à caixa"
 _back.accessibility_name = _back.tooltip_text
 _warning.text = ""
 _title.tooltip_text = _title.text + "\nEspessura demonstrativa, não medida · %d folhas / %d faces." % [leaf_count, pages.size()]
 _title.accessibility_description = _title.tooltip_text
 for index in _protected_pages:
  if _page_errors.has(index):
   _warning.text = str(_page_errors[index]) + " Nenhuma imagem substituta foi criada."
   break
 _warning.visible = not _warning.text.is_empty()
 var labels := reference_labels()
 _help.text = "%s / %s: páginas · %s: leitura/zoom · %s: voltar" % [labels.directions, labels.page_controls, labels.ok, labels.back]
 _help.tooltip_text = labels.priority
 if reading_mode:
  _help.text = "%s: mover · %s: zoom · %s ou %s: voltar ao livreto" % [labels.directions, labels.shoulders, labels.ok, labels.back]
 elif not labels.gamepad: _help.text += " · extensão 3D: arrastar inclina, roda aproxima"
 if flip_active: _help.text = "Direção oposta ou Esc: cancelar virada · a animação pausa quando a janela perde foco"

func reference_labels() -> Dictionary:
 var profile: Variant = host.get("input_profile") if is_instance_valid(host) else null
 var gamepad: bool = is_instance_valid(host) and host.get("input_device") == "gamepad"
 var pad_name := str(host.get("active_pad_name")) if gamepad else ""
 var family := str(profile.family(pad_name)) if gamepad and profile != null else "keyboard"
 var ok := str(profile.glyph("confirm", gamepad, pad_name)) if profile != null else ("Sul" if gamepad else "X")
 var back := str(profile.glyph("back", gamepad, pad_name)) if profile != null else ("Leste" if gamepad else "Z")
 var readable := {"ps_cross": "×", "ps_circle": "○", "ps_square": "□", "ps_triangle": "△", "south": "Sul", "east": "Leste", "west": "Oeste", "north": "Norte"}
 ok = str(readable.get(ok, ok))
 back = str(readable.get(back, back))
 var minus := "PageUp"
 var plus := "PageDown"
 var occupied: Array[int] = []
 var bindings: Dictionary = {}
 if profile != null: bindings = profile.buttons if gamepad else profile.keys
 for action in ["confirm", "back"]:
  if bindings.has(action): occupied.append(int(bindings[action]))
 var left_code: int = JOY_BUTTON_LEFT_SHOULDER if gamepad else KEY_PAGEUP
 var right_code: int = JOY_BUTTON_RIGHT_SHOULDER if gamepad else KEY_PAGEDOWN
 var arrows := ["←", "↑", "→", "↓"]
 var direction_codes := [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN] if gamepad else [KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN]
 if gamepad:
  minus = "L1" if family == "playstation" else ("LB" if family == "xbox" else "ombro esq.")
  plus = "R1" if family == "playstation" else ("RB" if family == "xbox" else "ombro dir.")
  # InputProfile's generic B-number fallback must not hide a remapped shoulder
  # or D-pad's actual meaning in this contextual help.
  var button_labels := {JOY_BUTTON_LEFT_SHOULDER: minus, JOY_BUTTON_RIGHT_SHOULDER: plus, JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_RIGHT: "→", JOY_BUTTON_DPAD_DOWN: "↓"}
  if bindings.has("confirm"): ok = str(button_labels.get(int(bindings.confirm), ok))
  if bindings.has("back"): back = str(button_labels.get(int(bindings.back), back))
 var available_shoulders: Array[String] = []
 if left_code not in occupied: available_shoulders.append(minus)
 if right_code not in occupied: available_shoulders.append(plus)
 var shoulders := "/".join(available_shoulders)
 if available_shoulders.size() == 1: shoulders += " (−)" if left_code not in occupied else " (+)"
 var pages_controls := shoulders if not shoulders.is_empty() else "botões Folha na tela"
 var zoom_controls := shoulders if not shoulders.is_empty() else "−/+ na tela"
 var available_directions: Array[String] = []
 for index in direction_codes.size():
  if int(direction_codes[index]) not in occupied: available_directions.append(arrows[index])
 var directions := "Direcional/analógico esquerdo" if gamepad else "Setas"
 if available_directions.size() < direction_codes.size():
  directions = " ".join(available_directions)
  if gamepad: directions += " / analógico esquerdo"
 return {"gamepad": gamepad, "family": family, "ok": ok, "back": back, "shoulders": zoom_controls, "page_controls": pages_controls, "directions": directions, "priority": "Confirmar e voltar têm prioridade sobre qualquer direção ou ombro para o qual forem remapeados."}

func refresh_controls() -> void:
 _update_labels()

func _apply_transfer() -> void:
 if not _built: return
 var target := Rect2(Vector2.ZERO, _stage.size)
 var frame := target
 var t := smoothstep(0, 1, _transfer)
 if _source_view_valid:
  # Start and end are real 3D rigid poses. No image warp/homography is used.
  _frame_camera()
  var target_book := _book_root.transform
  var target_camera := _camera.transform
  var target_fov := _camera.fov
  var printed_center := Vector3(_leaf_size.x * 0.5, 0, _thickness)
  var source_book := Transform3D(_source_cover_in_camera.basis, _source_cover_in_camera.origin - _source_cover_in_camera.basis * printed_center)
  _book_root.transform = source_book.interpolate_with(target_book, t)
  _camera.transform = Transform3D.IDENTITY.interpolate_with(target_camera, t)
  _camera.fov = lerpf(_source_vertical_fov, target_fov, t)
  var center_in_view := _camera.transform.affine_inverse() * (_book_root.transform * printed_center)
  var depth := maxf(0.003, -center_in_view.z)
  var radius := _leaf_size.length() * 1.2
  _camera.near = maxf(0.0001, depth - radius)
  _camera.far = maxf(_camera.near + 0.01, depth + radius)
 if _entry_bound and _transfer < 1:
  var desired := Rect2(_entry_rect.position - _stage.global_position, _entry_rect.size)
  # Uniform render scaling preserves the artwork's aspect at every frame.
  # With a captured source view, use its INITIAL projected corners, not the
  # changing interpolation pose, so the object can naturally rotate in 3D.
  var bounds := _project_source_cover() if _source_view_valid else _project_closed_book()
  var factor := minf(desired.size.x / maxf(bounds.size.x, 1), desired.size.y / maxf(bounds.size.y, 1))
  var start := Rect2(desired.get_center() - bounds.get_center() * factor, target.size * factor)
  frame = Rect2(start.position.lerp(target.position, t), start.size.lerp(target.size, t))
  frame.position.y -= sin(t * PI) * minf(54, _stage.size.y * 0.12)
 _display.position = frame.position
 _display.size = frame.size
 _shade.color.a = 0.45 + _transfer * 0.55
 if _source_view_valid: _invalidate_render()

func _project_source_cover() -> Rect2:
 var low := Vector2(INF, INF)
 var high := Vector2(-INF, -INF)
 var focal := _viewport.size.y / (2.0 * tan(deg_to_rad(_source_vertical_fov * 0.5)))
 var screen_scale := _stage.size / Vector2(_viewport.size)
 for x in [-_leaf_size.x * 0.5, _leaf_size.x * 0.5]:
  for y in [-_leaf_size.y * 0.5, _leaf_size.y * 0.5]:
   var point := _source_cover_in_camera * Vector3(x, y, 0)
   var projected := (Vector2(_viewport.size) * 0.5 + Vector2(point.x, -point.y) * focal / -point.z) * screen_scale
   low = low.min(projected)
   high = high.max(projected)
 return Rect2(low, (high - low).max(Vector2.ONE))

func _project_closed_book() -> Rect2:
 var low := Vector2(INF, INF)
 var high := Vector2(-INF, -INF)
 var screen_scale := _stage.size / Vector2(_viewport.size)
 for x in [0.0, _leaf_size.x]:
  for y in [-_leaf_size.y * 0.5, _leaf_size.y * 0.5]:
   var point := _book_root.global_transform * Vector3(x, y, _thickness)
   var projected := _camera.unproject_position(point) * screen_scale
   low = low.min(projected)
   high = high.max(projected)
 return Rect2(low, (high - low).max(Vector2.ONE))

func _finish_transfer() -> void:
 var direction := _transfer_direction
 _transfer_direction = 0
 _apply_transfer()
 if direction < 0: _complete_close()
 elif direction > 0:
  extracted.emit(item_id)
  _update_labels()
  _apply_activity()

func _invalidate_render() -> void:
 if is_instance_valid(_viewport) and visible and _window_focused:
  _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _apply_activity() -> void:
 if not is_instance_valid(_viewport): return
 _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if visible and _window_focused else SubViewport.UPDATE_DISABLED

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
  _window_focused = false
  cancel_drag()
  _apply_activity()
 elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
  _window_focused = true
  cancel_drag()
  _block_held_inputs()
  _apply_activity()

func _process(delta: float) -> void:
 if not visible: return
 if get_viewport().get_visible_rect().size != _layout_size: layout()
 if not _window_focused: return
 if reading_mode:
  var reading_delta := clampf(delta, 0, 0.05)
  if pan_axis != Vector2.ZERO: _pan_reading(pan_axis * _leaf_size.y * reading_delta * 0.9 / reading_zoom)
  if not is_zero_approx(zoom_axis): change_zoom(zoom_axis * reading_delta * 1.6)
  return
 var bounded := clampf(delta, 0, 0.05)
 if _transfer_direction != 0:
  _transfer = clampf(_transfer + bounded / TRANSFER_SECONDS * _transfer_direction, 0, 1)
  _apply_transfer()
  if _transfer <= 0 or _transfer >= 1: _finish_transfer()
  return
 if flip_active:
  _flip_elapsed += bounded
  flip_progress = clampf(_flip_elapsed / _flip_duration, 0, 1)
  _flip_angle = lerpf(_flip_start_angle, _flip_end_angle, smoothstep(0, 1, flip_progress))
  _update_turn_mesh()
  if flip_progress >= 1: _finish_flip()
 if _rotate_axis != Vector2.ZERO: _rotate(_rotate_axis * bounded * 0.9)
 if not is_zero_approx(_zoom_axis): change_zoom(_zoom_axis * bounded * 0.8)

func _rotate(amount: Vector2) -> void:
 if not amount.is_finite(): return
 _book_angles.x = clampf(_book_angles.x + amount.y, -0.62, 0.62)
 _book_angles.y = clampf(_book_angles.y + amount.x, -0.65, 0.65)
 _frame_camera()
 _invalidate_render()

func cancel_drag() -> void:
 _reference_directions.clear()
 _reference_zooms.clear()
 _reference_stick = Vector2.ZERO
 pan_axis = Vector2.ZERO
 zoom_axis = 0
 dragging = false
 _drag_button = 0
 _clicked_button = null
 _rotate_axis = Vector2.ZERO
 _zoom_axis = 0
 _triggers = Vector2.ZERO
 _axis_ready.clear()
 _axis_latched.clear()
 for device in Input.get_connected_joypads():
  for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
   if absf(Input.get_joy_axis(device, axis)) < 0.22: _axis_ready["%d:%d" % [device, axis]] = true

func _block_held_inputs() -> void:
 _held.clear()
 var codes: Array = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN, KEY_PLUS, KEY_EQUAL, KEY_MINUS, KEY_ESCAPE, KEY_R, KEY_Z, KEY_TAB, KEY_ENTER, KEY_SPACE, KEY_L]
 var profile: Variant = host.get("input_profile") if is_instance_valid(host) else null
 if profile != null and profile.get("keys") is Dictionary: codes.append_array(profile.keys.values())
 for code in codes:
  if Input.is_physical_key_pressed(int(code)) or Input.is_key_pressed(int(code)): _held["k:%d" % int(code)] = true
 for device in Input.get_connected_joypads():
  for code in JOY_BUTTON_MAX:
   if Input.is_joy_button_pressed(device, code): _held["j:%d:%d" % [device, code]] = true

func _button_at(point: Vector2) -> Button:
 for button in _buttons:
  if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(point): return button
 return null

func _cycle_focus(reverse: bool) -> void:
 var available: Array[Button] = []
 for button in _buttons:
  if button.is_visible_in_tree() and not button.disabled: available.append(button)
 if available.is_empty(): return
 var index := available.find(get_viewport().gui_get_focus_owner())
 available[posmod(index + (-1 if reverse else 1), available.size())].grab_focus()

func handle_event(event: InputEvent) -> bool:
 if not visible: return false
 if not _window_focused: return true
 refresh_controls()
 if reading_mode: return _handle_reading_event(event)
 var token := ""
 if event is InputEventKey:
  var code: int = event.physical_keycode if event.physical_keycode else event.keycode
  token = "k:%d" % code
  if not event.pressed:
   _held.erase(token)
   return true
  if event.echo or _held.has(token): return true
  _held[token] = true
 elif event is InputEventJoypadButton:
  token = "j:%d:%d" % [event.device, event.button_index]
  if not event.pressed:
   _held.erase(token)
   return true
  if _held.has(token): return true
  _held[token] = true
 var profile: Variant = host.get("input_profile") if is_instance_valid(host) else null
 var action := str(profile.action_for(event)) if profile != null and profile.has_method("action_for") else ""
 var code: int = (event.physical_keycode if event.physical_keycode else event.keycode) if event is InputEventKey else 0
 if action == "back" or code == KEY_ESCAPE or (profile == null and code == KEY_Z):
  if flip_active: cancel_flip()
  else: close()
  return true
 if _transfer_direction != 0: return true
 if action == "confirm" or (profile == null and code == KEY_X):
  enter_reading_mode()
  return true
 if event is InputEventKey and code in [KEY_ENTER, KEY_SPACE]:
  var focus := get_viewport().gui_get_focus_owner()
  if focus is Button and focus in _buttons and focus.is_visible_in_tree() and not focus.disabled: focus.pressed.emit()
  return true
 if event is InputEventKey:
  if code in [KEY_LEFT, KEY_UP, KEY_PAGEUP]: navigate_page(-1)
  elif code in [KEY_RIGHT, KEY_DOWN, KEY_PAGEDOWN]: navigate_page(1)
  elif code in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]: change_zoom(0.15)
  elif code in [KEY_MINUS, KEY_KP_SUBTRACT]: change_zoom(-0.15)
  elif code == KEY_TAB: _cycle_focus(event.shift_pressed)
 elif event is InputEventJoypadButton:
  if profile == null and event.button_index == JOY_BUTTON_B: close()
  elif profile == null and event.button_index == JOY_BUTTON_A: enter_reading_mode()
  elif event.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_LEFT_SHOULDER]: navigate_page(-1)
  elif event.button_index in [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_RIGHT_SHOULDER]: navigate_page(1)
 elif event is InputEventJoypadMotion: _handle_axis(event)
 elif event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_LEFT:
   if event.pressed:
    _clicked_button = _button_at(event.position)
    if _clicked_button: _clicked_button.grab_focus()
    elif _stage.get_global_rect().has_point(event.position):
     var spread := spread_for(turned_leaves)
     var left: bool = event.position.x < _stage.get_global_rect().get_center().x
     var selected := spread.x if left else spread.y
     if selected >= 0: current_page = selected
     if event.double_click:
      enter_reading_mode()
     else:
      dragging = true
      _drag_button = MOUSE_BUTTON_LEFT
   else:
    var clicked := _clicked_button
    cancel_drag()
    if is_instance_valid(clicked) and clicked == _button_at(event.position): clicked.pressed.emit()
  elif event.pressed and _stage.get_global_rect().has_point(event.position):
   if event.button_index == MOUSE_BUTTON_WHEEL_UP: change_zoom(0.15)
   elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: change_zoom(-0.15)
 elif event is InputEventMouseMotion and dragging:
  if event.button_mask & MOUSE_BUTTON_MASK_LEFT: _rotate(event.relative.limit_length(200) * 0.005)
  else: cancel_drag()
 return true

func _arm_reference_device(device: int, left_stick: Vector2) -> void:
 if absf(left_stick.x) < 0.22: _axis_ready["%d:%d" % [device, JOY_AXIS_LEFT_X]] = true
 if absf(left_stick.y) < 0.22: _axis_ready["%d:%d" % [device, JOY_AXIS_LEFT_Y]] = true

func _update_reference_motion() -> void:
 pan_axis = _reference_stick
 for value in _reference_directions.values(): pan_axis += value
 pan_axis = pan_axis.limit_length(1)
 zoom_axis = 0
 for value in _reference_zooms.values(): zoom_axis += float(value)
 zoom_axis = clampf(zoom_axis, -1, 1)

func _handle_reading_event(event: InputEvent) -> bool:
 if event is InputEventMouse:
  _handle_reading_mouse(event)
  return true
 if event is InputEventJoypadMotion:
  if not is_finite(event.axis_value) or event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]: return true
  var value := clampf(event.axis_value, -1, 1)
  var axis_key := "%d:%d" % [event.device, event.axis]
  if absf(value) < 0.22: _axis_ready[axis_key] = true
  if not _axis_ready.get(axis_key, false): return true
  if event.axis == JOY_AXIS_LEFT_X: _reference_stick.x = value if absf(value) > 0.22 else 0.0
  else: _reference_stick.y = value if absf(value) > 0.22 else 0.0
  _update_reference_motion()
  return true
 var token := ""
 var code := 0
 if event is InputEventKey:
  code = event.physical_keycode if event.physical_keycode else event.keycode
  token = "k:%d" % code
  if not event.pressed:
   _held.erase(token)
   _reference_directions.erase(token)
   _reference_zooms.erase(token)
   _update_reference_motion()
   return true
  if event.echo or _held.has(token): return true
 elif event is InputEventJoypadButton:
  token = "j:%d:%d" % [event.device, event.button_index]
  if not event.pressed:
   _held.erase(token)
   _reference_directions.erase(token)
   _reference_zooms.erase(token)
   _update_reference_motion()
   return true
  if _held.has(token): return true
 else: return true
 _held[token] = true
 var profile: Variant = host.get("input_profile") if is_instance_valid(host) else null
 var action := str(profile.action_for(event)) if profile != null and profile.has_method("action_for") else ""
 if action in ["confirm", "back"] or code == KEY_ESCAPE or (profile == null and code in [KEY_X, KEY_Z]):
  exit_reading_mode()
  return true
 if event is InputEventKey and code in [KEY_ENTER, KEY_SPACE]:
  var focus := get_viewport().gui_get_focus_owner()
  if focus is Button and focus in _buttons and focus.is_visible_in_tree() and not focus.disabled: focus.pressed.emit()
  return true
 if event is InputEventKey:
  if code == KEY_LEFT: _reference_directions[token] = Vector2.LEFT
  elif code == KEY_RIGHT: _reference_directions[token] = Vector2.RIGHT
  elif code == KEY_UP: _reference_directions[token] = Vector2.UP
  elif code == KEY_DOWN: _reference_directions[token] = Vector2.DOWN
  elif code == KEY_PAGEUP: _reference_zooms[token] = -1.0
  elif code == KEY_PAGEDOWN: _reference_zooms[token] = 1.0
  elif code == KEY_TAB: _cycle_focus(event.shift_pressed)
 elif event is InputEventJoypadButton:
  if profile == null and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B]:
   exit_reading_mode()
   return true
  if event.button_index == JOY_BUTTON_LEFT_SHOULDER: _reference_zooms[token] = -1.0
  elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER: _reference_zooms[token] = 1.0
  elif event.button_index == JOY_BUTTON_DPAD_LEFT: _reference_directions[token] = Vector2.LEFT
  elif event.button_index == JOY_BUTTON_DPAD_RIGHT: _reference_directions[token] = Vector2.RIGHT
  elif event.button_index == JOY_BUTTON_DPAD_UP: _reference_directions[token] = Vector2.UP
  elif event.button_index == JOY_BUTTON_DPAD_DOWN: _reference_directions[token] = Vector2.DOWN
 _update_reference_motion()
 return true

func _handle_reading_mouse(event: InputEventMouse) -> void:
 if event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_LEFT:
   if event.pressed:
    _clicked_button = _button_at(event.position)
    if _clicked_button: _clicked_button.grab_focus()
    else: dragging = _stage.get_global_rect().has_point(event.position)
   else:
    var clicked := _clicked_button
    cancel_drag()
    if is_instance_valid(clicked) and clicked == _button_at(event.position): clicked.pressed.emit()
  elif event.pressed and _stage.get_global_rect().has_point(event.position):
   if event.button_index == MOUSE_BUTTON_WHEEL_UP: change_zoom(0.15)
   elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: change_zoom(-0.15)
 elif event is InputEventMouseMotion and dragging:
  if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
   var world_per_pixel := _leaf_size.y * 1.1 / maxf(1, _stage.size.y) / reading_zoom
   _pan_reading(-event.relative.limit_length(8192) * world_per_pixel)
  else: cancel_drag()

func _handle_axis(event: InputEventJoypadMotion) -> void:
 if not is_finite(event.axis_value) or event.axis not in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]: return
 var value := clampf(event.axis_value, -1, 1)
 var key := "%d:%d" % [event.device, event.axis]
 if absf(value) < 0.22:
  _axis_ready[key] = true
  _axis_latched[key] = false
 if not _axis_ready.get(key, false): return
 if absf(value) > 0.65 and not _axis_latched.get(key, false):
  navigate_page(1 if value > 0 else -1)
  _axis_latched[key] = true
  _axis_ready[key] = true

func get_report() -> Dictionary:
 var retained: Array[int] = []
 for index in cache: retained.append(int(index))
 retained.sort()
 return {"open": visible, "item_id": item_id, "mode": "booklet_3d_zoom" if reading_mode else "booklet_3d", "face_count": pages.size(), "leaf_count": leaf_count, "turned_leaves": turned_leaves, "visible_faces": spread_for(turned_leaves), "current_page": current_page, "page_size_m": _leaf_size, "thickness_m": _thickness, "thickness_is_measured": false, "source_bound": not _source_report.is_empty(), "source_view_matched": _source_view_valid, "source_view_note": _source_view_limit, "source_geometry_proxy": is_instance_valid(_closed_proxy), "transfer_active": _transfer_direction != 0, "flip_active": flip_active, "flip_leaf": _flip_leaf if flip_active else -1, "flip_angle": _flip_angle, "cache_indices": retained, "cache_bytes": cache_bytes, "cache_max_bytes": _cache_budget(), "runtime_max_edge": READING_MAX_EDGE if reading_mode else RUNTIME_MAX_EDGE, "reading_zoom": reading_zoom, "reading_pan": pan, "viewport_size": _viewport.size if is_instance_valid(_viewport) else Vector2i.ZERO, "originals_modified": false, "flat_reader_instantiated": false, "window_focused": _window_focused}
