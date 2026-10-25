extends SceneTree
## Synthetic image fixtures only: no game media or private paths in this test.
const Reader = preload("res://cosmic/manual_book_reader.gd")
const Profile = preload("res://cosmic/input_profile.gd")
class Host extends Node:
 var input_profile = Profile.new()
 var input_device := "keyboard"
 var active_pad_name := ""
 var chakra: Font
 var orbitron: Font
class SourceBook extends RefCounted:
 var root: Node3D
 var paper: MeshInstance3D
 var cover: MeshInstance3D
 var size_m := Vector2(0.12, 0.18)
 var texture: Texture2D
 func create(parent: Node, image_texture: Texture2D) -> void:
  texture = image_texture
  root = Node3D.new()
  parent.add_child(root)
  paper = MeshInstance3D.new()
  paper.name = "UnprintedPaperVolume"
  var volume := BoxMesh.new()
  volume.size = Vector3(size_m.x, 0.000798, size_m.y)
  paper.mesh = volume
  paper.position.y = 0.000001
  root.add_child(paper)
  cover = MeshInstance3D.new()
  cover.name = "ValidatedFirstPage"
  var quad := QuadMesh.new()
  quad.size = size_m
  cover.mesh = quad
  cover.basis = Basis(Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN)
  cover.position.y = -0.0004
  var material := StandardMaterial3D.new()
  material.albedo_texture = texture
  cover.material_override = material
  root.add_child(cover)
 func get_report() -> Dictionary:
  return {"configured": is_instance_valid(root), "item_id": "qa_booklet", "page_size_m": size_m, "thickness_m": 0.0008, "cover_source": "host_supplied_manual_pages_0_no_fallback", "thickness_is_measured": false}

var assertions := 0
var failures: Array[String] = []
var reader: Control
var fixture_dir := "/tmp/retropass-booklet-test-%d" % OS.get_process_id()
var fixture_paths: Array[String] = []
var closed_count := 0
var max_handoff_error := 0.0

func check(condition: bool, description: String) -> void:
 assertions += 1
 if not condition:
  failures.append(description)
  push_error(description)

func _initialize() -> void:
 run.call_deferred()

func fixture(number: int, size_value: Vector2i = Vector2i(128, 192)) -> String:
 var image := Image.create(size_value.x, size_value.y, false, Image.FORMAT_RGBA8)
 image.fill(Color.WHITE if number == 1 else Color.from_hsv(number / 32.0, 0.7, 0.75))
 if number != 1:
  image.fill_rect(Rect2i(0, 0, 16, 18), Color.RED)
  image.fill_rect(Rect2i(size_value.x - 16, 0, 16, 18), Color.GREEN)
 var path := fixture_dir.path_join("synthetic-%02d.png" % number)
 check(image.save_png(path) == OK, "Synthetic fixture created outside repository")
 fixture_paths.append(path)
 return path

func key(code: int, pressed: bool = true, echo: bool = false) -> InputEventKey:
 var event := InputEventKey.new()
 event.physical_keycode = code
 event.keycode = code
 event.pressed = pressed
 event.echo = echo
 return event

func tap(code: int) -> void:
 reader.handle_event(key(code))
 reader.handle_event(key(code, false))

func axis(code: int, value: float) -> InputEventJoypadMotion:
 var event := InputEventJoypadMotion.new()
 event.axis = code
 event.axis_value = value
 return event

func settle() -> void:
 for step in 50: reader._process(0.05)

func source_corners(source: SourceBook, camera: Camera3D) -> PackedVector2Array:
 var result := PackedVector2Array()
 for corner in [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]:
  var point: Vector3 = source.cover.global_transform * Vector3(corner.x * source.size_m.x, corner.y * source.size_m.y, 0)
  result.append(camera.unproject_position(point))
 return result

func reader_corners() -> PackedVector2Array:
 var result := PackedVector2Array()
 for corner in [Vector2(0, 0.5), Vector2(1, 0.5), Vector2(1, -0.5), Vector2(0, -0.5)]:
  var point: Vector3 = reader._book_root.global_transform * Vector3(corner.x * reader._leaf_size.x, corner.y * reader._leaf_size.y, reader._thickness)
  var projected: Vector2 = reader._camera.unproject_position(point)
  result.append(reader._display.global_position + projected * reader._display.size / Vector2(reader._viewport.size))
 return result

