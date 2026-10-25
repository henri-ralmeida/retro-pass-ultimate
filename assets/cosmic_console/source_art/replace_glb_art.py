#!/usr/bin/env python3
"""Replace the two decal image bufferViews, compacting BIN to remove old bytes.
Run once on an original derived GLB with argv[1] as input and argv[2] as output.
Geometry attributes, normals, indices, UVs, transforms, hierarchy and all other
bufferViews remain byte-identical. No Blender re-export or retessellation occurs.
"""
from pathlib import Path
import struct,json,hashlib,sys
root=Path(__file__).resolve().parent.parent
src=Path(sys.argv[1]); dst=Path(sys.argv[2]); raw=src.read_bytes()
n=struct.unpack_from('<I',raw,12)[0]; j=json.loads(raw[20:20+n]); oldbin=raw[28+n:]
newimages={0:('master_system_atlas_4k','master_system_atlas_4k.png'),1:('master_system_wordmark_4k','master_system_wordmark_4k.png')}
oldimages={im['bufferView']:oldbin[j['bufferViews'][im['bufferView']].get('byteOffset',0):j['bufferViews'][im['bufferView']].get('byteOffset',0)+j['bufferViews'][im['bufferView']]['byteLength']] for im in j['images']}
replacements={j['images'][i]['bufferView']:(root/"source_art/raster"/name).read_bytes() for i,(newname,name) in newimages.items()}
for i,(newname,name) in newimages.items():j['images'][i].update(name=newname,mimeType='image/png')
newbin=bytearray(); preserved=[]
for i,v in enumerate(j['bufferViews']):
    old=oldbin[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
    data=replacements.get(i,old)
    while len(newbin)%4:newbin.append(0)
    v['byteOffset']=len(newbin);v['byteLength']=len(data);newbin.extend(data)
    if i not in replacements:preserved.append({'bufferView':i,'sha256':hashlib.sha256(data).hexdigest(),'unchanged':data==old})
while len(newbin)%4:newbin.append(0)
j['buffers'][0]['byteLength']=len(newbin)
j.setdefault('asset',{}).setdefault('extras',{})['inscription_revision']='Independent vector reconstruction, 4K; no retailer photograph or baked photographic logo. See source_art/ATTRIBUTION.txt.'
for mat in j['materials']:
    mat['name']=mat['name'].replace('Photo_print_Actual_','Vector_print_').replace('Console_logo_baked_RGBA','Console_logo_vector_RGBA').replace('_actual_print','_vector_print')
s=json.dumps(j,separators=(',',':')).encode();s+=b' '*((-len(s))%4)
result=struct.pack('<III',0x46546c67,2,28+len(s)+len(newbin))+struct.pack('<II',len(s),0x4E4F534A)+s+struct.pack('<II',len(newbin),0x004E4942)+newbin
dst.write_bytes(result)
assert all(oldimages[i] not in result for i in replacements)
audit={'source_sha256':hashlib.sha256(raw).hexdigest(),'result_sha256':hashlib.sha256(result).hexdigest(),'all_other_bufferViews_unchanged':all(x['unchanged'] for x in preserved),'preserved_other_bufferViews_including_normal_image':preserved,'removed_image_sha256':[hashlib.sha256(oldimages[i]).hexdigest() for i in replacements],'old_image_byte_sequences_absent':True,'images':[{'name':im['name'],'mimeType':im['mimeType'],'sha256':hashlib.sha256(newbin[j['bufferViews'][im['bufferView']]['byteOffset']:j['bufferViews'][im['bufferView']]['byteOffset']+j['bufferViews'][im['bufferView']]['byteLength']]).hexdigest()} for im in j['images']]}
(root/'source_art'/'GLB_REPLACEMENT_AUDIT.json').write_text(json.dumps(audit,indent=2)+'\n')
print('GLB image replacement complete;',len(preserved),'other bufferViews byte-identical (including normal image); old image byte sequences absent.')
