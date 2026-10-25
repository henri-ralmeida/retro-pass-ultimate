"""Procedural card-recess repair. Run in Blender 4.3.2, without re-exporting old GLB buffers.

Usage: blender -b --python repair_card_recess.py -- INPUT.glb INPUT.blend OUTPUT.glb OUTPUT.blend AUDIT.json
Original photo reference is consulted only for shape; no reference pixels are used.
Only two new solid meshes and a split seam are made. All existing mesh buffers,
images, materials and inscriptions are retained exactly in the GLB.
"""
import bpy, sys, json, struct, hashlib, copy
from pathlib import Path
from mathutils import Vector

def digest(b): return hashlib.sha256(b).hexdigest()
def unpack(p):
 b=Path(p).read_bytes(); n=struct.unpack_from('<I',b,12)[0]
 g=json.loads(b[20:20+n]); off=20+n; size=struct.unpack_from('<I',b,off)[0]
 return g,b[off+8:off+8+size]
def pack(p,g,blob):
 g['buffers'][0]['byteLength']=len(blob); j=json.dumps(g,separators=(',',':')).encode();j+=b' '*((-len(j))%4);blob+=b'\0'*((-len(blob))%4)
 Path(p).write_bytes(struct.pack('<III',0x46546c67,2,28+len(j)+len(blob))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(blob),0x004e4942)+blob)
def image_hashes(g,b):
 return {im['name']:digest(b[g['bufferViews'][im['bufferView']].get('byteOffset',0):g['bufferViews'][im['bufferView']].get('byteOffset',0)+g['bufferViews'][im['bufferView']]['byteLength']]) for im in g['images']}
def mesh_hashes():
 d={}
 for o in bpy.data.objects:
  if o.type!='MESH': continue
  h=hashlib.sha256()
  for v in o.data.vertices:h.update(struct.pack('<3f',*v.co))
  for p in o.data.polygons:h.update(struct.pack('<'+'I'*len(p.vertices),*p.vertices))
  for n in o.data.corner_normals:h.update(struct.pack('<3f',*n.vector))
  for uv in o.data.uv_layers:
   for v in uv.data:h.update(struct.pack('<2f',*v.uv))
  d[o.name]=h.hexdigest()
 return d
def bounds():
 vs=[o.matrix_world@v.co for o in bpy.data.objects if o.type=='MESH' for v in o.data.vertices]
 return [[min(v[k] for v in vs) for k in range(3)],[max(v[k] for v in vs) for k in range(3)]]
def ob_bounds(o):
 vs=[o.matrix_world@v.co for v in o.data.vertices]
 return [[min(v[k] for v in vs) for k in range(3)],[max(v[k] for v in vs) for k in range(3)]]

a=sys.argv[sys.argv.index('--')+1:];assert len(a)==5
src_glb,src_blend,out_glb,out_blend,audit_path=map(Path,a)
g,old_blob=unpack(src_glb); assert not any(n.get('name')=='Card_slot_recess_floor' for n in g['nodes']), 'Already repaired'
bpy.ops.wm.open_mainfile(filepath=str(src_blend)); assert 'Card_slot_recess_floor' not in bpy.data.objects
before_hashes=mesh_hashes(); before_bounds=bounds();before_images=image_hashes(g,old_blob)
parent=bpy.data.objects['MasterSystem_PresentationPivot']
parent_i=next(i for i,n in enumerate(g['nodes']) if n.get('name')==parent.name)
seam=bpy.data.objects['Front_parting_seam'];seam_i=next(i for i,n in enumerate(g['nodes']) if n.get('name')==seam.name)
# Preserve seam topology; shorten it to end at the physical recess and instance
# the same mesh on the other side. Do not leave a floating line through the slot.
right=seam.copy();right.name='Front_parting_seam_card_right';bpy.context.collection.objects.link(right)
seam.scale.x=.235/.366;seam.location.x=-.0655
right.scale.x=.071/.366;right.location.x=.1475
rn=copy.deepcopy(g['nodes'][seam_i]);rn['name']=right.name;rn['scale']=[.071/.366,1,1];rn['translation'][0]=.1475
ln=g['nodes'][seam_i];ln['scale']=[.235/.366,1,1];ln['translation'][0]=-.0655
g['nodes'].append(rn);g['nodes'][parent_i]['children'].append(len(g['nodes'])-1)

