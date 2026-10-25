extends SceneTree
## Resume against the host's own applied catalog, without reopening the panel.
const Host = preload("res://cosmic/media_optin_host.gd")
const Profile = preload("res://cosmic/input_profile.gd")
var inventory: Array = []
var applied_calls := 0
var assertions := 0
var failures := 0
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func wait_finished(host: Control) -> void:
 var deadline := Time.get_ticks_msec() + 10000
 while (host.panel.service.is_busy() or host.panel._was_running) and Time.get_ticks_msec() < deadline:
  await process_frame
 check(not host.panel.service.is_busy() and not host.panel._was_running, "Worker reached observed terminal state")
func confirm(host: Control, resume: bool) -> void:
 if resume: host.panel._review_resume()
 else: host.panel._review()
 await process_frame
 host.panel.confirm_dialog.get_ok_button().grab_focus()
 var event := InputEventKey.new()
 event.keycode = KEY_X
 event.physical_keycode = KEY_X
 event.pressed = true
 host.panel.confirm_dialog.push_input(event)
func run() -> void:
 var prefix := "user://host_resume_applied_%s" % Time.get_ticks_usec()
 var fixture := ProjectSettings.globalize_path(prefix + "_fixtures")
 DirAccess.make_dir_recursive_absolute(fixture)
 var png := Image.create(16,16,false,Image.FORMAT_RGBA8)
 png.fill(Color(0.8,0.3,0.2,1))
 check(png.save_png(fixture.path_join("front.png")) == OK, "Synthetic PNG created")
 inventory = [{"id":"exact-edition", "system":"master_system", "edition":"synthetic-a", "cover_front":"original", "media_metadata":{"cover_front":{"relative_path":"front.png","status":"present"}}}]
 var host := Host.new()
 host.profile = Profile.new()
 host.store.path = prefix + "_settings.json"
 host.catalog_getter = func(): return inventory.duplicate(true)
 host.catalog_apply = func(result: Dictionary) -> int:
  applied_calls += 1
  inventory = result.items.duplicate(true)
  return int(result.applied)
 root.add_child(host)
 host.set_process(false)
 host.panel.journal_path = prefix + "_queue.json"
 host.open_panel()
 host.panel.system_picker.select(0)
 host.panel.root_input.text = fixture
 host.panel.categories.covers.button_pressed = true
 await confirm(host,false)
 await wait_finished(host)
 var plan_signature: String = JSON.stringify(host.panel._last_plan).sha256_text()
 host._process(0)
 check(applied_calls == 1 and inventory[0].has("local_media_validation"), "First apply really mutates shared catalog with provenance")
 check(host.panel.inventory_items == inventory, "Panel snapshot follows own completed application")
 check(JSON.stringify(host.panel._last_plan).sha256_text() == plan_signature, "Own application leaves approved plan signature intact")
 # Do not close/reopen: this is the exact immediate-resume UI regression.
 await confirm(host,true)
 await wait_finished(host)
 check(host.panel.service.poll().files_done == 1 and host.panel.service.poll().bytes_read > 0, "Immediate resume performs current source reread")
 host._process(0)
 check(applied_calls == 2 and "vínculos aplicados" in host._status and not "Catálogo mudou" in host._status, "Immediate resume accepts own provenance-only catalog change")
 check(inventory[0].local_media_previous.cover_front == "original", "Repeated application retains earliest original surface")
 check(JSON.stringify(host.panel._last_plan).sha256_text() == plan_signature, "Resume does not rewrite consent plan")
 await confirm(host,true)
 inventory[0].edition = "external-edition-change"
 await wait_finished(host)
 host._process(0)
 check(applied_calls == 2 and "Catálogo mudou" in host._status, "External catalog change still rejects pending application")
 check(inventory[0].edition == "external-edition-change", "Rejected apply does not overwrite external edit")
 host.free()
 for stem in [prefix + "_settings.json",prefix + "_queue.json"]:
  for suffix in ["", ".tmp", ".bak"]:
   if FileAccess.file_exists(stem + suffix): DirAccess.remove_absolute(stem + suffix)
 DirAccess.remove_absolute(fixture.path_join("front.png"))
 DirAccess.remove_absolute(fixture)
 print("MEDIA_HOST_RESUME_APPLIED: %d assertions; %d failures" % [assertions,failures])
 quit(0 if failures == 0 else 1)
