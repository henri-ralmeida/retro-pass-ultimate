extends RefCounted
## CPU ray picker over the unchanged approved pad, in pad-root local meters.
## Dedicated face-on configuration view only; caller must reject UI-covered points.
const REQUIRED_MESHES := ["Pad_eight_direction_rocker", "Pad_button_1", "Pad_button_2"]
var regions: Dictionary = {}
var configuration_error := ""

func configure(mesh_bounds_in_pad_root: Dictionary) -> bool:
 regions.clear()
 for mesh_name in REQUIRED_MESHES:
  if not mesh_bounds_in_pad_root.has(mesh_name) or not mesh_bounds_in_pad_root[mesh_name] is AABB:
   configuration_error = "Malha de controle ausente: " + mesh_name
   return false
  var bounds: AABB = mesh_bounds_in_pad_root[mesh_name]
  if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x <= 0.0 or bounds.size.z <= 0.0:
   configuration_error = "Limites de malha inválidos: " + mesh_name
   return false
 for index in [1, 2]:
  var bounds: AABB = mesh_bounds_in_pad_root["Pad_button_%d" % index]
  regions["button_%d" % index] = {"center": bounds.get_center(), "height": bounds.end.y + 0.0003, "radius": maxf(bounds.size.x, bounds.size.z) * 0.5 + 0.001}
 var rocker: AABB = mesh_bounds_in_pad_root.Pad_eight_direction_rocker
 regions.dpad = {"center": rocker.get_center(), "height": rocker.end.y + 0.0010, "radius": minf(rocker.size.x, rocker.size.z) * 0.5, "center_radius": 0.0035}
 configuration_error = ""
 return true

func pick_local_ray(origin: Vector3, direction: Vector3) -> Dictionary:
 if regions.is_empty() or not configuration_error.is_empty() or not origin.is_finite() or not direction.is_finite(): return {}
 # Back-facing and grazing views never select controls through the underside.
 if direction.y >= -0.000001: return {}
 var nearest: Dictionary = {}
 var nearest_t := INF
 for region_id in ["button_1", "button_2", "dpad"]:
  var region: Dictionary = regions[region_id]
  var distance: float = (float(region.height) - origin.y) / direction.y
  if distance < 0.0 or distance >= nearest_t: continue
  var point := origin + direction * distance
  var offset := Vector2(point.x - region.center.x, point.z - region.center.z)
  if offset.length() > float(region.radius): continue
  var action: String = region_id
  if region_id == "dpad":
   if offset.length() < float(region.center_radius): continue
   # A narrow diagonal boundary is deliberately inert, rather than guessing.
   if absf(absf(offset.x) - absf(offset.y)) < 0.0010: continue
   action = ("right" if offset.x > 0 else "left") if absf(offset.x) > absf(offset.y) else ("down" if offset.y > 0 else "up")
  nearest = {"action": action, "point_local": point, "ray_t": distance}
  nearest_t = distance
 return nearest

func pick_world_ray(origin: Vector3, direction: Vector3, pad_global: Transform3D) -> Dictionary:
 if not pad_global.is_finite() or absf(pad_global.basis.determinant()) < 0.00000001: return {}
 var inverse := pad_global.affine_inverse()
 # Do not normalize the local direction: preserve the world ray parameter under scale.
 return pick_local_ray(inverse * origin, inverse.basis * direction)

static func viewport_point(window_point: Vector2, content_rect: Rect2, viewport_size: Vector2) -> Vector2:
 if content_rect.size.x <= 0 or content_rect.size.y <= 0 or viewport_size.x <= 0 or viewport_size.y <= 0 or not content_rect.has_point(window_point): return Vector2(-1, -1)
 return (window_point - content_rect.position) / content_rect.size * viewport_size
