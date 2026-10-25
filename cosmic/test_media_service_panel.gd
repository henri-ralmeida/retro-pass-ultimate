extends SceneTree
const Config = preload("res://cosmic/media_optin_config.gd")
const Planner = preload("res://cosmic/media_optin_plan.gd")
const Service = preload("res://cosmic/media_processing_service.gd")
const OptinPanel = preload("res://cosmic/media_optin_panel.gd")
var assertions := 0
var failures := 0
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func wait_service(service: RefCounted) -> void:
 var deadline := Time.get_ticks_msec() + 10000
 while service.is_busy() and Time.get_ticks_msec() < deadline:
  await process_frame
 check(not service.is_busy(), "Worker terminates within fixture deadline")
 service.shutdown()
func run() -> void:
 var token := str(Time.get_ticks_usec())
 var fixture := ProjectSettings.globalize_path("user://service_fixture_" + token)
 var journal := "user://service_journal_" + token + ".json"
 DirAccess.make_dir_recursive_absolute(fixture)
 var bytes := PackedByteArray()
 bytes.resize(4 * 1024 * 1024)
 bytes.fill(42)
 var file := FileAccess.open(fixture.path_join("exact.png"), FileAccess.WRITE)
 file.store_buffer(bytes)
 file.close()
 var items := [{"id":"synthetic_game", "system":"master_system", "media_metadata":{
  "cover_front":{"relative_path":"exact.png", "status":"present"},
  "wheel":{"relative_path":"OFF.png", "status":"present"}}}]
 var plan := Planner.build(Config.choose("master_system", fixture, ["covers"]), items)
 var service := Service.new()
 check(service.begin(plan, journal, false) == ERR_UNAUTHORIZED, "Service requires explicit confirmation")
 check(not FileAccess.file_exists(journal), "No journal or media work before confirmation")
 check(service.begin(plan, journal, true) == OK, "Thread starts")
 check(service.begin(plan, journal, true) == ERR_BUSY, "Repeated start rejected while busy")
 service.request_cancel()
 await wait_service(service)
 check(service.poll().status == "cancelled", "Worker persists cancellation")
 check(service.begin(plan, journal, true, true) == OK, "Explicit confirmed resume")
 await wait_service(service)
 var snapshot := service.poll()
 check(snapshot.status == "done" and snapshot.files_done == 1, "Thread completes real file")
 check(snapshot.bytes_read == bytes.size(), "Real processed byte count")
 check(service.result().files[0].links[0].identity_status == "unverified", "No identity inference from processing")
 var copy := service.result()
 copy.files.clear()
 check(service.result().files.size() == 1, "Snapshots isolated from caller mutation")
 var panel := OptinPanel.new()
 panel.journal_path = journal + "_panel"
 panel.set_inventory(items)
 root.add_child(panel)
 await process_frame
 check(panel.system_picker.selected == -1, "No automatic system consent")
 for box in panel.categories.values(): check(not box.button_pressed, "Category defaults off")
 panel.system_picker.select(0)
 panel.root_input.text = fixture
 panel.categories.covers.button_pressed = true
 panel._review()
 check(panel.confirm_dialog.visible and not FileAccess.file_exists(panel.journal_path), "Review only shows metadata, does not start I/O")
 panel.confirm_dialog.canceled.emit()
 panel.confirm_dialog.hide()
 panel._confirm()
 check(not FileAccess.file_exists(panel.journal_path), "Dismissed confirmation cannot launch stale plan")
 panel._review()
 panel._confirm()
 panel.confirm_dialog.hide()
 check(panel.start_button.disabled and panel.skip_button.disabled, "Configuration and dismiss controls locked while processing")
 panel._confirm()
 await wait_service(panel.service)
 panel._process(0)
 check(panel.service.poll().status == "done", "Panel confirmed path completes")
 check(not panel.resume_button.disabled and not panel.start_button.disabled, "Terminal state restores controls")
 panel.system_picker.select(2)
 panel.root_input.text = fixture + "/different_selection"
 panel._review_resume()
 check(panel.confirm_dialog.visible and not panel.service.is_busy(), "Resume also requires confirmation")
 check("Sistema: master_system" in panel.confirm_dialog.dialog_text and not "Sistema: atari_2600" in panel.confirm_dialog.dialog_text, "Resume confirmation shows actual saved plan system, not current selector")
 check(not "different_selection" in panel.confirm_dialog.dialog_text, "Resume confirmation shows saved plan root, not edited input")
 panel._invalidate_confirmation()
 panel._dismiss(false)
 check(not panel.visible and not panel.service.is_busy(), "Configure later dismisses without work")
 panel.queue_free()
 await process_frame
 for name in [journal, journal + "_panel"]:
  for suffix in ["", ".bak", ".tmp"]:
   if FileAccess.file_exists(name + suffix): DirAccess.remove_absolute(name + suffix)
 DirAccess.remove_absolute(fixture.path_join("exact.png"))
 DirAccess.remove_absolute(fixture)
 print("MEDIA_SERVICE_PANEL: ", assertions, " assertions; ", failures, " failures")
 quit(0 if failures == 0 else 1)
