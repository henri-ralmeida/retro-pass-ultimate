extends SceneTree
var failures := 0
var assertions := 0
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var app = load("res://cosmic/main.tscn").instantiate()
 app.reduced_motion = true
 app.dwell_seconds = 99999.0
 root.add_child(app)
 var host = app.media_host
 host.set_process(false)
 host.tour_store.path = "user://tour_main_fixture_%s.json" % Time.get_ticks_usec()
 host.tour_store.save_tour("unseen")
 host._private_state = {}
 host._tour_checked = false
 host._restore_checked = true
 host.automatic_tour = true
 host.can_offer_tour = func(): return true
 app.controller_release_gate = false
 app._set_background_blocked(false)
 host._process(0.8)
 check(host.is_open() and app.controller_background_blocked,"Automatic offer uses main modal blockade")
 check(root.gui_get_focus_owner() == host.panel.start_button,"Main automatic offer enters icon focus")
 host.panel.later_button.pressed.emit()
 check(not host.is_open() and app.controller_release_gate and app.media_release_gate,"Dismissal arms main held-input release gates")
 check(host.tour_store.state() == "later","Main dismissal persists later")
 host._process(4)
 check(not host.is_open(),"Main cannot auto-repeat dismissed tour")
 app.controller_release_gate = false
 app.media_release_gate = false
 app._set_background_blocked(false)
 app._open_local_media()
 check(host.is_open(),"Main icon reopening remains available")
 host.close_panel()
 var path: String = host.tour_store.path
 app.free()
 for suffix in ["", ".tmp", ".bak"]: DirAccess.remove_absolute(path+suffix)
 print("MEDIA_TOUR_MAIN: %d assertions; %d failures" % [assertions,failures])
 quit(0 if failures == 0 else 1)