func cache_ok() -> void:
 check(reader.cache.size() <= reader._cache_page_limit(), "Booklet texture count bounded")
 check(reader.cache_bytes <= reader._cache_budget(), "Booklet byte estimate including mipmaps bounded")
 var sum := 0
 for index in reader.cache:
  var entry: Dictionary = reader.cache[index]
  sum += int(entry.bytes)
  var edge_limit: int = Reader.READING_MAX_EDGE if reader.reading_mode and int(index) == reader.current_page else Reader.RUNTIME_MAX_EDGE
  check(entry.runtime_size.x <= edge_limit and entry.runtime_size.y <= edge_limit, "Runtime LOD edge bounded per visible selected face")
 check(sum == reader.cache_bytes, "Texture accounting includes all cache entries")
 if reader.reading_mode:
  check(reader.cache.size() <= 2 and reader.get_report().mode == "booklet_3d_zoom", "Reading stays 3D and retains only the two visible faces")

func run() -> void:
 DirAccess.make_dir_recursive_absolute(fixture_dir)
 var host := Host.new()
 root.add_child(host)
 reader = Reader.new()
 host.add_child(reader)
 reader.configure(host)
 reader.closed.connect(func(): closed_count += 1)
 await process_frame
 check(not reader.availability({"id": "missing"}), "Missing manual cannot create booklet")
 check(not reader.open_item({"id": "missing"}), "Missing manual leaves reader closed")
 var paths: Array[String] = []
 for number in 32: paths.append(fixture(number))
 var item := {"id": "qa_booklet", "title": "SYNTHETIC QA · NOT A GAME MANUAL", "manual_item_id": "qa_booklet", "manual_pages": paths}
 check(reader.availability(item), "Bounded local pages eligible")
 check(reader.cache.is_empty(), "Availability does not decode images")
 check(reader.open_item(item), "Standalone 3D reader opens synthetic fixture")
 check(reader.leaf_count == 16, "32 ordered faces produce exactly 16 physical leaves")
 check(reader.spread_for(0) == Vector2i(-1, 0), "Closed book shows original first-page cover")
 check(reader.spread_for(1) == Vector2i(1, 2), "First turn reveals verso 1 then front 2")
 check(reader.spread_for(16) == Vector2i(31, -1), "Final outside back face is 31")
 check(reader.current_page == 0 and reader.turned_leaves == 0, "Initial pose is closed, never an automatic turn")
 check(reader._right_page.get_meta("page_index") == 0, "Initial face binds original page index")
 check(reader._right_page.mesh.get_surface_count() == 1, "Printed page is real 3D geometry")
 for reverse in [false, true]:
  var sample := ArrayMesh.new()
  reader._surface(sample, 0.003, reverse)
  var arrays: Array = sample.surface_get_arrays(0)
  var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
  var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
  var triangles: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
  var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
  for triangle in range(0, triangles.size(), 3):
   var ia := triangles[triangle]
   var ib := triangles[triangle + 1]
   var ic := triangles[triangle + 2]
   var cross := (positions[ib] - positions[ia]).cross(positions[ic] - positions[ia])
   check(cross.dot(normals[ia]) < 0, "Printed triangles use Godot clockwise winding, not hidden reverse culling")
  check(is_equal_approx(uv[0].x, 1.0 if reverse else 0.0), "Verso UV remains correct while fixing winding")
 check("unshaded" in reader._page_shader.code, "Print contrast is not washed by summed environmental illumination")
 check(not reader._warning.visible, "Demonstration disclosure stays in tooltip unless a real page error exists")
 cache_ok()
 reader.navigate(1)
 check(reader.flip_active and reader._turn_front.get_meta("page_index") == 0 and reader._turn_back.get_meta("page_index") == 1, "Turning leaf owns paired original front/back faces")
 reader._process(0.05)
 var paused_angle: float = reader._flip_angle
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
 reader._process(5)
 check(reader._flip_angle == paused_angle, "Window focus loss freezes animation exactly")
 reader.handle_event(key(KEY_RIGHT))
 check(reader.turned_leaves == 0, "Unfocused reader consumes without navigation")
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
 reader.navigate(-1)
 settle()
 check(not reader.flip_active and reader.turned_leaves == 0, "Opposite direction reverses/cancels turn to source")
 reader.navigate(1)
 settle()
 check(reader.turned_leaves == 1 and reader.current_page == 2, "Completed first turn selects real next front")
 check(reader._left_page.get_meta("page_index") == 1 and reader._right_page.get_meta("page_index") == 2, "Spread retains left/right order")
 var blank: Image = reader.cache[1].texture.get_image()
 check(blank.get_pixel(30, 30).is_equal_approx(Color.WHITE), "Original blank PDF face retained, never removed/replaced")
 cache_ok()
 reader.set_reduced_motion(true)
 for leaves in range(2, 17):
  reader.navigate(1)
  check(not reader.flip_active and reader.turned_leaves == leaves, "Reduced-motion turns are instantaneous and ordered")
  check(reader.spread_for(leaves).x == leaves * 2 - 1, "All reverse faces remain sequential")
  cache_ok()
 reader.navigate(1)
 check(reader.turned_leaves == 16, "Forward edge clamps, does not wrap")
 for leaves in range(15, -1, -1):
  reader.navigate(-1)
  check(reader.turned_leaves == leaves, "Backward turns reverse exact leaf sequence")
 reader.navigate(-1)
 check(reader.turned_leaves == 0, "Backward edge clamps")
 tap(KEY_RIGHT)
 check(reader.turned_leaves == 1 and reader.current_page == 1, "One reference input advances to first verso without skipping it")
 reader.handle_event(key(KEY_RIGHT))
 for repeat in 20: reader.handle_event(key(KEY_RIGHT, true, true))
 check(reader.turned_leaves == 1 and reader.current_page == 2, "Next reference input selects right face, echo cannot race through pages")
 reader.handle_event(key(KEY_RIGHT, false))
 reader.handle_event(axis(JOY_AXIS_LEFT_X, 1))
 check(reader.current_page == 2, "Analog held on entry waits for neutral")
 reader.handle_event(axis(JOY_AXIS_LEFT_X, 0))
 reader.handle_event(axis(JOY_AXIS_LEFT_X, 1))
 check(reader.turned_leaves == 2 and reader.current_page == 3, "Neutral-to-edge analog command advances one face")
 for repeat in 10: reader.handle_event(axis(JOY_AXIS_LEFT_X, 1))
 check(reader.current_page == 3, "Held analog does not repeat")
 reader.handle_event(key(KEY_PAGEDOWN))
 var before_focus: int = reader.current_page
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
 # Deliberately omit the key release that happened outside the application.
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
 reader.handle_event(key(KEY_PAGEDOWN))
 check(reader.current_page == before_focus + 1, "First deliberate press after lost off-window release is not swallowed")
 reader.handle_event(key(KEY_PAGEDOWN, false))
 host.input_profile.rebind("inspect", JOY_BUTTON_LEFT_SHOULDER, true)
 var shoulder := InputEventJoypadButton.new()
 shoulder.button_index = JOY_BUTTON_LEFT_SHOULDER
 shoulder.pressed = true
 var before_shoulder: int = reader.current_page
 reader.handle_event(shoulder)
 check(reader.current_page == before_shoulder - 1, "Unrelated inspect remap cannot swallow manual shoulder navigation")
 shoulder.pressed = false
 reader.handle_event(shoulder)
 host.input_profile.rebind("inspect", JOY_BUTTON_X, true)
 reader._next.grab_focus()
 var before_toolbar: int = reader.turned_leaves
 tap(KEY_ENTER)
 check(reader.turned_leaves == before_toolbar + 1, "Enter activates a keyboard-focused toolbar button as explicit UI extension")
 for repeat in 30: reader.change_zoom(100)
 check(reader.zoom == Reader.ZOOM_MAX, "3D zoom bounded above")
 reader.change_zoom(NAN)
 check(reader.zoom == Reader.ZOOM_MAX, "Invalid zoom ignored")
 for repeat in 30: reader.change_zoom(-100)
 check(reader.zoom == Reader.ZOOM_MIN, "3D zoom bounded below")
 reader._rotate(Vector2(1e10, -1e10))
 check(absf(reader._book_angles.x) <= 0.6201 and absf(reader._book_angles.y) <= 0.6501, "Voluntary tilt bounded, no runaway rotation")
 var resting_angles: Vector2 = reader._book_angles
 settle()
 check(reader._book_angles == resting_angles, "Idle causes no automatic model rotation")
 var same_world: Node3D = reader._book_root
 var same_viewport: SubViewport = reader._viewport
 var same_display_texture: Texture2D = reader._display.texture
 var same_left_mesh: Mesh = reader._left_page.mesh
 var same_right_mesh: Mesh = reader._right_page.mesh
 var before_reading_pose: Transform3D = reader._book_root.transform
 var before_reading_camera: Transform3D = reader._camera.transform
 var reading_page: int = reader.current_page
 var reading_spread: int = reader.turned_leaves
 reader.enter_reading_mode()
 check(reader.reading_mode and reader._book_root == same_world and reader._viewport == same_viewport, "Reading zoom stays inside the exact same 3D world and viewport")
 check(reader._display.texture == same_display_texture and reader._left_page.mesh == same_left_mesh and reader._right_page.mesh == same_right_mesh, "Reading zoom never swaps to a flat image or replaces the physical page meshes")
 check(reader._book_root.transform == before_reading_pose and not reader.get_report().flat_reader_instantiated, "Book geometry and pose remain unchanged; no 2D reader is instantiated")
 check(reader._camera.fov < Reader.BASE_CAMERA_FOV and reader._camera.attributes == null, "Reading is a real Camera3D lens zoom with no DOF blur attributes")
 reader.handle_event(key(KEY_RIGHT))
 reader._process(0.05)
 reader.handle_event(key(KEY_RIGHT, false))
 check(reader.current_page == reading_page, "RetroBat zoom layer pans without changing the original face")
 reader.handle_event(key(KEY_PAGEDOWN))
 reader._process(0.05)
 check(reader.reading_zoom > 1.15 and reader.zoom_axis > 0, "RetroBat PageDown zooms the 3D camera continuously while held")
 reader.handle_event(key(KEY_PAGEDOWN, false))
 check(reader.zoom_axis == 0, "RetroBat zoom release stops immediately")
 reader._axis_ready.clear()
 reader._arm_reference_device(77, Vector2.ZERO)
 var initial_vertical := axis(JOY_AXIS_LEFT_Y, 1)
 initial_vertical.device = 77
 reader.handle_event(initial_vertical)
 check(reader.pan_axis.y == 1, "Initially neutral left Y acts on first deliberate vertical movement")
 initial_vertical.axis_value = 0
 reader.handle_event(initial_vertical)
 reader.handle_event(key(KEY_PAGEDOWN))
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
 reader.handle_event(key(KEY_PAGEDOWN))
 check(reader.zoom_axis > 0, "3D zoom rebuilds held inputs after lost off-window release")
 reader.handle_event(key(KEY_PAGEDOWN, false))
 host.input_profile.rebind("inspect", JOY_BUTTON_LEFT_SHOULDER, true)
 shoulder.pressed = true
 reader.handle_event(shoulder)
 check(reader.zoom_axis < 0, "Unrelated inspect remap cannot swallow zoom-out shoulder")
 shoulder.pressed = false
 reader.handle_event(shoulder)
 host.input_profile.rebind("inspect", JOY_BUTTON_X, true)
 reader._zoom_in.grab_focus()
 var ui_zoom: float = reader.reading_zoom
 tap(KEY_SPACE)
 check(reader.reading_mode and reader.reading_zoom > ui_zoom, "Space activates focused 3D zoom button without changing native confirm behavior")
 reader.handle_event(key(KEY_R))
 reader.handle_event(key(KEY_R, false))
 check(reader.reading_zoom > 1, "No invented native reset action in RetroBat zoom layer")
 reader.handle_event(axis(JOY_AXIS_RIGHT_X, 0))
 reader.handle_event(axis(JOY_AXIS_RIGHT_X, 1))
 check(reader.pan_axis == Vector2.ZERO, "Right stick is not an invented RetroBat pan mapping")
 reader.handle_event(axis(JOY_AXIS_LEFT_X, 0))
 reader.handle_event(axis(JOY_AXIS_LEFT_X, 1))
 check(reader.pan_axis.x == 1, "RetroBat left stick pans the same 3D page")
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
 check(reader.pan_axis == Vector2.ZERO and reader.zoom_axis == 0, "3D zoom focus loss clears held pan/zoom")
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
 reader.change_zoom(100)
 reader._pan_reading(Vector2(1e20, -1e20))
 check(reader.reading_zoom == Reader.READING_ZOOM_MAX and reader.pan.is_finite() and reader.pan.length() < 0.5, "Extreme 3D reading zoom and pan remain bounded")
 check(reader._camera.near > 0 and reader._camera.far > reader._camera.near, "Reading camera retains a valid tight depth range")
 cache_ok()
 tap(KEY_X)
 check(not reader.reading_mode and reader.current_page == reading_page and reader.turned_leaves == reading_spread, "Native confirm returns to the exact same physical spread and selected face")
 check(reader._book_root.transform == before_reading_pose and reader._camera.transform.is_equal_approx(before_reading_camera), "Exiting reading restores original book pose and camera framing")
 check(reader._left_page.mesh == same_left_mesh and reader._right_page.mesh == same_right_mesh and reader._viewport == same_viewport, "Exit preserves all existing 3D page meshes and viewport identity")
 cache_ok()
 reader.close()
 check(not reader.visible and reader.cache.is_empty() and closed_count == 1, "Closing returns once and clears local textures")
 check(reader.open_item(item), "Reopen for per-face accessibility walk")
 for face in range(1, 32):
  reader.navigate_page(1)
  check(reader.current_page == face, "Every original face reachable without mouse")
 for face in range(30, -1, -1):
  reader.navigate_page(-1)
  check(reader.current_page == face, "Every original face reachable in reverse")
 host.input_device = "gamepad"
 host.active_pad_name = "DualSense"
 reader.refresh_controls()
 check("×" in reader._help.text and "○" in reader._help.text and "L1/R1" in reader._help.text and "ps_cross" not in reader._help.text, "PlayStation help uses readable correct-family symbols")
 host.active_pad_name = "Xbox Wireless Controller"
 reader.refresh_controls()
 check(reader.reference_labels().ok == "A" and reader.reference_labels().back == "B" and "LB/RB" in reader._help.text, "Xbox help uses A/B and shoulder labels")
 host.input_device = "keyboard"
 reader.refresh_controls()
 check("PageUp/PageDown" in reader._help.text and reader.reference_labels().ok == "X" and reader.reference_labels().back == "Z", "Keyboard help follows configured Windows reference profile")
 host.input_profile.rebind("confirm", KEY_PAGEUP, false)
 reader.refresh_controls()
 check(reader.reference_labels().shoulders == "PageDown (+)", "Confirm mapped to PageUp removes its false zoom/navigation promise")
 host.input_profile.rebind("back", KEY_LEFT, false)
 reader.refresh_controls()
 check("←" not in reader.reference_labels().directions, "Back mapped to Left removes that false pan/page promise")
 host.input_profile.rebind("back", KEY_PAGEDOWN, false)
 reader.refresh_controls()
 check(reader.reference_labels().shoulders == "−/+ na tela" and reader.reference_labels().page_controls == "botões Folha na tela", "Both consumed page controls offer honest on-screen alternatives by mode")
 host.input_profile.rebind("confirm", KEY_X, false)
 host.input_profile.rebind("back", KEY_Z, false)
 host.input_device = "gamepad"
 host.active_pad_name = "DualSense"
 host.input_profile.rebind("confirm", JOY_BUTTON_LEFT_SHOULDER, true)
 reader.refresh_controls()
 check(reader.reference_labels().ok == "L1" and reader.reference_labels().shoulders == "R1 (+)", "Remapped PlayStation shoulder is labeled as confirm, not false zoom-out")
 host.input_profile.rebind("back", JOY_BUTTON_DPAD_UP, true)
 reader.refresh_controls()
 check("↑" not in reader.reference_labels().directions and reader.reference_labels().back == "↑", "Remapped D-pad direction only appears as back, while left stick remains available")
 host.input_profile.rebind("confirm", JOY_BUTTON_A, true)
 host.input_profile.rebind("back", JOY_BUTTON_B, true)
 host.input_device = "keyboard"
 reader.refresh_controls()
 reader.finish_close()
 # Exact canonical closed-source geometry and source visibility round trip.
 var source := SourceBook.new()
 var source_image := Image.load_from_file(paths[0])
 source.create(host, ImageTexture.create_from_image(source_image))
 var original_transform := source.root.transform
 check(reader.bind_source_book(source, Rect2(40, 60, 120, 180)), "Canonical source booklet binds by identity and projected origin")
 reader.set_reduced_motion(false)
 check(reader.open_item(item), "Bound-source booklet opens")
 check(not source.root.visible and reader._closed_proxy != null, "Exact closed geometry proxy replaces only original source visibility")
 check(reader._leaf_size == source.size_m and is_equal_approx(reader._thickness, 0.0008), "Reader derives dimensions and demonstration thickness from source")
 check(reader.get_report().source_geometry_proxy and reader.get_report().source_bound, "Report identifies same-source geometry")
 check(reader._transfer_direction == 1, "Projected source-to-reader transfer begins")
 check(is_equal_approx(reader._display.size.x / reader._display.size.y, reader._stage.size.x / reader._stage.size.y), "Transfer proxy scales uniformly, never squeezing the cover aspect")
 settle()
 check(reader._transfer == 1 and reader._transfer_direction == 0, "Extraction finishes without automatic page turn")
 reader.close()
 check(reader.visible and reader._transfer_direction == -1, "Return uses reverse projected transfer")
 settle()
 check(not reader.visible and source.root.visible and source.root.transform == original_transform, "Return restores source visibility without moving case geometry")
 check(closed_count == 3, "Animated close emits exactly once")
 check(reader.bind_source_book(source, Rect2(40, 60, 120, 180)), "Source binds for interrupted extraction")
 check(reader.open_item(item), "Interrupted extraction opens")
 check(not source.root.visible and reader._transfer_direction == 1, "Extraction owns hidden original")
 reader.finish_close()
 check(not reader.visible and source.root.visible and reader.cache.is_empty(), "Synchronous teardown during extraction restores original and releases cache")
 check(reader.bind_source_book(source), "Source binds for interrupted zoom")
 check(reader.open_item(item), "Interrupted zoom opens")
 reader.enter_reading_mode()
 check(reader.reading_mode and not source.root.visible, "Zoom retains hidden origin ownership")
 reader.finish_close()
 check(not reader.visible and not reader.reading_mode and source.root.visible and reader.cache.is_empty(), "Synchronous teardown releases the same 3D zoom scene cache and restores source")
 check(reader.bind_source_book(source), "Source binds for interrupted leaf turn")
 check(reader.open_item(item), "Interrupted turn opens")
 reader.navigate(1)
 reader._process(0.05)
 check(reader.flip_active, "Leaf turn running before forced teardown")
 reader.finish_close()
 check(not reader.visible and not reader.flip_active and source.root.visible, "Synchronous teardown stops turning and restores original")
 check(reader.bind_source_book(source), "Source rebinds")
 var wrong := item.duplicate(true)
 wrong.id = "other"
 wrong.manual_item_id = "other"
 check(not reader.open_item(wrong) and source.root.visible, "Wrong selected identity cannot borrow source book or hide original")
 var odd := item.duplicate(true)
 odd.manual_pages = paths.slice(0, 5)
 check(reader.open_item(odd), "Odd face count is supported without inventing a scan")
 reader.set_reduced_motion(true)
 for repeat in 20: reader.navigate(1)
 check(reader.turned_leaves == 2 and reader.current_page == 4 and reader.leaf_count == 3, "Odd final leaf stops on its real front, not fabricated backside")
 reader.close()
 var large := fixture(40, Vector2i(2048, 3072))
 var large_item := {"id": "large", "manual_pages": [large, large, large, large, large, large]}
 check(reader.open_item(large_item), "High-resolution original opens without modifying source")
 check(reader.cache[0].size == Vector2(2048, 3072) and reader.cache[0].runtime_size.y == 1024, "3D runtime LOD preserves aspect and source size metadata")
 cache_ok()
 reader.enter_reading_mode()
 check(reader.cache[0].runtime_size == Vector2i(2048, 3072) and reader.cache[0].size == Vector2(2048, 3072), "3D reading promotes only selected original face to native source resolution")
 cache_ok()
 reader.exit_reading_mode()
 check(reader.cache[0].runtime_size.y == 1024, "Leaving reading releases high LOD and restores bounded browsing LOD")
 reader.close()
 var unchanged := Image.load_from_file(large)
 check(unchanged.get_size() == Vector2i(2048, 3072), "Original high-resolution file remains intact")
 # Perspective handoff: compare all four PRINTED corners, not merely an AABB.
 var source_camera := Camera3D.new()
 source_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
 source_camera.fov = 38.0
 root.add_child(source_camera)
 for keep in [Camera3D.KEEP_HEIGHT, Camera3D.KEEP_WIDTH]:
  source_camera.keep_aspect = keep
  source.root.transform = Transform3D(Basis.from_euler(Vector3(-1.1, 0.28, 0.22)).scaled(Vector3.ONE * 3.25), Vector3(0.17, -0.08, -1.3))
  var source_pose: Transform3D = source.root.transform
  var expected := source_corners(source, source_camera)
  var projected_rect := Rect2(expected[0], Vector2.ZERO)
  for point in expected: projected_rect = projected_rect.expand(point)
  reader.set_reduced_motion(false)
  check(reader.bind_source_book(source, projected_rect, source_camera), "Camera-relative canonical source binds for perspective handoff")
  check(reader.open_item(item), "Perspective handoff opens selected canonical manual")
  check(reader.get_report().source_view_matched, "Handoff records supported source camera pose and FOV")
  var actual := reader_corners()
  for index in 4:
   max_handoff_error = maxf(max_handoff_error, actual[index].distance_to(expected[index]))
   check(actual[index].distance_to(expected[index]) < 0.1, "Initial printed corner preserves source perspective/orientation to subpixel tolerance")
  check(reader._book_root.basis.determinant() > 0.99, "Handoff remains rigid and unmirrored, not a planar image warp")
  reader._process(0.05)
  check(source.root.transform == source_pose, "Reader interpolation never mutates released source pose")
  settle()
  check(reader._book_root.position.is_equal_approx(Vector3.ZERO), "Handoff interpolates to established readable book pose")
  reader.close()
  reader._transfer = 0.0
  reader._apply_transfer()
  actual = reader_corners()
  for index in 4:
   max_handoff_error = maxf(max_handoff_error, actual[index].distance_to(expected[index]))
   check(actual[index].distance_to(expected[index]) < 0.1, "Return endpoint matches the same four source corners, not only its rectangle")
  reader.finish_close()
  check(source.root.visible and source.root.transform == source_pose, "Return restores released source visibility without changing orientation")
 # Parent teardown may run after this child has already exited the tree.
 var detached: Control = Reader.new()
 host.add_child(detached)
 detached.configure(host)
 check(detached.bind_source_book(source), "Canonical source binds for detached teardown")
 check(detached.open_item(item), "Reader opens before detach while source is retained")
 detached.enter_reading_mode()
 check(not source.root.visible and detached.reading_mode, "Detached-teardown fixture owns source visibility and reading cache")
 host.remove_child(detached)
 check(not detached.is_inside_tree() and source.root.visible, "Child exit restores source before parent teardown")
 detached.finish_close()
 check(not detached.visible and detached.cache.is_empty() and not detached.reading_mode and source.root.visible, "finish_close outside tree safely clears reading state/cache without viewport access")
 detached.free()
 source_camera.queue_free()
 source.root.queue_free()
 reader.queue_free()
 host.queue_free()
 await process_frame
 for path in fixture_paths: DirAccess.remove_absolute(path)
 DirAccess.remove_absolute(fixture_dir)
 print("HANDOFF_MAX_CORNER_ERROR_PX: %.8f" % max_handoff_error)
 print("MANUAL_BOOK_READER_TEST: %d assertions; %d failures" % [assertions, failures.size()])
 for failure in failures: print("FAIL: " + failure)
 quit(0 if failures.is_empty() else 1)
