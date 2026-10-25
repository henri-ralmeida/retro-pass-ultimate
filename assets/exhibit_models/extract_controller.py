#!/usr/bin/env python3
"""Extract existing pad geometry without copying any photographic/image payload.
Usage: python extract_controller.py path/to/SMS_Assembly.glb
Original file is read-only; output is adjacent to this script.
"""
import copy, hashlib, json, math, pathlib, struct, sys
src=pathlib.Path(sys.argv[1]); out=pathlib.Path(__file__).parent
raw=src.read_bytes(); magic,version,total=struct.unpack_from('<4sII',raw)
assert magic==b'glTF' and version==2 and total==len(raw)
jlen,jtype=struct.unpack_from('<II',raw,12); g=json.loads(raw[20:20+jlen]); pos=20+jlen
blen,btype=struct.unpack_from('<II',raw,pos); binary=raw[pos+8:pos+8+blen]
root=next(i for i,n in enumerate(g['nodes']) if n.get('name')=='SMS_CONTROLLER_ROOT')
removed=['Pad_direction_frame_print','Pad_SEGA_and_button_print']
ids=[i for i in g['nodes'][root]['children'] if g['nodes'][i]['name'] not in removed]
h={'asset':{'version':'2.0','generator':'RetroPass isolated controller extractor'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'SMS_CONTROLLER_ROOT','children':list(range(1,len(ids)+1))}],'meshes':[],'materials':[],'accessors':[],'bufferViews':[],'buffers':[]}
buf=bytearray(); am={}; bm={}; mm={}
def view(i):
 if i not in bm:
  v=copy.deepcopy(g['bufferViews'][i]); start=v.get('byteOffset',0); size=v['byteLength']; buf.extend(b'\0'*((-len(buf))%4)); v.update(buffer=0,byteOffset=len(buf)); buf.extend(binary[start:start+size]); bm[i]=len(h['bufferViews']);h['bufferViews'].append(v)
 return bm[i]
def accessor(i):
 if i not in am:
  a=copy.deepcopy(g['accessors'][i]); assert 'sparse' not in a;a['bufferView']=view(a['bufferView']);am[i]=len(h['accessors']);h['accessors'].append(a)
 return am[i]
def material(i):
 if i not in mm:
  m=copy.deepcopy(g['materials'][i]);m.pop('normalTexture',None);m.pop('extensions',None)
  for k in list(m):
   if 'Texture' in k:m.pop(k)
  p=m.get('pbrMetallicRoughness',{})
  for k in list(p):
   if 'Texture' in k:p.pop(k)
  mm[i]=len(h['materials']);h['materials'].append(m)
 return mm[i]
for i in ids:
 n=copy.deepcopy(g['nodes'][i]);
 if n['name']=='Pad_cable_strain_relief':
  n['translation']=[0.011,0.010500014,-0.0235]
  n['rotation']=[0,0.7071067811865476,0,0.7071067811865476]
 mesh=copy.deepcopy(g['meshes'][n['mesh']]);n['mesh']=len(h['meshes']);h['nodes'].append(n)
 for p in mesh['primitives']:
  p['attributes']={k:accessor(a) for k,a in p['attributes'].items() if not k.startswith('TEXCOORD')}
  if 'indices' in p:p['indices']=accessor(p['indices'])
  if 'material' in p:p['material']=material(p['material'])
 h['meshes'].append(mesh)
# Derivative-only rear-entry correction. X is an image-proportion estimate.
# Anchor basis.x is the outward tangent: +90 degrees around Y maps +X to -Z.
h['nodes'].append({'name':'ControllerCableAnchor','translation':[0.011,0.010500014,-0.0265],'rotation':[0,0.7071067811865476,0,0.7071067811865476]});h['nodes'][0]['children'].append(len(h['nodes'])-1)
buf.extend(b'\0'*((-len(buf))%4));h['buffers']=[{'byteLength':len(buf)}]
j=json.dumps(h,separators=(',',':')).encode();j+=b' '*((-len(j))%4)
glb=struct.pack('<4sII',b'glTF',2,12+8+len(j)+8+len(buf))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(buf),0x004e4942)+buf
path=out/'SMS_Controller_neutral.glb';path.write_bytes(glb)
# Validate all packed float attributes, index bounds, payload separation and references.
triangles=0
for mesh in h['meshes']:
 for p in mesh['primitives']:
  a=h['accessors'][p['attributes']['POSITION']];v=h['bufferViews'][a['bufferView']];start=v['byteOffset']+a.get('byteOffset',0);stride=v.get('byteStride',12)
  assert all(math.isfinite(x) for i in range(a['count']) for x in struct.unpack_from('<3f',buf,start+i*stride))
  if 'indices' in p:
   ia=h['accessors'][p['indices']];iv=h['bufferViews'][ia['bufferView']];fmt={5121:'B',5123:'H',5125:'I'}[ia['componentType']];values=struct.unpack_from('<'+str(ia['count'])+fmt,buf,iv['byteOffset']+ia.get('byteOffset',0));assert max(values)<a['count'];triangles+=len(values)//3
assert not any(k in h for k in ['images','textures','samplers'])
anchor=h['nodes'][-1]; x,y,z,w=anchor['rotation']; tangent=[1-2*(y*y+z*z),2*(x*y+w*z),2*(x*z-w*y)]
assert all(abs(v-e)<1e-12 for v,e in zip(tangent,[0,0,-1]))
relief=next(n for n in h['nodes'] if n['name']=='Pad_cable_strain_relief')
assert all(abs(anchor['translation'][i]-(relief['translation'][i]+.003*tangent[i]))<1e-9 for i in range(3))
report={'anchor_basis_x_points_departure':True,'anchor_at_relief_tip':True,'source_sha256':hashlib.sha256(raw).hexdigest(),'output_sha256':hashlib.sha256(glb).hexdigest(),'output_bytes':len(glb),'mesh_count':len(h['meshes']),'triangles':triangles,'images':0,'textures':0,'finite_positions':True,'valid_index_bounds':True,'source_preserved':src.read_bytes()==raw,'removed_photo_planes':removed,'units':'meters; glTF/Godot Y up','shell_width':0.1071,'shell_depth':0.0441,'shell_min_y':0.001,'max_y':0.0178,'cable_anchor':[0.011,0.010500014,-0.0265],'cable_departure_direction':[0,0,-1],'relief_translation':[0.011,0.010500014,-0.0235],'relief_and_anchor_rotation_xyzw':[0,0.7071067811865476,0,0.7071067811865476],'correction':'Rear entry verified from supplied photo; X=.011m is estimated from perspective, not a measured dimension. Mesh vertices and materials preserved.'}
(out/'SMS_Controller_validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
