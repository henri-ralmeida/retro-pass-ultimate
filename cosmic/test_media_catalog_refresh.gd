extends SceneTree
## Synthetic surfaces only; no private artwork or external catalog.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var image_path := "user://media_refresh_synthetic.png"
 var image := Image.create(32,16,false,Image.FORMAT_RGB8)
 image.fill(Color(0.1,0.4,0.8))
 image.save_png(image_path)
 var scene = load("res://cosmic/main.tscn").instantiate()
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene.reduced_motion = true
 var view = scene.sms_library_view
 var index: int = view.current_index
 var id: String = view.ITEMS[index].id
 var items: Array = scene._local_media_inventory()
 for item in items:
  if item.id == id:
   item.cover_front = image_path
   item.wheel = image_path
 var old_box = view.box
 scene._apply_local_media({"items":items,"applied":2,"changed_paths":[image_path]})
 check(view.local_media_refresh_pending,"Applied catalog marks presentation dirty")
 check(view.box == old_box,"Metadata commit does not rebuild interactive model mid-navigation")
 view.open()
 check(not view.local_media_refresh_pending,"Next open consumes refresh")
 check(view.current_index == index and view.box.item_id == id,"Refresh preserves exact selected variant")
 check(view.box.item.cover_front == image_path,"Next open updates box surface")
 check(view.item_wheel.texture != null,"Next open updates wheel through existing loader")
 view.close()
 var first_texture = view.item_wheel.texture
 image.fill(Color(0.8,0.1,0.2))
 image.save_png(image_path)
 scene._apply_local_media({"items":items,"applied":2,"changed_paths":[image_path]})
 # Even identical metadata requires refreshed surfaces after same-path byte changes.
 view.open()
 check(view.item_wheel.texture != first_texture,"Same-path changed bytes invalidate texture")
 scene.free()
 DirAccess.remove_absolute(image_path)
 print("MEDIA_CATALOG_REFRESH: %d assertions; %d failures" % [checks,failures])
 quit(0 if failures == 0 else 1)
