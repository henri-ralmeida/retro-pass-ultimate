extends RefCounted
## Exclusive transient owner in the existing SMS library world. No reparenting.
const Path = preload("res://cosmic/sms_insertion_path.gd")
const Dual = preload("res://cosmic/box_dual_hinge.gd")
const Loader = preload("res://cosmic/sms_mechanical_loader.gd")
const GameBox = preload("res://cosmic/game_box.gd")
const OPEN_BASE_SPINE := 90.0
const OPEN_SPINE_LID := 10.345512025270239 # Approved HOME dual-hinge pose; sleeve-safe path.
const BOX_SHA := "9f185f9483654504862ccf4e030852fe9915a8adee022e9b8b0acbd18d3c3d49"
const SCENE := "res://assets/cosmic_console/MasterSystem_Console_Render.tscn"
const SCENE_SHA := "e08182d4bb38b35d2f5bfdc453b5ad6f25e930c2a3d1146b5283ae84d9c4cadf"
const DEPENDENCIES := {"res://assets/cosmic_console/MasterSystem_Console.glb":"3a15c855ab5ed558ba8d22fc631d0775e0d1a25749e0e8a4e6afefe66156193e","res://assets/cosmic_console/console_finish.gd":"6e4a7313e1aa49cc0dec74e92ed6d1a5f48cc0bf43524cfe2cdcb4673623339f"}
var time := 0.0
var target := 0.0
var duration := Path.TOTAL
var active := false
var last_error := ""
var state: String:
 get:
  if time == 0.0 and target == 0.0: return "closed"
  if target < time: return "reversing"
  if time == duration: return "seated"
  return "forward"
var console: Node3D
var _box: Node3D
var _camera: Camera3D
var _cart: Node3D
var _parent: Node3D
var _cart_id := 0
var _inside := Transform3D.IDENTITY
var _frame := Transform3D.IDENTITY
var _camera_rest := Transform3D.IDENTITY
var _camera_goal := Transform3D.IDENTITY
var _far := 0.0
var _console_offscreen := Vector3.ZERO
var _movers: Array = []
var _dual = Dual.new()

static func media_error(selected: Dictionary) -> String:
 var id := str(selected.get("id",""))
 if id.is_empty() or id == "unavailable": return "Seleção sem mídia correspondente."
 for field in ["cover_front","cover_back","cover_spine"]:
  var path := str(selected.get(field,""))
  if path.is_empty() or GameBox.load_artwork(path,64) == null:
   return "Mídia local incompleta para esta edição; inserção indisponível."
 for field in ["cartridge_label","cartridge_top"]:
  var path := str(selected.get(field,""))
  if not path.is_empty():
   if GameBox.load_artwork(path,64) == null: return "Mídia de cartucho indisponível para esta entrada."
  elif not _verified_legacy_cart_atlas(selected):
   return "Vínculo da mídia original do cartucho não verificado para esta entrada/variante."
 var model := str(selected.get("model_path","res://assets/library_models/master_system_box_cartridge.glb"))
 if FileAccess.get_sha256(model) != BOX_SHA: return "Modelo desta entrada não corresponde à geometria calibrada."
 return ""

static func _verified_legacy_cart_atlas(selected: Dictionary) -> bool:
 # Explicit private linkage for the supplied legacy atlas. Never apply by art_root
 # alone, title similarity, region guesses, or a different catalog variant.
 if str(selected.get("id","")) != "wonder_boy": return false
 var binding_path := OS.get_environment("RETROPASS_SMS_MEDIA_BINDING")
 if binding_path.is_empty() or not FileAccess.file_exists(binding_path): return false
 var file := FileAccess.open(binding_path,FileAccess.READ)
 if file == null or file.get_length() > 16384: return false
 var binding: Variant = JSON.parse_string(file.get_as_text())
 if not binding is Dictionary: return false
 if str(binding.get("item_id","")) != str(selected.id) or str(binding.get("variant_id","")) != str(selected.get("variant_id","")): return false
 var root := str(selected.get("art_root",""))
 if root.is_empty(): return false
 for name in ["SLOT_CART_LABEL.jpg","SLOT_CART_TOP.jpg"]:
  var expected := str(binding.get(name,""))
  if expected != "a3577bda7d29a808de6446235d5782a7862cd4806e7c7ff2414c8ba74780040c": return false
  if FileAccess.get_sha256(root.path_join(name)) != expected: return false
 return true

func prepare(box: Node3D, camera: Camera3D, console_parent: Node3D, selected: Dictionary, patch_path: String) -> bool:
 teardown()
 last_error = media_error(selected)
 if not last_error.is_empty(): return false
 if not is_instance_valid(box) or not is_instance_valid(camera) or not is_instance_valid(console_parent) or not box.is_inside_tree(): return _fail("Cena indisponível.")
 if str(box.item_id) != str(selected.id) or box.opened or box.cartridge_out: return _fail("Caixa selecionada precisa estar fechada e corresponder à edição.")
 var cart: Variant = box.cartridge
 if not is_instance_valid(cart) or not cart.get_parent() is Node3D: return _fail("Cartucho canônico indisponível.")
 if not cart.transform.is_equal_approx(box.inside_pose): return _fail("Cartucho fora da pose inicial; nenhuma correção instantânea aplicada.")
 var loader := Loader.new()
 var result := loader.create_candidate(SCENE,patch_path,SCENE_SHA,OS.get_environment("RETROPASS_SMS_MECHANICAL_PATCH_SHA256"),DEPENDENCIES)
 if result.is_empty(): return _fail("Geometria mecânica privada indisponível ou divergente: " + loader.last_error)
 _box = box
 _camera = camera
 _cart = cart
 _parent = cart.get_parent()
 _cart_id = cart.get_instance_id()
 _inside = cart.transform
 _frame = _parent.global_transform
 _camera_rest = camera.global_transform
 _far = camera.far
 if not _dual.configure(box):
  result.root.free()
  return _fail(_dual.last_error)
 console = result.root
 console_parent.add_child(console)
 _movers = result.movers
 # Capture bounds at final geometry, then start the console beyond the frustum.
 console.global_transform = _frame * Transform3D(Basis.IDENTITY,Path.CONSOLE_ORIGIN)
 _dual.set_angles(OPEN_BASE_SPINE,OPEN_SPINE_LID)
 _camera_goal = _fit_stage()
 _dual.reset()
 var scale_factor := _frame.basis.get_scale().x
 var native_right := _frame.basis.inverse()*_camera_rest.basis.x
 _console_offscreen = Path.CONSOLE_ORIGIN + native_right.normalized() * maxf(4.0,(_camera_goal.origin-_camera_rest.origin).length()/maxf(scale_factor,0.001)+2.0)
 active = true
 time = 0.0
 target = 0.0
 _apply()
 last_error = ""
 return true

