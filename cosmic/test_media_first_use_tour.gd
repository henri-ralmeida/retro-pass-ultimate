extends SceneTree
const Host = preload("res://cosmic/media_optin_host.gd")
const Profile = preload("res://cosmic/input_profile.gd")
var failures := 0
var assertions := 0
var stable := false
var offers := 0
var prefix: String
func check(value: bool, label: String) -> void:
 assertions += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func host_new() -> Control:
 var host := Host.new()
 host.profile = Profile.new()
 host.store.path = prefix
 host.automatic_tour = true
 host.can_apply = func(): return true
 host.can_offer_tour = func(): return stable
 host.offer_tour = func():
  offers += 1
  host.open_panel()
 host.catalog_getter = func(): return []
 root.add_child(host)
 host.set_process(false)
 return host
func run() -> void:
 prefix = "user://tour_fixture_%s.json" % Time.get_ticks_usec()
 var host := host_new()
 check(host.tour_store.state() == "unseen" and not host.is_open(),"First launch begins unseen, not immediately modal")
 host._process(3.0)
 check(not host.is_open() and offers == 0,"Waits for stable unblocked navigation")
 stable = true
 host._process(0.4)
 check(not host.is_open(),"Stable-screen grace period respected")
 stable = false
 host._process(0.5)
 stable = true
 host._process(0.4)
 check(not host.is_open(),"Unstable interval resets grace period")
 host._process(0.4)
 check(host.is_open() and offers == 1 and host.tour_store.state() == "in_progress","Offers once, persists in-progress before modal")
 check(not host.panel.service.is_busy() and not FileAccess.file_exists(host.panel.journal_path),"Welcome reads no media and starts no queue")
 check(host.panel.start_button.text.is_empty() and host.panel.skip_button.text.is_empty() and host.panel.later_button.text.is_empty(),"Actions stay icon-only")
 check(host.panel.system_picker.text == "Escolha um sistema" and not host.panel.system_picker.accessibility_name.is_empty(),"Unselected system is visibly named, never blank")
 check(host.close_button.size_flags_horizontal == Control.SIZE_SHRINK_BEGIN,"Back action remains compact instead of full-width")
 check(host.panel.get_theme_stylebox("panel") is StyleBoxEmpty,"Inner panel inherits coherent navy shell")
 check(host.panel.categories.covers.get_theme_icon("unchecked").get_width() == 22,"Checkbox has explicit high-contrast vector outline")
 check(not host.panel.skip_button.tooltip_text.is_empty() and not host.panel.skip_button.accessibility_name.is_empty(),"Icon actions remain named for focus/accessibility")
 check(root.gui_get_focus_owner() == host.panel.start_button,"Focus enters tour action")
 host._process(5.0)
 check(offers == 1,"Open modal cannot duplicate itself")
 host.close_panel()
 check(host.tour_store.state() == "later" and not host.is_open(),"Close is explicit later, not a prompt loop")
 host._process(10.0)
 check(offers == 1,"Later does not auto-repeat")
 host.free()
 host = host_new()
 host._process(10.0)
 check(not host.is_open() and offers == 1,"Later survives fresh host")
 host.open_panel()
 check(host.is_open(),"Icon/manual reopening is always available")
 host._dismissed(preload("res://cosmic/media_optin_config.gd").defer_setup(true))
 check(host.tour_store.state() == "skipped" and not host.is_open(),"Skip persists")
 host.free()
 host = host_new()
 host._process(10.0)
 check(not host.is_open(),"Skip survives fresh host without insistence")
 check(host.tour_store.save_tour("in_progress") == OK,"Interrupted-tour state can be represented")
 host.free()
 host = host_new()
 host._process(10.0)
 check(not host.is_open(),"Crash with in-progress tour never forces reopening")
 host.open_panel()
 var plan := preload("res://cosmic/media_optin_plan.gd").build(preload("res://cosmic/media_optin_config.gd").choose("master_system","/not-read-before-confirmation",["covers"]),[])
 check(host._before_start(plan) == OK and host.tour_store.state() == "configured","Explicit confirmed plan marks configured without probing root")
 host.close_panel()
 check(host.tour_store.state() == "configured","Closing configured panel cannot downgrade decision")
 host.free()
 for stem in [prefix,prefix+".tour",prefix+".bindings"]:
  for suffix in ["", ".tmp", ".bak"]: DirAccess.remove_absolute(stem+suffix)
 print("MEDIA_FIRST_USE_TOUR: %d assertions; %d failures" % [assertions,failures])
 quit(0 if failures == 0 else 1)
