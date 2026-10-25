extends SceneTree
## Isolated synthetic fixture tests. These are not a game manual, do not enter
## the normal catalog, and never prove physical-controller or Windows behavior.
const Reader = preload("res://cosmic/manual_reader.gd")
const Profile = preload("res://cosmic/input_profile.gd")
class Host extends Node:
 var input_profile = Profile.new()
 var input_device := "keyboard"
 var chakra: Font
 var orbitron: Font

var failures: Array[String] = []
var assertions := 0
var reader: Control
var fixture_paths: Array[String] = []
var fixture_dir := "/tmp/retropass-manual-test-%d" % OS.get_process_id()
var closed_count := 0

func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok:
  failures.append(message)
  push_error(message)

func _initialize() -> void:
 run.call_deferred()

func key(code: int, pressed: bool = true, echo: bool = false) -> InputEventKey:
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = pressed
 event.echo = echo
 return event

func tap(code: int) -> void:
 reader.handle_event(key(code))
 reader.handle_event(key(code, false))

func pad(code: int, pressed: bool = true) -> InputEventJoypadButton:
 var event := InputEventJoypadButton.new()
 event.button_index = code
 event.pressed = pressed
 return event

func axis(code: int, value: float) -> InputEventJoypadMotion:
 var event := InputEventJoypadMotion.new()
 event.axis = code
 event.axis_value = value
 return event

func mouse_button(point: Vector2, pressed: bool) -> InputEventMouseButton:
 var event := InputEventMouseButton.new()
 event.position = point
 event.global_position = point
 event.button_index = MOUSE_BUTTON_LEFT
 event.pressed = pressed
 return event

func write_image(name_value: String, width: int = 96, height: int = 144, jpeg: bool = false) -> String:
 var path := fixture_dir.path_join(name_value)
 var fixture := Image.create(width, height, false, Image.FORMAT_RGBA8)
 fixture.fill(Color(0.18, 0.27, 0.34, 1))
 fixture.fill_rect(Rect2i(4, 4, mini(width-4, 22), mini(height-4, 14)), Color(0.7, 0.2, 0.3, 1))
 var result := fixture.save_jpg(path) if jpeg else fixture.save_png(path)
 check(result == OK, "Synthetic image saved only under isolated /tmp fixture directory")
 fixture_paths.append(path)
 return path

func write_bytes(name_value: String, bytes: PackedByteArray) -> String:
 var path := fixture_dir.path_join(name_value)
 var file := FileAccess.open(path, FileAccess.WRITE)
 file.store_buffer(bytes)
 file.close()
 fixture_paths.append(path)
 return path

func check_cache() -> void:
 check(reader.cache.size() <= Reader.MAX_CACHE_PAGES, "Texture count remains bounded")
 check(reader.cache_bytes <= Reader.MAX_CACHE_BYTES, "Texture byte estimate remains bounded")
 var sum := 0
 for entry in reader.cache.values(): sum += int(entry.bytes)
 check(sum == reader.cache_bytes, "Cache byte accounting matches retained textures")
 for index in reader.cache:
  check(absi(int(index) - reader.current_page) <= 1, "Only current/adjacent textures retained")