func insert(reduced: bool = false) -> bool:
 if not _valid(): return _fail("Rig alterado; feche a biblioteca para reconstruir.")
 target = duration
 if reduced: time = target; return _apply()
 return true
func cancel(reduced: bool = false) -> bool:
 if not _valid(): return _fail("Rig alterado; feche a biblioteca para reconstruir.")
 target = 0.0
 if reduced: time = target; return _apply()
 return true
func tick(delta: float, focused: bool = true) -> bool:
 if not _valid(): return _fail("Rig alterado; feche a biblioteca para reconstruir.")
 if focused and is_finite(delta) and delta >= 0.0: time = move_toward(time,target,delta)
 return _apply()
func _valid() -> bool:
 return active and is_instance_valid(_box) and is_instance_valid(_cart) and is_instance_valid(_camera) and is_instance_valid(_parent) and is_instance_valid(console) and _cart.is_inside_tree() and console.is_inside_tree() and not _cart.is_queued_for_deletion() and not console.is_queued_for_deletion() and _box.cartridge == _cart and _cart.get_instance_id() == _cart_id and _cart.get_parent() == _parent and _parent.global_transform.is_equal_approx(_frame)
func _apply() -> bool:
 if not _valid(): return _fail("Rig indisponível.")
 var pose := Path.sample(time)
 if not _dual.set_angles(OPEN_BASE_SPINE*pose.opening,OPEN_SPINE_LID*pose.opening): return _fail(_dual.last_error)
 _cart.transform = _inside if time <= Path.REVEAL+Path.OPEN else pose.pose
 _box.opened = pose.opening > 0.0
 _box.cartridge_out = time > Path.REVEAL+Path.OPEN
 console.global_transform = _frame*Transform3D(Basis.IDENTITY,_console_offscreen.lerp(Path.CONSOLE_ORIGIN,pose.reveal))
 for part in _movers:
  var node: Variant = part.node
  if not is_instance_valid(node): return _fail("Porta mecânica removida.")
  node.global_transform = console.global_transform*pose.door*part.rest_local_to_console
 _camera.global_transform = _camera_rest if time == 0.0 else _camera_rest.interpolate_with(_camera_goal,pose.reveal)
 _camera.far = maxf(_far,(_camera_goal.origin-_frame.origin).length()+50.0)
 return true
func _fit_stage() -> Transform3D:
 var points: Array[Vector3] = []
 for root in [_box,console]:
  for mesh in root.find_children("*","MeshInstance3D",true,false):
   if not mesh.mesh or not mesh.is_visible_in_tree(): continue
   for i in range(8): points.append(_camera_rest.basis.inverse()*(mesh.global_transform*mesh.get_aabb().get_endpoint(i)))
 # Include all route extrema plus cart bounds conservatively.
 for p in [Vector3(0,0.20,0.036),Path.CONSOLE_ORIGIN+Vector3(0.061,0.2,-0.051)]:
  for d in [Vector3(-0.07,-0.01,-0.02),Vector3(0.07,0.10,0.02)]: points.append(_camera_rest.basis.inverse()*(_frame*(p+d)))
 var low := Vector3(INF,INF,INF)
 var high := -low
 for p in points: low = low.min(p); high = high.max(p)
 var center := (low+high)*0.5
 var aspect := float(_camera.get_viewport().size.x)/maxf(_camera.get_viewport().size.y,1.0)
 # Library viewport is >=2:1 in both supported 16:9 and 4:3 layouts.
 # Fit that narrower bound at entry so resizing between them cannot crop the stage.
 aspect = minf(aspect,2.0)
 var tangent := tan(deg_to_rad(_camera.fov)*0.5)
 var depth := -INF
 for p in points: depth = maxf(depth,p.z+maxf(absf(p.y-center.y),absf(p.x-center.x)/aspect)*1.18/tangent)
 return Transform3D(_camera_rest.basis,_camera_rest.basis*Vector3(center.x,center.y,depth))
func teardown() -> void:
 if is_instance_valid(_cart) and is_instance_valid(_parent) and _cart.get_parent() == _parent: _cart.transform = _inside
 _dual.restore()
 if is_instance_valid(_box): _box.opened = false; _box.cartridge_out = false
 if is_instance_valid(_camera): _camera.global_transform = _camera_rest; _camera.far = _far
 if is_instance_valid(console):
  if console.get_parent(): console.get_parent().remove_child(console)
  console.free()
 console = null
 _box = null
 _cart = null
 _camera = null
 _parent = null
 _movers.clear()
 active = false
 time = 0.0
 target = 0.0
func _fail(reason: String) -> bool:
 last_error = reason
 return false
