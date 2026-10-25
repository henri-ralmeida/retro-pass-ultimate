extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(value: bool, note: String) -> void:
 checks += 1
 if not value:
  failures.append(note)
  push_error(note)
func _initialize() -> void: run.call_deferred()
func run() -> void:
 var scene = load("res://cosmic/main.tscn").instantiate()
 root.add_child(scene)
 await process_frame
 scene.set_process(false)
 scene.reduced_motion = true
 scene._focus_returned()
 var view: Control = scene.perspective_box_view
 check(is_instance_valid(view),"Dedicated box perspective exists")
 check(scene.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,"Approved console projection unchanged")
 for window_size in [Vector2i(1152,648),Vector2i(1024,768)]:
  root.size = window_size
  await process_frame
  scene._layout()
  await process_frame
  scene._update_perspective_box_frame()
  check(view.visible,"Box is visible in HOME")
  var rect := view.get_rect()
  check(rect.size.x>60 and rect.size.y>60,"Perspective area is usable")
  check(Rect2(Vector2.ZERO,Vector2(window_size)).encloses(rect),"Box viewport fits window")
  var console_left := INF
  for mesh in scene.model.find_children("*","MeshInstance3D",true,false):
   if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
   for corner in 8:
    var point: Vector2 = scene.camera.unproject_position(mesh.global_transform*mesh.get_aabb().get_endpoint(corner))
    point = scene.viewport_container.position+point*scene.viewport_container.size/Vector2(scene.viewport.size)
    console_left = minf(console_left,point.x)
  check(rect.end.x<console_left,"Perspective box stays left of console without overlap")
  for mesh in scene.exhibit.game_box.find_children("*","MeshInstance3D",true,false):
   check(mesh.layers==0,"Bounds proxy is not rendered twice")
  check(scene.exhibit.game_box.cartridge==null,"Only HOME cartridge is seated")
  scene._focus_lost()
  scene._update_perspective_box_frame()
  check(view.visible,"Focus loss preserves box visibility")
  scene._focus_returned()
  for repeat in 3:
   scene.toggle_inspection()
   check(not view.visible,"Console inspection hides perspective box")
   scene.close_inspection()
   scene._update_perspective_box_frame()
   check(view.visible,"Back restores perspective box")
  scene.open_history(false)
  check(not view.visible,"History hides box")
  scene.close_history()
  scene._layout()
  check(view.visible,"History return restores box")
  scene.enter_library()
  check(not view.visible,"Reduced-motion entry hides box")
  scene.leave_library()
  scene._update_perspective_box_frame()
  check(view.visible,"Library return rebuilds same-game box")
 scene.reduced_motion = false
 scene.enter_library()
 scene._apply_entry(0.3)
 check(view.visible,"Animated entry retains box before fade")
 scene._apply_entry(0.94)
 check(not view.visible,"Covered entry hides box")
 scene.leave_library()
 check(view.visible,"Interrupted entry restores box")
 scene.queue_free()
 await process_frame
 print("PERSPECTIVE_HOME: checks=",checks," failures=",failures)
 quit(0 if failures.is_empty() else 1)
