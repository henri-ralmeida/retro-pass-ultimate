"""Path-only maintenance after moving canonical rasters under source_art/raster.
Run with Blender background, no rendering or texture reloading. Packed image bytes,
mesh data, normals, UVs and transforms are hashed before saving and after reopening.
"""
import bpy
from pathlib import Path
import hashlib,json,struct
root=Path(__file__).resolve().parent.parent
blend=root/'source_blender/MasterSystem_Console_EDITABLE.blend'

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

def packed_hashes():
    return {im.name:hashlib.sha256(im.packed_file.data).hexdigest() for im in bpy.data.images if im.packed_file}

bpy.ops.wm.open_mainfile(filepath=str(blend))
before_geometry=mesh_hash();before_packed=packed_hashes()
assert set(before_packed)=={'abs_grain_normal','master_system_atlas_4k','master_system_wordmark_4k'}
changes=[]
for name in ['master_system_atlas_4k','master_system_wordmark_4k']:
    im=bpy.data.images[name];old=im.filepath
    new='//../source_art/raster/'+name+'.png'
    assert (root/'source_art/raster'/(name+'.png')).is_file()
    assert hashlib.sha256((root/'source_art/raster'/(name+'.png')).read_bytes()).hexdigest()==before_packed[name]
    im.filepath=new
    changes.append({'image':name,'old_filepath':old,'new_filepath':new})
# Packed-file source paths are a separate field from Image.filepath. Relink both.
for im in bpy.data.images:
    for packed in im.packed_files:
        packed.filepath=im.filepath
assert before_geometry==mesh_hash() and before_packed==packed_hashes()
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(blend))
bpy.ops.wm.open_mainfile(filepath=str(blend))
assert before_geometry==mesh_hash() and before_packed==packed_hashes()
images=[]
for im in bpy.data.images:
    assert im.packed_file
    images.append({'name':im.name,'size':list(im.size),'users':im.users,'filepath':im.filepath,'packed':True,'packed_source_paths':[p.filepath for p in im.packed_files],'packed_sha256':hashlib.sha256(im.packed_file.data).hexdigest()})
audit_path=root/'source_art/BLEND_REPLACEMENT_AUDIT.json'
audit=json.loads(audit_path.read_text());audit['packed_images']=images
audit['path_only_relocation']={'changes':changes,'geometry_hash_before':before_geometry,'geometry_hash_after_reopen':mesh_hash(),'packed_hashes_unchanged':before_packed==packed_hashes(),'saved_blend_sha256':hashlib.sha256(blend.read_bytes()).hexdigest()}
audit_path.write_text(json.dumps(audit,indent=2)+'\n')
model_path=root/'source_blender/MODEL_AUDIT.json'
model=json.loads(model_path.read_text());model['images']=images;model_path.write_text(json.dumps(model,indent=2)+'\n')
print(json.dumps(audit['path_only_relocation'],indent=2))
