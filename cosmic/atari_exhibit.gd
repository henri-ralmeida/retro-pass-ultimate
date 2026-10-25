extends Node3D
## Native-meter proof of the five explicitly supplied private assets.
## This class never instantiates GameBox, the SMS hinge, or SMS manual clips.
const PrivateMedia = preload("res://cosmic/atari_private_media.gd")
const SLOT_ORIGIN := Vector3(0.0, 0.06411989246393278, -0.06015661475325658)
const SLOT_ANGLE := 38.0
var media = PrivateMedia.new()
var asset_roots: Dictionary = {}
var missing: Array[String] = []
var carton_open := false
var cartridge_seated := false
var flap_rest: Dictionary = {}
var canonical_cartridge: Node3D
var configured := false

func configure(manifest_path: String = "", opted_in: bool = false) -> bool:
 for child in get_children():
  remove_child(child)
  child.free() # Safe here: detached model roots; avoid transient duplicate residents on reconfigure.
 asset_roots.clear()
 missing.clear()
 flap_rest.clear()
 canonical_cartridge = null
 carton_open = false
 cartridge_seated = false
 configured = media.configure(manifest_path, opted_in)
 if not configured:
  return false
 for key in PrivateMedia.MODEL_KEYS:
  var model: Node3D = media.load_model(key)
  if model == null:
   missing.append(key)
   continue
  var root := Node3D.new()
  root.name = "Atari_" + key
  add_child(root)
  root.add_child(model)
  root.set_meta("system_id", "atari2600")
  if key in ["box", "cartridge", "manual"]:
   root.set_meta("selected_game_id", str(media.manifest.game.id))
  asset_roots[key] = root
 _layout()
 return missing.is_empty()

func _layout() -> void:
 if asset_roots.has("console"):
  asset_roots.console.position = Vector3(0.08, 0.0, -0.10)
  # Existing staged RF routing is not the final connected-cable path.
  asset_roots.console.set_meta("rf_routing_status", "staged_source_geometry")
 if asset_roots.has("controller"):
  asset_roots.controller.position = Vector3(-0.10, 0.0, 0.25)
 if asset_roots.has("box"):
  asset_roots.box.position = Vector3(-0.25, 0.0, -0.06)
  asset_roots.box.rotation.y = deg_to_rad(12.0)
  for key in ["Carton main top flap hinge", "Top flap tuck hinge",
    "Dust flap hinge -1", "Dust flap hinge 1"]:
   var hinge := asset_roots.box.find_child(key, true, false) as Node3D
   if hinge != null:
    flap_rest[key] = {"node": hinge, "transform": hinge.transform}
 if asset_roots.has("cartridge"):
  canonical_cartridge = asset_roots.cartridge
  set_cartridge_seated(false)
 if asset_roots.has("manual"):
  # Source booklet is lying on the X/Z plane. No substitute page or clip mechanism.
  asset_roots.manual.position = Vector3(0.18, 0.003, 0.22)
  asset_roots.manual.rotation.y = deg_to_rad(-15.0)

func set_carton_open(value: bool) -> bool:
 if flap_rest.size() != 4:
  return false
 carton_open = value
 for key in flap_rest:
  var item: Dictionary = flap_rest[key]
  var hinge: Node3D = item.node
  hinge.transform = item.transform
  if not value:
   continue
  match key:
   "Carton main top flap hinge": hinge.rotate_object_local(Vector3.RIGHT, deg_to_rad(-112.0))
   "Top flap tuck hinge": hinge.rotate_object_local(Vector3.RIGHT, deg_to_rad(70.0))
   "Dust flap hinge -1": hinge.rotate_object_local(Vector3.BACK, deg_to_rad(82.0))
   "Dust flap hinge 1": hinge.rotate_object_local(Vector3.BACK, deg_to_rad(-82.0))
 return true

func set_cartridge_seated(value: bool) -> bool:
 if not is_instance_valid(canonical_cartridge):
  return false
 if value and not asset_roots.has("console"):
  return false
 cartridge_seated = value
 canonical_cartridge.transform = Transform3D.IDENTITY
 if value:
  # Static source-contract pose. No claim of collision-tested insertion animation.
  canonical_cartridge.transform = asset_roots.console.transform * Transform3D(
    Basis(Vector3.RIGHT, deg_to_rad(SLOT_ANGLE)), SLOT_ORIGIN)
 else:
  canonical_cartridge.position = Vector3(0.08, 0.0, 0.16)
  canonical_cartridge.rotation.y = deg_to_rad(-10.0)
 canonical_cartridge.set_meta("pose_status", "approximate_seated" if value else "isolated")
 return true

func manual_page_paths() -> Array[String]:
 var result: Array[String] = []
 for index in 8:
  result.append(media.manual_page_path(index))
 return result

func status_text() -> String:
 if not configured:
  return "Mídia privada Atari ausente ou desabilitada. Nenhum modelo substituto foi criado."
 var base := str(media.manifest.game.title) + " · caixa de papelão, cartucho e manual da fonte privada."
 if not missing.is_empty():
  base += "\nRecurso ausente ou inválido: " + ", ".join(missing) + "."
 base += "\nPose de encaixe aproximada; fluxo interativo de inserção ainda não validado."
 base += "\nManual de arquivo público, 8 páginas; leitor ainda não conectado."
 return base
