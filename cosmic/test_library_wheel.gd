extends SceneTree
## Synthetic transparent image for generic fallback/layout checks, not game art.
var assertions := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
 assertions += 1
 if not ok: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var path := "user://synthetic_clearlogo.png"
 var image := Image.create(800,240,false,Image.FORMAT_RGBA8)
 image.fill(Color.TRANSPARENT)
 image.fill_rect(Rect2i(30,30,740,180),Color(0.2,0.7,0.5,0.8))
 image.save_png(path)
 var scene = load("res://cosmic/main.tscn").instantiate()
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene._focus_returned()
 scene.reduced_motion = true
 scene.enter_library()
 var view = scene.library_view
 var original: Dictionary = view.ITEMS[view.current_index].duplicate(true)
 var title: String = str(original.title)
 view.ITEMS[view.current_index]["wheel"] = path
 view._select(view.current_index)
 check(view.item_wheel.texture!=null and view.item_wheel.visible,"Explicit local wheel appears")
 check(not view.item_title.visible,"Wheel replaces rather than duplicates the text title")
 check(view.item_wheel.accessibility_name.ends_with(title),"Logo keeps the same item accessible name")
 check(view.item_wheel.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED,"Wheel preserves source aspect ratio")
 var pixels: Image = view.item_wheel.texture.get_image()
 check(pixels.get_pixel(0,0).a<0.01,"Transparent margins remain transparent")
 for size in [Vector2i(1152,648),Vector2i(1024,768)]:
  root.size=size
  await process_frame
  view.layout()
  var rect: Rect2 = view.item_wheel.get_global_rect()
  check(Rect2(Vector2.ZERO,Vector2(size)).encloses(rect),"Wheel fits aspect ratio "+str(size))
  check(not rect.intersects(view.footer.get_global_rect()),"Wheel does not overlap contextual footer")
 view.toggle_inspection()
 check(not view.item_wheel.visible and not view.item_title.visible,"Inspection removes both title representations")
 view.go_back()
 view.ITEMS[view.current_index]["wheel"] = "user://missing_same_game_logo.png"
 view._select(view.current_index)
 check(view.item_wheel.texture==null and view.item_title.visible and view.item_title.text==title,"Missing wheel uses normal same-game text, never another game's art")
 view.ITEMS[view.current_index].erase("wheel")
 view._select(view.current_index)
 check(not view.item_wheel.visible and view.item_title.visible,"Absent metadata has identical readable fallback")
 view.ITEMS[view.current_index]=original
 scene.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 print("LIBRARY_WHEEL_TESTS ",JSON.stringify({"assertions":assertions,"passed":failures.is_empty(),"failures":failures,"fixture":"synthetic transparent rectangle, not original game logo"}))
 quit(0 if failures.is_empty() else 1)