def solid(name,x0,x1,front_bottom,back_bottom,front_top,back_top,z0,z1,mat_name,bevel):
 verts=[(x0,front_bottom,z0),(x1,front_bottom,z0),(x1,back_bottom,z0),(x0,back_bottom,z0),(x0,front_top,z1),(x1,front_top,z1),(x1,back_top,z1),(x0,back_top,z1)]
 faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
 me=bpy.data.meshes.new(name+'_mesh');me.from_pydata(verts,[],faces);me.update()
 o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.parent=parent;me.materials.append(bpy.data.materials[mat_name])
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 m=o.modifiers.new('Soft_molded_edges','BEVEL');m.width=bevel;m.segments=2;m.affect='EDGES';bpy.ops.object.modifier_apply(modifier=m.name)
 uv=o.data.uv_layers.new(name='UVMap')
 for p in o.data.polygons:
  axis=max(range(3),key=lambda k:abs(p.normal[k]));axes=[k for k in range(3) if k!=axis]
  for li in p.loop_indices:
   co=o.data.vertices[o.data.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]]*100,co[axes[1]]*100)
 o['geometry_origin']='Original procedural geometry; observed reference only, no imported third-party mesh'
 return o
floor=solid('Card_slot_recess_floor',.0518,.1122,-.0847,-.0659,-.0847,-.0659,-.02435,-.02255,'ABS_satin_bezel',.00015)
guide=solid('Card_slot_rear_guide',.0522,.1118,-.0685,-.0673,-.0715,-.0703,-.0202,-.0012,'ABS_molded_black',.00015)
new=[floor,guide];new_names=[o.name for o in new];right_name=right.name;bpy.context.view_layer.update()
blob=bytearray(old_blob)
def accessor(vals,typ,target):
 while len(blob)%4:blob.append(0)
 size=len(vals[0]);flat=[v for row in vals for v in row];start=len(blob);blob.extend(struct.pack('<'+'f'*len(flat),*flat))
 vi=len(g['bufferViews']);g['bufferViews'].append({'buffer':0,'byteOffset':start,'byteLength':len(blob)-start,'target':target})
 ac={'bufferView':vi,'componentType':5126,'count':len(vals),'type':typ}
 if typ=='VEC3':ac.update(min=[min(v[k] for v in vals) for k in range(size)],max=[max(v[k] for v in vals) for k in range(size)])
 ai=len(g['accessors']);g['accessors'].append(ac);return ai
for o in new:
 me=o.data;me.calc_loop_triangles();positions=[];normals=[];uvs=[]
 for tri in me.loop_triangles:
  for li in tri.loops:
   co=me.vertices[me.loops[li].vertex_index].co;n=me.corner_normals[li].vector
   positions.append((co.x,co.z,-co.y));normals.append((n.x,n.z,-n.y));uvs.append(tuple(me.uv_layers.active.data[li].uv))
 material=next(i for i,m in enumerate(g['materials']) if m['name']==me.materials[0].name)
 attrs={'POSITION':accessor(positions,'VEC3',34962),'NORMAL':accessor(normals,'VEC3',34962),'TEXCOORD_0':accessor(uvs,'VEC2',34962)}
 mi=len(g['meshes']);g['meshes'].append({'name':o.name+'_mesh','primitives':[{'attributes':attrs,'material':material,'mode':4}]})
 ni=len(g['nodes']);g['nodes'].append({'name':o.name,'mesh':mi});g['nodes'][parent_i]['children'].append(ni)
