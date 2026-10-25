extends SceneTree
## Synthetic Linux integration: no personal collection, network or physical pad.
const Host = preload("res://cosmic/media_optin_host.gd")
const Profile = preload("res://cosmic/input_profile.gd")
class MainProbe:
 extends "res://cosmic/main.gd"
 var observed := 0
 func _ready() -> void: pass
 func _observe_input_device(_event: InputEvent) -> void: observed += 1
class LibrarySpy:
 extends Node
 var calls := 0
 func handle_event(_event: InputEvent) -> bool:
  calls += 1
  return true
var failures := 0
var assertions := 0
var inventory: Array = []
var applied: Dictionary = {}
var apply_calls := 0
var prefix := ""
var fixture := ""
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func key(code: int) -> InputEventKey:
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = true
 return event
func pad(code: int) -> InputEventJoypadButton:
 var event := InputEventJoypadButton.new()
 event.button_index = code
 event.pressed = true
 return event
func new_host(suffix: String = "") -> Control:
 var host := Host.new()
 host.store.path = prefix + suffix + "_settings.json"
 host.profile = Profile.new()
 host.profile.rebind("confirm", KEY_C, false)
 host.profile.rebind("back", KEY_V, false)
 host.profile.rebind("confirm", JOY_BUTTON_Y, true)
 host.profile.rebind("back", JOY_BUTTON_X, true)
 host.catalog_getter = func(): return inventory.duplicate(true)
 host.catalog_apply = func(result: Dictionary):
  applied = result.duplicate(true)
  apply_calls += 1
  return int(result.get("applied", 0))
 root.add_child(host)
 host.set_process(false)
 host.panel.journal_path = prefix + suffix + "_queue.json"
 return host
func configure(host: Control) -> void:
 host.open_panel()
 host.panel.system_picker.select(0)
 host.panel.root_input.text = fixture
 host.panel.categories.covers.button_pressed = true
func finish(host: Control) -> void:
 var deadline := Time.get_ticks_msec() + 10000
 while (host.panel.service.is_busy() or host.panel._was_running) and Time.get_ticks_msec() < deadline:
  await process_frame
 check(not host.panel.service.is_busy() and not host.panel._was_running, "Worker completes and panel observes terminal result")
