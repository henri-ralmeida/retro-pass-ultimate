extends SceneTree
## Layout geometry and focus scrolling only: not a rendered or hardware test.
const ControllerPanel = preload("res://cosmic/controller_mapping_panel.gd")
const Store = preload("res://cosmic/controller_profile_store.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures.append(message)
func settle() -> void:
 for i in 5: await process_frame
func reachable(panel, control: Control, context: String) -> void:
 var scroll := panel.column.get_parent() as ScrollContainer
 scroll.ensure_control_visible(control)
 await settle()
 var rect := control.get_global_rect()
 var viewport_rect := scroll.get_global_rect()
 check(rect.position.x >= viewport_rect.position.x - 1 and rect.end.x <= viewport_rect.end.x + 1, context + ": horizontal bounds")
 check(rect.position.y >= viewport_rect.position.y - 1 and rect.end.y <= viewport_rect.end.y + 1, context + ": scroll reachability")
func run() -> void:
 for dimensions in [Vector2i(1152,648), Vector2i(1024,768), Vector2i(800,600)]:
  root.size = dimensions
  var panel = ControllerPanel.new()
  panel.load_model = false
  panel.snapshot.poll_physical = false
  panel.store = Store.new("user://layout-%d/profiles.json" % Time.get_ticks_usec())
  root.add_child(panel)
  panel.set_process(false)
  for player in 2:
   check(panel.open_player(player), "player opens")
   panel.advance(0.2)
   await settle()
   var prefix := "%s P%d" % [dimensions, player + 1]
   check(not panel.body.vertical, prefix + ": approved side-by-side layout")
   for row in panel.rows.values(): await reachable(panel, row, prefix + " row")
   await reachable(panel, panel.close_button, prefix + " back")
   panel.begin_capture("button_1")
   panel.advance(0.2)
   var key := InputEventKey.new()
   key.keycode = KEY_X if player == 0 else KEY_H
   key.physical_keycode = key.keycode
   key.pressed = true
   panel.route_input(key)
   key = key.duplicate()
   key.pressed = false
   panel.route_input(key)
   await settle()
   check(panel.conflict_box.visible, prefix + ": conflict shown")
   await reachable(panel, panel.swap_button, prefix + " swap")
   await reachable(panel, panel.conflict_cancel_button, prefix + " cancel")
   panel._resolve_conflict(false)
   panel.advance(0.2)
   panel.request_close()
   panel.advance(0.2)
   await settle()
  panel.free()
 print("CONTROLLER_LAYOUT: checks=%d failures=%s" % [checks, failures])
 quit(0 if failures.is_empty() else 1)