pack(out_glb,g,bytes(blob))
# Save without .blend1 backup inside the public repository. Restore image paths
# relative to destination: all three images stay packed and unchanged.
bpy.context.preferences.filepaths.save_version=0
desired_paths={}
for im in bpy.data.images:
 if im.name=='abs_grain_normal':rel='//../MasterSystem_Console_SMS_Assembly_abs_grain_normal.png'
 elif im.name in ('master_system_atlas_4k','master_system_wordmark_4k'):rel='//../source_art/raster/'+im.name+'.png'
 else:raise AssertionError('Unexpected image '+im.name)
 desired_paths[im.name]=rel
 absolute=(out_blend.resolve().parent/rel[2:]).resolve();assert absolute.is_file()
 im.filepath=str(absolute)
 for packed in im.packed_files:packed.filepath=im.filepath
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend.resolve()),relative_remap=False)
bpy.ops.wm.open_mainfile(filepath=str(out_blend.resolve()))
for im in bpy.data.images:
 im.filepath=desired_paths[im.name]
 for packed in im.packed_files:packed.filepath=im.filepath
bpy.ops.wm.save_as_mainfile(filepath=str(out_blend.resolve()),relative_remap=False)
bpy.ops.wm.open_mainfile(filepath=str(out_blend.resolve()));after_hashes=mesh_hashes();after_bounds=bounds()
assert all(after_hashes[n]==h for n,h in before_hashes.items())
assert before_bounds==after_bounds
ng,nb=unpack(out_glb);assert nb[:len(old_blob)]==old_blob;assert image_hashes(ng,nb)==before_images
# Verify preservation of existing materials, image records, and mesh primitives.
original_g,_=unpack(src_glb)
for key in ('materials','images','textures','samplers'):assert ng.get(key)==original_g.get(key),key
assert ng['meshes'][:len(original_g['meshes'])]==original_g['meshes']
ims=[{'name':im.name,'packed_sha256':digest(im.packed_file.data),'size':list(im.size),'filepath':im.filepath} for im in bpy.data.images]
assert len(ims)==3 and all(im.packed_file for im in bpy.data.images)
audit={'repair_date_utc':'2026-10-25','reference_page':'https://iansretromuseum.co.uk/consoles/mastersystem/','reference_close_up':'https://iansretromuseum.co.uk/consoles/mastersystem/gfx1/l10.jpg','reference_use':'Visual shape reference only; no photo pixels or third-party model copied. Dimensions are estimated to fit the supplied mesh, not measured engineering data.','diagnosis':'Original card recess had a lower lip but no continuous inner floor; an uninterrupted fascia seam floated across it. The real console has a recessed tray and a narrow slit near its rear floor.','source_glb_sha256':digest(src_glb.read_bytes()),'output_glb_sha256':digest(out_glb.read_bytes()),'source_blend_sha256':digest(src_blend.read_bytes()),'output_blend_sha256':digest(out_blend.read_bytes()),'existing_glb_binary_prefix_unchanged':True,'existing_mesh_buffers_normals_uvs_unchanged':True,'existing_blend_meshes_normals_uvs_unchanged':True,'existing_materials_images_textures_unchanged':True,'changed_original_object_transforms':['Front_parting_seam'], 'added_objects':new_names+[right_name],'new_bounds_blender_m':{name:ob_bounds(bpy.data.objects[name]) for name in new_names},'blender_to_godot':'(x, y, z) -> (x, z, -y)','bounds_before_blender_m':before_bounds,'bounds_after_blender_m':after_bounds,'bounds_unchanged':True,'nominal_slot_height_m':.00235,'glb_image_sha256_before':before_images,'glb_image_sha256_after':image_hashes(ng,nb),'blend_images':ims,'mesh_objects':sum(o.type=='MESH' for o in bpy.data.objects),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.data.objects if o.type=='MESH'),'verification':'Saved and reopened Blend; parsed GLB, compared original BIN prefix, existing mesh primitives, material/image tables and image hashes. Offline renders separate from Godot tests.'}
Path(audit_path).write_text(json.dumps(audit,indent=2)+'\n');print(json.dumps(audit,indent=2))
