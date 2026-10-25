"""Run with Blender in background to replace image nodes only and verify saved file."""
import bpy, json, hashlib, struct, os
from pathlib import Path
root=Path(__file__).resolve().parent.parent
blend=root/'source_blender/MasterSystem_Console_EDITABLE.blend'
bpy.ops.wm.open_mainfile(filepath=str(blend))
def mesh_hash():
    h=hashlib.sha256()
    for o in sorted(bpy.data.objects,key=lambda x:x.name):
        h.update(o.name.encode());h.update(o.type.encode())
        h.update(repr([list(x) for x in o.matrix_world]).encode())
        if o.type=='MESH':
            for v in o.data.vertices:h.update(struct.pack('<3f',*v.co))
            for p in o.data.polygons:h.update(struct.pack('<'+'I'*len(p.vertices),*p.vertices))
            for n in o.data.corner_normals:h.update(struct.pack('<3f',*n.vector))
            for uv in o.data.uv_layers:
                for d in uv.data:h.update(struct.pack('<2f',*d.uv))
    return h.hexdigest()
before=mesh_hash()
replacements={}
for old,name in [('powerbase_top_reference','master_system_atlas_4k'),('console_logo_rgba','master_system_wordmark_4k')]:
    image=bpy.data.images.load(str(root/'source_art/raster'/(name+'.png')),check_existing=False);image.name=name;image.filepath='//../source_art/raster/'+name+'.png';image.pack();replacements[old]=image
for mat in bpy.data.materials:
    if mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type=='TEX_IMAGE' and node.image and node.image.name in replacements:node.image=replacements[node.image.name]
    mat.name=mat.name.replace('Photo_print_Actual_','Vector_print_').replace('Console_logo_baked_RGBA','Console_logo_vector_RGBA').replace('_actual_print','_vector_print')
keep={'master_system_atlas_4k','master_system_wordmark_4k','abs_grain_normal'}
for im in list(bpy.data.images):
    if im.name not in keep:bpy.data.images.remove(im,do_unlink=True)
normal=bpy.data.images.get('abs_grain_normal');normal.filepath='//../MasterSystem_Console_SMS_Assembly_abs_grain_normal.png'
assert before==mesh_hash()
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
bpy.ops.wm.open_mainfile(filepath=str(blend))
after=mesh_hash();assert before==after
images=[]
for im in bpy.data.images:
    assert im.name in keep and im.packed_file
    images.append({'name':im.name,'size':list(im.size),'users':im.users,'filepath':im.filepath,'packed':bool(im.packed_file),'packed_sha256':hashlib.sha256(im.packed_file.data).hexdigest()})
audit={'mesh_normal_uv_transform_hash_before':before,'mesh_normal_uv_transform_hash_after_reopen':after,'geometry_normals_uvs_transforms_unchanged':before==after,'packed_images':images,'unused_photographs_removed':True,'reopened_saved_blend':True}
(root/'source_art/BLEND_REPLACEMENT_AUDIT.json').write_text(json.dumps(audit,indent=2)+'\n')
p=root/'source_blender/MODEL_AUDIT.json';model=json.loads(p.read_text());model['images']=images;model['materials']=sorted(m.name for m in bpy.data.materials);model['texture_restoration']='Replaced photographic decal images with newly drawn vector artwork rendered at 4K. Removed all unused packed images. Reopened and hashed unchanged geometry/normals/UVs/transforms.';model['inscription_audit']='../source_art/BLEND_REPLACEMENT_AUDIT.json';p.write_text(json.dumps(model,indent=2)+'\n')
print(json.dumps(audit,indent=2))