func run() -> void:
 prefix = "user://host_integration_%s" % Time.get_ticks_usec()
 fixture = ProjectSettings.globalize_path(prefix + "_fixtures")
 DirAccess.make_dir_recursive_absolute(fixture)
 var png := Image.create(32,32,false,Image.FORMAT_RGBA8)
 png.fill(Color(0.1,0.6,0.9,1))
 check(png.save_png(fixture.path_join("front.png")) == OK, "Synthetic PNG fixture")
 inventory = [{"id":"exact-a", "system":"master_system", "relative_path":"game.sms", "edition":"synthetic-a", "cover_front":"original-kept", "media_metadata":{"cover_front":{"relative_path":"front.png","status":"present"}}}]
 var host := new_host()
 check(not host.is_open() and not host.panel.service.is_busy(), "Optional host does not start or open itself")
 host.open_panel()
 host.panel._dismiss(true)
 check(not host.is_open() and host.store.load_state().decision.decision == "skipped", "Pular closes and persists")
 host.open_panel()
 host.panel._dismiss(false)
 check(not host.is_open() and host.store.load_state().decision.decision == "later", "Configurar depois persists")
 configure(host)
 host.panel._review()
 check(host.panel.confirm_dialog.visible and not host.panel._pending_plan.is_empty(), "Review requires explicit confirmation")
 check(host.panel.service.poll().status == "idle" and not FileAccess.file_exists(host.panel.journal_path), "No processing/journal before confirmation")
 host.panel.confirm_dialog._input(key(KEY_V))
 check(not host.panel.confirm_dialog.visible and host.panel._pending_plan.is_empty() and host.is_open(), "Remapped back dismisses only confirmation")
 host.panel.system_picker.grab_focus()
 check(host.route_input(key(KEY_C)), "Remapped confirm routed to system picker")
 var popup = host.panel.system_picker.get_popup()
 check(popup.visible, "OptionButton popup opens through remapped profile")
 popup.set_focused_item(2)
 popup._input(pad(JOY_BUTTON_Y))
 check(not popup.visible and host.panel.system_picker.selected == 2, "Remapped gamepad confirm selects exact system")
 host.panel.system_picker.show_popup()
 popup._input(pad(JOY_BUTTON_X))
 check(not popup.visible and host.is_open(), "Remapped popup back leaves modal open")
 configure(host)
 host.panel.root_input.grab_focus()
 check(not host.route_input(key(KEY_C)), "Remapped letters remain path text while typing")
 var probe := MainProbe.new()
 root.add_child(probe)
 probe.set_process(false)
 probe.set_process_input(false)
 probe.media_host = host
 var spy := LibrarySpy.new()
 probe.add_child(spy)
 probe.library_view = spy
 probe.library_state = "library"
 probe._input(key(KEY_C))
 check(probe.observed == 0 and spy.calls == 0, "Modal false route never falls through to HOME/library")
 host.panel._review()
 probe._input(key(KEY_X))
 check(probe.observed == 0 and spy.calls == 0, "Confirmation GUI remains exclusive from main input")
 probe.media_host = null
 probe.free()
 var service = host.panel.service
 await process_frame
 host.panel.confirm_dialog.get_ok_button().grab_focus()
 var opening_release := key(KEY_C)
 opening_release.pressed = false
 host.panel.confirm_dialog._input(opening_release)
 host.panel.confirm_dialog._input(key(KEY_C))
 check(host.store.load_state().decision.decision == "configured", "Confirmation persists explicit plan")
 host.close_panel()
 check(not host.is_open() and host.panel.service == service and is_instance_valid(host.panel), "Closing modal preserves one worker/panel owner")
 await finish(host)
 check(host.panel.service.poll().files_done == 1, "Actual file hash completes")
 check(apply_calls == 0, "Catalog not applied before host gate")
 host._process(0)
 check(apply_calls == 1 and applied.applied == 1 and applied.validated_files == 1, "Current hash plus real decode associates one exact link")
 check(applied.items[0].cover_front == fixture.path_join("front.png") and applied.items[0].local_media_previous.cover_front == "original-kept", "Application preserves original surface")
 check(applied.items[0].local_media_validation.cover_front.identity_status == "unverified", "Decode is not identity verification")
 host.free()
 host = new_host()
 check(not host.panel.service.is_busy() and host.panel.service.poll().status == "idle" and not host.panel._last_plan.is_empty(), "Restart offers stored plan without running")
 host.open_panel()
 host.panel._review_resume()
 check(host.panel.confirm_dialog.visible and host.panel.service.poll().status == "idle", "Resume requires another confirmation")
 await process_frame
 host.panel.confirm_dialog.get_ok_button().grab_focus()
 host.panel.confirm_dialog._input(key(KEY_C))
 inventory[0].edition = "changed-edition"
 await finish(host)
 host._process(0)
 check(apply_calls == 1 and "Catálogo mudou" in host._status, "Catalog change refuses pending application")
 host.free()
 host = new_host("_failure")
 configure(host)
 host.store.path = "user://missing_parent_" + str(Time.get_ticks_usec()) + "/settings.json"
 host.panel._review()
 host.panel._confirm()
 check(host.panel.service.poll().status == "idle" and not FileAccess.file_exists(host.panel.journal_path), "Store failure blocks worker before any media reads")
 check("nenhuma mídia lida" in host.panel.status_label.text, "Store failure explained honestly")
 host.panel._invalidate_confirmation()
 host.panel._dismiss(false)
 check(host.is_open() and host.panel.visible, "Failed decision save leaves retry UI open")
 host.close_panel()
 host.free()
 var fake_image := FileAccess.open(fixture.path_join("invalid.png"), FileAccess.WRITE)
 fake_image.store_string("synthetic bytes, deliberately not an image")
 fake_image.close()
 inventory[0].media_metadata.cover_front.relative_path = "invalid.png"
 host = new_host("_invalid")
 configure(host)
 host.panel._review()
 host.panel._confirm()
 host.panel.confirm_dialog.hide()
 await finish(host)
 host._process(0)
 check(host.panel.service.poll().files_done == 1 and applied.applied == 0 and applied.validated_files == 0, "Hash success never substitutes for valid image decoding")
 check(applied.items[0].cover_front == "original-kept" and not applied.issues.is_empty(), "Invalid PNG preserves original with explicit issue")
 service = host.panel.service
 host.free()
 check(not service.is_busy() and service._thread == null, "Host teardown safely joins and releases owning service")
 for stem in [prefix + "_settings.json",prefix + "_queue.json",prefix + "_failure_settings.json",prefix + "_failure_queue.json",prefix + "_invalid_settings.json",prefix + "_invalid_queue.json"]:
  for suffix in ["", ".tmp", ".bak"]:
   if FileAccess.file_exists(stem + suffix): DirAccess.remove_absolute(stem + suffix)
 DirAccess.remove_absolute(fixture.path_join("invalid.png"))
 DirAccess.remove_absolute(fixture.path_join("front.png"))
 DirAccess.remove_absolute(fixture)
 print("MEDIA_HOST_INTEGRATION: %d assertions; %d failures" % [assertions, failures])
 quit(0 if failures == 0 else 1)
