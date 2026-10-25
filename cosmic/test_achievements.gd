extends SceneTree
## Explicit synthetic fixtures only. Never depicts the user's RA progress.
const Model = preload("res://cosmic/achievements_model.gd")
const TrophyPanel = preload("res://cosmic/achievements_panel.gd")
const Profile = preload("res://cosmic/input_profile.gd")
const Snapshot = preload("res://cosmic/controller_input_snapshot.gd")
class HostFixture extends Node:
 var input_profile = Profile.new()
 var media_input_snapshot = Snapshot.new()
 var application_focused := true
 var scene_active := true
 var active_pad := 27
class ProviderFixture extends RefCounted:
 var calls: Array = []
 func request_read(_consumer: Object, ticket: Dictionary) -> void: calls.append(ticket)
var checks := 0
var failures: Array[String] = []
func check(ok: bool, why: String) -> void:
 checks += 1
 if not ok: failures.append(why)
func settle() -> void:
 for frame in 5: await process_frame
func _initialize() -> void: run.call_deferred()
func key(panel: Control, host: Node, code: int, pressed: bool = true) -> bool:
 var event := InputEventKey.new()
 event.keycode = code
 event.physical_keycode = code
 event.pressed = pressed
 host.media_input_snapshot.observe(event)
 return panel.route_input(event)
