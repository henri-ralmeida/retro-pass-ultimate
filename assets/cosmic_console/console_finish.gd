extends Node3D
## Non-destructive realtime finish for the original, unchanged presentation GLB.
## Tiny high-contrast bevel highlights alias under the Compatibility renderer.
## Broader satin highlights preserve lighting/volume without disabling specular.
const DIELECTRIC_ROUGHNESS_FLOOR := 0.65
const DIELECTRIC_SPECULAR := 0.25
const METAL_ROUGHNESS_FLOOR := 0.48
var material_audit: Array[Dictionary] = []

func _ready() -> void:
 var adjusted: Dictionary = {}
 for node in find_children("*", "MeshInstance3D", true, false):
  for surface in node.mesh.get_surface_count():
   var original := node.get_active_material(surface) as StandardMaterial3D
   if original == null: continue
   if not adjusted.has(original):
    var material := original.duplicate() as StandardMaterial3D
    var is_metal := material.metallic >= 0.5
    material.roughness = maxf(material.roughness, METAL_ROUGHNESS_FLOOR if is_metal else DIELECTRIC_ROUGHNESS_FLOOR)
    if not is_metal:
     material.metallic_specular = minf(material.metallic_specular, DIELECTRIC_SPECULAR)
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    adjusted[original] = material
    material_audit.append({
     "name": original.resource_name,
     "metallic": original.metallic,
     "roughness_original": original.roughness,
     "roughness_final": material.roughness,
     "specular_original": original.metallic_specular,
     "specular_final": material.metallic_specular,
     "normal_mapping_preserved": material.normal_enabled == original.normal_enabled and material.normal_texture == original.normal_texture,
     "alpha_preserved": material.transparency == original.transparency,
    })
   node.set_surface_override_material(surface, adjusted[original])
