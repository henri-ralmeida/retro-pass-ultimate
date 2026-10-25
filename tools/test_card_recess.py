#!/usr/bin/env python3
"""Structural regression for the recessed Sega Card entrance (not a visual test)."""
import hashlib, itertools, json, math, struct
from pathlib import Path
root = Path(__file__).resolve().parents[1]
raw = (root/'assets/cosmic_console/MasterSystem_Console.glb').read_bytes()
n = struct.unpack_from('<I', raw, 12)[0]
g = json.loads(raw[20:20+n]); data = raw[28+n:]
expected_images = {'69bf4af353ccf3dff150f83d4d27aa3761c451aa8d7740f3e3a03fbba5e9142c', 'a0dbaf4ae4c0f973b3f5648f85f996ae420bf1a8c1b2cc96facb12a4546f944d', '3849a2f3313c6ff8e231f31e05df0bf72bc3e7eb4767f10f50a71c49c65597c5'}
images = set()
for im in g['images']:
 v = g['bufferViews'][im['bufferView']]; start = v.get('byteOffset', 0)
 images.add(hashlib.sha256(data[start:start+v['byteLength']]).hexdigest())
assert images == expected_images, 'Printed artwork and procedural normal map must remain unchanged'

def identity(): return [[float(i==j) for j in range(4)] for i in range(4)]
def mul(a,b): return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def matrix(node):
 if 'matrix' in node: return [[node['matrix'][c*4+r] for c in range(4)] for r in range(4)]
 x,y,z,w = node.get('rotation',[0,0,0,1]); s=node.get('scale',[1,1,1]); t=node.get('translation',[0,0,0])
 m=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w),t[0]], [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w),t[1]], [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y),t[2]], [0,0,0,1]]
 for r in range(3):
  for c in range(3): m[r][c]*=s[c]
 return m
bounds={}
def visit(index,parent):
 node=g['nodes'][index]; m=mul(parent,matrix(node)); points=[]
 if 'mesh' in node:
  for p in g['meshes'][node['mesh']]['primitives']:
   a=g['accessors'][p['attributes']['POSITION']]
   for v in itertools.product(*zip(a['min'],a['max'])): points.append([sum(m[r][c]*v[c] for c in range(3))+m[r][3] for r in range(3)])
  bounds[node.get('name',str(index))]=[[min(p[i] for p in points),max(p[i] for p in points)] for i in range(3)]
 for child in node.get('children',[]):visit(child,m)
for index in g['scenes'][g.get('scene',0)]['nodes']:visit(index,identity())
floor=bounds['Card_slot_recess_floor']; guide=bounds['Card_slot_rear_guide']
# glTF/Godot: +Y up, +Z front. The tray joins front lip and rear wall.
assert floor[0][0] <= .0521 and floor[0][1] >= .1119, 'Tray must span the recess width'
lip=bounds['Card_slot_lower_lip']
assert floor[2][0] <= .0662 and floor[2][1] >= lip[2][0] + .001, 'Tray must overlap front lip by at least 1 mm'
assert max(floor[2][1],lip[2][1]) >= .0884, 'Tray/lip union must reach the front of the entrance'
assert floor[1][1] < -.022 and floor[1][0] > -.025, 'Tray must remain near the original lower lip'
gap=guide[1][0]-floor[1][1]
assert .001 < gap < .004, 'Keep a narrow recessed card slit, not a solid plug or open void'
assert 'Front_parting_seam_card_right' in bounds, 'Shell seam must remain split around the entrance'
assert all(math.isfinite(x) for b in bounds.values() for axis in b for x in axis)
print(json.dumps({'passed': True, 'images_unchanged': True, 'floor_bounds':floor,'guide_bounds':guide,'card_slit_metres':gap,'mode':'GLB structural bounds and image hash checks; visual QA remains required'},indent=2))