func run() -> void:
 var model := Model.new()
 var records: Array = []
 for index in 200:
  records.append({"id":index+1,"title":"Conquista %03d" % index,"description":"Fixture explícita de teste", "points":5,"unlocked_softcore":true,"unlocked_hardcore":index<199})
 model.set_records(records)
 check(not model.summary().complete,"199/200 never complete despite rounded percentage")
 check(model.summary().unlocked == 199,"hardcore count exact")
 model.mode = "softcore"
 check(model.summary().complete,"softcore complete independent of hardcore")
 model.mode = "hardcore"
 model.filter = "locked"
 check(model.visible_records().size() == 1,"mode-specific locked filter")
 model.set_records([
  {"id":1,"title":"Zeta","points":20,"display_order":3,"type":"missable","rarity_hardcore":2,"unlocked_softcore":true},
  {"id":2,"title":"Alpha","points":5,"display_order":1,"type":"progression","rarity_hardcore":60,"unlocked_hardcore":true},
  {"id":3,"title":"Beta","points":10,"display_order":2,"type":"win_condition","rarity_hardcore":10},
  {"id":3,"title":"Duplicate"}])
 model.filter = "all"
 check(model.achievements.size() == 3,"duplicate ids ignored")
 for sort in Model.SORTS:
  model.sort = sort
  var expected := {"ra":"2","az":"2","za":"1","points":"1","points_low":"2","rarity":"1","rarity_common":"2","status":"2","locked_first":"3"}
  check(model.visible_records()[0].id == expected[sort],"sort "+sort)
 model.filter = "beaten"
 check(model.visible_records().size() == 2,"Beaten Path groups types only")
 model.filter = "missable"
 check(model.visible_records().size() == 1,"missable filter")
 var host := HostFixture.new()
 host.media_input_snapshot.poll_physical = false
 root.add_child(host)
 var launcher := Button.new()
 launcher.text = "Synthetic fixture launcher"
 root.add_child(launcher)
 var panel := TrophyPanel.new()
 root.add_child(panel)
 panel.configure(host)
 var provider := ProviderFixture.new()
 panel.open_for({"id":"local","title":"FIXTURE EXPLÍCITA — SEM DADOS PESSOAIS"},launcher)
 check(panel.state == "unavailable","no provider and no identity honest unavailable")
 check(panel.model.achievements.is_empty(),"no invented records")
 panel.close_panel()
 check(launcher.has_focus(),"close returns to original launcher")
 panel.open_for({"ra_game_id":"test:1","title":"FIXTURE EXPLÍCITA — SEM DADOS PESSOAIS"},launcher,provider)
 await settle()
 var ticket := panel.pending.duplicate(true)
 check(panel.state == "loading","loading distinct from empty")
 check(panel.accept_response(ticket,{"ok":true,"records":records}),"matching ticket accepted")
 await settle()
 check(panel.state == "ready" and panel.model.achievements.size() == 200,"records applied")
 check(not panel.accept_response(ticket,{"ok":true,"records":[]}),"duplicate response ignored")
 var origin := panel._content.get_child(1) as Button
 origin.grab_focus()
 var origin_key := str(origin.get_meta("focus_key"))
 origin.pressed.emit()
 await settle()
 check(panel.view == "achievement_comments","confirm achievement opens read-only comments")
 var comment_ticket := panel.pending.duplicate(true)
 panel.accept_response(comment_ticket,{"ok":false,"error":"Explicit fixture network failure"})
 await settle()
 check(panel.state == "error" and panel.comments.is_empty(),"network failure never called empty ready")
 check(root.gui_get_focus_owner() in panel._buttons,"error has focusable retry")
 panel._request()
 var retry_ticket := panel.pending.duplicate(true)
 panel.accept_response(retry_ticket,{"ok":true,"records":[{"user":"Fixture","submitted":"Test date","text":"<b>literal text, no HTML execution</b>"}],"has_more":true})
 await settle()
 check(panel.comments.size() == 1 and panel.page == 0 and panel.has_more,"first page loaded, not claimed total")
 var next := panel._footer.get_child(1) as Button
 next.grab_focus()
 next.pressed.emit()
 var page_ticket := panel.pending.duplicate(true)
 check(page_ticket.page == 1,"next page index requested")
 panel.accept_response(page_ticket,{"ok":false,"error":"Fixture page failure"})
 await settle()
 check(panel.page == 0 and panel.comments.size() == 1,"failed page keeps current page and records")
 var retry := panel._footer.get_child(1) as Button
 retry.pressed.emit()
 check(panel.pending.page == 1,"retry requests same failed page")
 panel.accept_response(panel.pending.duplicate(true),{"ok":true,"records":[{"user":"Second fixture","text":"Page 2"}],"has_more":false})
 await settle()
 check(panel.page == 1 and panel.comments.size() == 2 and not panel.has_more,"pagination complete explicit has_more")
 panel.go_back()
 var back_ticket := panel.pending.duplicate(true)
 panel.accept_response(back_ticket,{"ok":true,"records":records})
 await settle()
 var focused := root.gui_get_focus_owner()
 check(focused != null and focused.get_meta("focus_key","") == origin_key,"Back restores original achievement row after async response")
 panel._navigate("hubs")
 var stale := panel.pending.duplicate(true)
 panel._navigate("game_comments")
 check(not panel.accept_response(stale,{"ok":true,"records":[]}),"stale view response ignored")
 panel.accept_response(panel.pending.duplicate(true),{"ok":true,"records":[]})
 check(panel.state == "ready" and panel.comments.is_empty(),"valid empty distinct from failure")
 panel._navigate("hubs")
 panel.accept_response(panel.pending.duplicate(true),{"ok":true,"records":[{"id":"fixture-hub","name":"Fixture hub","loaded_count":2}]})
 var hub := panel._content.get_child(0) as Button
 hub.grab_focus()
 hub.pressed.emit()
 panel.accept_response(panel.pending.duplicate(true),{"ok":true,"records":[{"title":"Fixture SMS","console":"Master System"},{"title":"Fixture Atari","console":"Atari 2600"}]})
 check(panel.view == "hub_members" and panel.members.size() == 2,"hub members partial view")
 panel.console_filter = "Atari 2600"
 panel._render()
 check(panel._content.get_child_count() == 1,"hub console filter")
 panel.go_back()
 panel.accept_response(panel.pending.duplicate(true),{"ok":true,"records":[{"id":"fixture-hub","name":"Fixture hub","loaded_count":2}]})
 await settle()
 check(root.gui_get_focus_owner().get_meta("focus_key","") == "hub:fixture-hub","Back restores original hub")
 panel._navigate("achievements")
 panel.accept_response(panel.pending.duplicate(true),{"ok":true,"records":records.slice(0,3)})
 panel._show_sort()
 check(panel._sort_open,"sort subview opens")
 panel.go_back()
 check(not panel._sort_open and panel._sort_button.has_focus(),"Back closes sort and restores sort focus")

 # Long literal comments remain reachable with keyboard and gamepad, not mouse only.
 panel._navigate("game_comments")
 var long_comments: Array = []
 for index in 40: long_comments.append({"user":"Fixture "+str(index),"submitted":"Synthetic date","text":"Explicit test text. ".repeat(80)})
 panel.accept_response(panel.pending.duplicate(true),{"ok":true,"records":long_comments})
 await settle()
 key(panel,host,KEY_PAGEDOWN)
 key(panel,host,KEY_PAGEDOWN,false)
 check(panel._scroll.scroll_vertical > 0,"keyboard can scroll long comments")
 var scroll_before := panel._scroll.scroll_vertical
 var scroll_event := InputEventJoypadMotion.new()
 scroll_event.device = 27
 scroll_event.axis = JOY_AXIS_RIGHT_Y
 scroll_event.axis_value = 1.0
 host.media_input_snapshot.observe(scroll_event)
 panel.route_input(scroll_event)
 panel._process(0.3)
 check(panel._scroll.scroll_vertical > scroll_before,"right stick scrolls comments")
 scroll_event.axis_value = 0.0
 host.media_input_snapshot.observe(scroll_event)
 panel.route_input(scroll_event)
 panel._navigate("achievements")
 panel.accept_response(panel.pending.duplicate(true),{"ok":true,"records":records.slice(0,3)})

 # Held input is event-driven and no second home/scene owner is invoked.
 panel._close_button.grab_focus()
 var before := root.gui_get_focus_owner()
 key(panel,host,KEY_DOWN)
 var after := root.gui_get_focus_owner()
 key(panel,host,KEY_DOWN)
 check(after == root.gui_get_focus_owner() and after != before,"held directional press changes focus once")
 key(panel,host,KEY_DOWN,false)
 host.application_focused = false
 panel.focus_changed(false)
 key(panel,host,KEY_X)
 check(panel.visible,"unfocused confirm cannot close")
 key(panel,host,KEY_X,false)
 host.application_focused = true
 panel.focus_changed(true)
 await settle()
 check(not panel._opening_gate,"neutral return rearms after lost releases")
 panel._close_button.grab_focus()
 key(panel,host,KEY_X)
 check(not panel.visible,"remapped confirm activates focused icon exactly once")
 key(panel,host,KEY_X,false)
 panel.open_for({"ra_game_id":"test:2","title":"Fixture reopened"},launcher,provider)
 var closed_ticket := panel.pending.duplicate(true)
 panel.close_panel()
 check(not panel.accept_response(closed_ticket,{"ok":true,"records":records}),"closed panel rejects stale response")

 # Any observed gamepad device participates in the release gate.
 host.input_profile.rebind("confirm",JOY_BUTTON_LEFT_SHOULDER,true)
 var pad := InputEventJoypadButton.new()
 pad.device = 31
 pad.button_index = JOY_BUTTON_LEFT_SHOULDER
 pad.pressed = true
 host.media_input_snapshot.observe(pad)
 panel.open_for({"ra_game_id":"test:pad","title":"Fixture held pad"},launcher,provider)
 check(panel._opening_gate,"non-default held gamepad gates opening")
 panel._close_button.grab_focus()
 panel.route_input(pad)
 check(panel.visible,"held opening gamepad cannot confirm close")
 pad.pressed = false
 host.media_input_snapshot.observe(pad)
 panel.route_input(pad)
 check(not panel._opening_gate,"gamepad release arms fresh action")
 pad.pressed = true
 host.media_input_snapshot.observe(pad)
 panel.route_input(pad)
 check(not panel.visible,"remapped fresh gamepad confirmation works")
 pad.pressed = false
 host.media_input_snapshot.observe(pad)
 var axis_event := InputEventJoypadMotion.new()
 axis_event.device = 31
 axis_event.axis = JOY_AXIS_LEFT_X
 axis_event.axis_value = 0.8
 host.media_input_snapshot.observe(axis_event)
 panel.open_for({"ra_game_id":"test:axis","title":"Fixture held axis"},launcher,provider)
 check(panel._opening_gate,"non-default held axis gates opening")
 axis_event.axis_value = 0.0
 host.media_input_snapshot.observe(axis_event)
 panel.route_input(axis_event)
 check(not panel._opening_gate,"axis neutral releases gate")
 panel.close_panel()

 for dimensions in [Vector2i(1152,648),Vector2i(1024,768),Vector2i(800,600)]:
  root.size = dimensions
  panel.open_for({"ra_game_id":"test:3","title":"Fixture responsive"},launcher,provider)
  panel.accept_response(panel.pending.duplicate(true),{"ok":true,"records":records.slice(0,3)})
  await settle()
  var bounds := Rect2(Vector2.ZERO,root.get_visible_rect().size)
  print("LAYOUT ",dimensions," viewport=",root.get_visible_rect().size," panel=",panel._panel.get_global_rect()," min=",panel._panel.get_combined_minimum_size())
  check(bounds.encloses(panel._panel.get_global_rect()),"panel fits "+str(dimensions))
  for button in panel._toolbar.get_children():
   if button is Button:
    check(bounds.encloses(button.get_global_rect()),"toolbar icon fits "+str(dimensions))
    check(button.text.is_empty() and not button.tooltip_text.is_empty() and not button.accessibility_name.is_empty(),"icon tooltip/accessibility")
  panel.close_panel()
 panel.free()
 launcher.free()
 host.free()
 print("ACHIEVEMENTS_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty(),"fixtures":"explicit synthetic; no personal RA/network/physical controller"}))
 quit(0 if failures.is_empty() else 1)
