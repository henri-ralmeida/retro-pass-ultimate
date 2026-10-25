extends SceneTree
const OptinPanel = preload("res://cosmic/media_optin_panel.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 root.content_scale_size = Vector2i.ZERO
 for viewport_size in [Vector2i(1152,648),Vector2i(1024,768)]:
  root.size = viewport_size
  var panel := OptinPanel.new()
  var theme := Theme.new()
  theme.default_font = load("res://assets/fonts/ChakraPetch-Regular.ttf")
  theme.default_font_size = 16
  panel.theme = theme
  root.add_child(panel)
  panel.system_picker.select(0)
  panel.root_input.text = "/synthetic/private/absolute/path/with/a/long/root/for/layout/fixture"
  panel.categories.covers.button_pressed = true
  panel.set_inventory([{"id":"exact", "system":"master_system", "media_metadata":{"cover_front":{"status":"present","relative_path":"front.png"}}}])
  panel._review()
  for i in 4: await process_frame
  var dialog: Window = panel.confirm_dialog
  check(dialog.size.x <= viewport_size.x and dialog.size.y <= viewport_size.y,"Confirmation fits viewport " + str(viewport_size))
  check(Rect2i(Vector2i.ZERO,viewport_size).encloses(Rect2i(dialog.position,dialog.size)),"Confirmation stays on screen")
  for button in [panel.confirm_dialog.get_ok_button(),panel.confirm_dialog.get_cancel_button()]:
   print("MEDIA_LAYOUT_RECT ",viewport_size," dialog=",dialog.position,"/",dialog.size," button=",button.get_global_rect())
   check(Rect2(Vector2.ZERO,Vector2(dialog.size)).encloses(button.get_global_rect()),"Consent button fully visible")
  var label: Label = panel.confirm_dialog.get_label()
  check(label.get_line_count()*label.get_line_height() <= label.size.y+2,"All consent text lines fit")
  panel.free()
  await process_frame
 print("MEDIA_LAYOUT: %d assertions; %d failures" % [checks,failures])
 quit(0 if failures == 0 else 1)