func run() -> void:
 DirAccess.make_dir_recursive_absolute(fixture_dir)
 var host := Host.new()
 root.add_child(host)
 reader = Reader.new()
 host.add_child(reader)
 reader.configure(host)
 reader.closed.connect(func(): closed_count += 1)
 await process_frame
 check(not reader.availability({"id":"wonder_boy", "title":"Wonder Boy"}), "Absent real manual is unavailable")
 check(not reader.open_item({"id":"wonder_boy", "title":"Wonder Boy"}), "Missing manual does not open substitute")
 check(not reader.visible and reader.pages.is_empty() and reader.cache.is_empty(), "Missing manual retains no displayed content")
 check("PDF" in reader.status_for({"id":"fixture", "manual_pdf":"/tmp/manual.pdf"}), "PDF-only metadata is explicitly unsupported")
 var first := write_image("synthetic-01.png")
 var second := write_image("synthetic-02.jpg", 144, 96, true)
 var third := write_image("synthetic-03.png")
 var fourth := write_image("synthetic-04.png")
 var fifth := write_image("synthetic-05.png")
 var item := {"id":"qa_synthetic_a", "title":"SYNTHETIC QA FIXTURE · NOT A GAME MANUAL", "manual_item_id":"qa_synthetic_a", "manual_pages":[first, second, third, fourth, fifth]}
 check(reader.availability(item), "Local bounded image paths are eligible without decoding")
 check(reader.cache.is_empty(), "Availability never creates texture cache")
 check(reader.open_item(item), "Image-page fixture opens integrated reader")
 check(reader.visible and reader.item_id == "qa_synthetic_a" and reader.current_page == 0, "Reader binds selected item identity")
 check(reader.cache.size() == 2, "Opening decodes first page and one neighbor, not whole manual")
 check(reader._image.texture != null, "Current real local image is displayed")
 check_cache()
 reader.navigate(1)
 check(reader.current_page == 1 and reader._natural_size == Vector2(144,96), "JPEG page decoded with original dimensions")
 check_cache()
 reader.navigate(1)
 reader.navigate(1)
 check(not reader.cache.has(0) and not reader.cache.has(1), "Old-page textures are evicted")
 for index in 50: reader.navigate(1)
 check(reader.current_page == 4, "Forward navigation clamps, never wraps")
 for index in 50: reader.navigate(-1)
 check(reader.current_page == 0, "Backward navigation clamps")
 for index in 100: reader.change_zoom(1)
 check(reader.zoom == Reader.ZOOM_MAX, "Extreme zoom is bounded above")
 reader.pan = Vector2(1e20, -1e20)
 reader._frame_page()
 check(reader.pan.is_finite() and reader.pan.length() < 10000, "Pan clamps to rendered image, no unbounded drift")
 for index in 100: reader.change_zoom(-1)
 check(reader.zoom == Reader.ZOOM_MIN and reader.pan == Vector2.ZERO, "Fit is lower zoom bound and recenters")
 reader.change_zoom(NAN)
 check(reader.zoom == Reader.ZOOM_MIN, "Nonfinite zoom input ignored")
 tap(KEY_RIGHT)
 check(reader.current_page == 1, "Keyboard changes pages")
 reader.handle_event(key(KEY_RIGHT))
 for index in 20: reader.handle_event(key(KEY_RIGHT, true, true))
 check(reader.current_page == 2, "Keyboard repeat cannot race through pages")
 reader.handle_event(key(KEY_RIGHT, false))
 reader.handle_event(pad(JOY_BUTTON_RIGHT_SHOULDER))
 for index in 20: reader.handle_event(pad(JOY_BUTTON_RIGHT_SHOULDER))
 check(reader.current_page == 3, "Synthetic controller repeated press is debounced")
 reader.handle_event(pad(JOY_BUTTON_RIGHT_SHOULDER, false))
 reader.handle_event(axis(JOY_AXIS_LEFT_X, -1))
 check(reader.current_page == 3, "Held analog axis on entry waits for neutral")
 reader.handle_event(axis(JOY_AXIS_LEFT_X, 0))
 reader.handle_event(axis(JOY_AXIS_LEFT_X, -1))
 for index in 20: reader.handle_event(axis(JOY_AXIS_LEFT_X, -1))
 check(reader.current_page == 2, "Analog navigation has one neutral-to-edge step")
 reader.handle_event(axis(JOY_AXIS_LEFT_X, 0))
 reader.handle_event(axis(JOY_AXIS_LEFT_X, -1))
 check(reader.current_page == 1, "Returning stick to neutral re-arms one navigation")
 reader.handle_event(axis(JOY_AXIS_TRIGGER_RIGHT, 0))
 reader.handle_event(axis(JOY_AXIS_TRIGGER_RIGHT, 1))
 reader._process(1.0)
 check(reader.zoom > 1 and reader.zoom <= 1.081, "Synthetic trigger zoom obeys bounded delta")
 reader.change_zoom(2)
 var center: Vector2 = reader._canvas.get_global_rect().get_center()
 reader.handle_event(mouse_button(center, true))
 check(reader.dragging, "Page drag begins only inside image panel")
 var motion := InputEventMouseMotion.new()
 motion.relative = Vector2(30,40)
 motion.button_mask = MOUSE_BUTTON_MASK_LEFT
 reader.handle_event(motion)
 check(reader.pan != Vector2.ZERO, "Dragging moves zoomed image")
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
 check(not reader.dragging and reader.pan_axis == Vector2.ZERO and reader.zoom_axis == 0, "Focus loss cancels drag and analog state")
 var previous_page: int = reader.current_page
 reader.handle_event(key(KEY_RIGHT))
 check(reader.current_page == previous_page, "Unfocused modal consumes without acting")
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
 var zoom_before: float = reader.zoom
 reader.handle_event(axis(JOY_AXIS_TRIGGER_RIGHT, 1))
 reader._process(0.05)
 check(reader.zoom == zoom_before, "Held trigger does not carry over focus loss")
 reader.reset_view()
 reader._next.grab_focus()
 reader.handle_event(pad(JOY_BUTTON_A))
 reader.handle_event(pad(JOY_BUTTON_A, false))
 check(reader.current_page == previous_page + 1, "Mapped gamepad confirm activates focused reader button")
 await process_frame
 var zoom_before_click: float = reader.zoom
 var zoom_button_center: Vector2 = reader._zoom_in.get_global_rect().get_center()
 reader.handle_event(mouse_button(zoom_button_center, true))
 reader.handle_event(mouse_button(zoom_button_center, false))
 check(reader.zoom > zoom_before_click, "Modal mouse click activates its own button while consuming input")
 reader.handle_event(mouse_button(zoom_button_center, true))
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
 reader.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
 var interrupted_zoom: float = reader.zoom
 reader.handle_event(mouse_button(zoom_button_center, false))
 check(reader.zoom == interrupted_zoom, "Interrupted button press cannot activate after focus returns")
 tap(KEY_TAB)
 check(reader._buttons.has(root.gui_get_focus_owner()), "Tab focus stays inside modal controls")
 check(reader.handle_event(key(KEY_F8)), "Unknown modal keys are consumed rather than reaching background")
 check(host.input_profile.rebind("back", KEY_Q, false), "Test remaps keyboard back")
 tap(KEY_Z)
 check(reader.visible, "Old back key no longer closes after remapping")
 tap(KEY_Q)
 check(not reader.visible and closed_count == 1, "Remapped keyboard back closes modal and emits once")
 check(reader.cache.is_empty() and reader.cache_bytes == 0 and reader.pages.is_empty(), "Close releases all content and cache")
 check(not reader.handle_event(key(KEY_RIGHT)), "Closed reader no longer consumes host input")
 reader.close()
 check(closed_count == 1, "Repeated close does not emit twice")
 check(reader.open_item(item), "Reopening same game starts fresh")
 check(reader.current_page == 0 and reader.zoom == 1 and reader.pan == Vector2.ZERO, "No page/zoom/pan carryover")
 check(host.input_profile.rebind("back", JOY_BUTTON_LEFT_SHOULDER, true), "Test remaps controller back")
 reader.handle_event(pad(JOY_BUTTON_LEFT_SHOULDER))
 check(not reader.visible and closed_count == 2, "Remapped controller back wins over default page control")
 check(reader.open_item(item), "Reopen before item change")
 var other := {"id":"qa_synthetic_b", "title":"OTHER SYNTHETIC QA FIXTURE", "manual_pages":[second]}
 check(reader.open_item(other), "Switching item binds new local pages")
 check(reader.item_id == "qa_synthetic_b" and reader.pages.size() == 1 and reader._natural_size == Vector2(144,96), "No page or cache leaks from previous game")
 var wrong := item.duplicate(true)
 wrong.manual_item_id = "a_different_game"
 check(not reader.open_item(wrong) and not reader.visible and reader.cache.is_empty(), "Explicit different-game identity fails closed")
 var corrupt := write_bytes("corrupt.png", PackedByteArray([1,2,3,4,5]))
 check(not reader.open_item({"id":"bad", "manual_pages":[corrupt]}), "Corrupt image fails before decode")
 check(not reader.visible and reader.cache.is_empty(), "Corrupt first page never displays stale content")
 var oversize := fixture_dir.path_join("too-many-bytes.png")
 var large := FileAccess.open(oversize, FileAccess.WRITE)
 large.seek(Reader.MAX_FILE_BYTES)
 large.store_8(0)
 large.close()
 fixture_paths.append(oversize)
 check(not reader.availability({"id":"large", "manual_pages":[oversize]}), "Encoded file size rejected by lightweight availability")
 check(not reader.open_item({"id":"large", "manual_pages":[oversize]}), "Oversized file rejected without reading/decode")
 var header := FileAccess.get_file_as_bytes(first)
 header[16] = 0
 header[17] = 0
 header[18] = 0x20
 header[19] = 0
 var huge_dimensions := write_bytes("huge-dimensions.png", header)
 check(not reader.open_item({"id":"dimensions", "manual_pages":[huge_dimensions]}), "Oversized dimensions rejected before decoder allocation")
 var paths: Array = []
 paths.resize(Reader.MAX_PAGES + 1)
 paths.fill(first)
 check(not reader.open_item({"id":"many", "manual_pages":paths}), "Page count bounded before loading")
 for path in ["https://example.invalid/a.png", "file:///tmp/a.png", "../escape.png", "/tmp/../escape.png", "/tmp/manual.pdf", "/tmp/page.svg", "//server/share.png", "relative.png"]:
  check(not reader.open_item({"id":"unsafe", "manual_pages":[path]}), "Unsupported path fails closed: " + path)
 check(not reader.open_item({"id":"type", "manual_pages":[12]}), "Malformed page element rejected")
 check(reader.open_item({"id":"partial", "manual_pages":[first, corrupt, third]}), "Valid first page can open with corrupt later page")
 reader.navigate(1)
 check(reader._image.texture == null and reader._empty.visible and not reader.last_error.is_empty(), "Corrupt later page has honest empty state, not previous image")
 reader.pan_axis = Vector2.ONE
 reader._process(0.05)
 check(reader.pan == Vector2.ZERO, "Missing page cannot accumulate invisible unbounded pan")
 reader.navigate(1)
 check(reader._image.texture != null and reader.last_error.is_empty(), "Reader can continue past corrupt later page")
 check_cache()
 reader.close()
 # One square 4K RGBA page exactly fills texture budget. The adjacent same-size
 # page must not be decoded/cached until selected; this fixture remains isolated.
 var four_k := write_image("synthetic-square-4k.png", 4096,4096)
 check(reader.open_item({"id":"qa_4k", "manual_pages":[four_k,four_k]}), "4096×4096 PNG page accepted without downscaling source")
 check(reader.cache.size() == 1 and reader.cache_bytes == Reader.MAX_CACHE_BYTES, "Square4K page prevents neighbor preload beyond64MiB budget")
 check(reader._natural_size == Vector2(4096,4096), "Square4K original dimensions preserved")
 reader.navigate(1)
 check(reader.cache.size() == 1 and reader.cache.has(1) and not reader.cache.has(0), "Selecting next4K page evicts former before new decode")
 check_cache()
 reader.close()
 host.queue_free()
 await process_frame
 for path in fixture_paths: DirAccess.remove_absolute(path)
 DirAccess.remove_absolute(fixture_dir)
 print("MANUAL_READER: ", "PASS" if failures.is_empty() else "FAIL", " assertions=", assertions, " failures=", failures.size())
 quit(0 if failures.is_empty() else 1)
