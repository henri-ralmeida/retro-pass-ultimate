extends SceneTree
## Synthetic color fixture tests mapping only; not real game art or visual fidelity.
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
 assertions += 1
 if not value: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var path := "user://synthetic_cartridge_label.png"
 var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
 image.fill(Color.RED)
 image.save_png(path)
 var box = load("res://cosmic/game_box.gd").new()
 root.add_child(box)
 box.configure({"id":"synthetic_a","title":"Synthetic mapping test","cartridge_label":path})
 var label_count := 0
 for mesh in box.original_model.find_children("*","MeshInstance3D",true,false):
  for surface in mesh.mesh.get_surface_count():
   var source = mesh.mesh.surface_get_material(surface)
   if source.resource_name == "SLOT_CART_LABEL":
    label_count += 1
    check(mesh.get_surface_override_material(surface).albedo_texture != null,"Explicit cartridge label is applied")
    var coords: PackedVector2Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
    var low := Vector2(INF,INF)
    var high := Vector2(-INF,-INF)
    for uv in coords:
     low = low.min(uv)
     high = high.max(uv)
    check(low.is_equal_approx(Vector2.ZERO) and high.is_equal_approx(Vector2.ONE),"Independent label fills its own UV rectangle instead of legacy photograph crop")
   if source.resource_name == "SLOT_CART_TOP":
    check(mesh.get_surface_override_material(surface).albedo_texture == null,"Front label never invented as cartridge top")
 check(label_count > 0,"Original cartridge has label surface")
 box.configure({"id":"synthetic_b","title":"No supplied label"})
 for mesh in box.original_model.find_children("*","MeshInstance3D",true,false):
  for surface in mesh.mesh.get_surface_count():
   if mesh.mesh.surface_get_material(surface).resource_name == "SLOT_CART_LABEL":
    check(mesh.get_surface_override_material(surface).albedo_texture == null,"Another game never inherits previous label")
 box.queue_free()
 await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 print("GAME_MEDIA_TESTS ",JSON.stringify({"assertions":assertions,"passed":failures.is_empty(),"failures":failures}))
 quit(0 if failures.is_empty() else 1)
