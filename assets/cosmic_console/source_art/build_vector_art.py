#!/usr/bin/env python3
"""Build editable vector art and 4K texture files, without reading any photograph.
Requires fontTools and Inkscape; uses only bundled fonts and the attributed SEGA vector.
Coordinates intentionally retain the model's original UV layout. Labels are paths to
avoid font substitution; edit their strings and dimensions here and rebuild.
"""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from xml.sax.saxutils import escape
import xml.etree.ElementTree as ET
import subprocess, hashlib, json, re
ROOT = Path(__file__).resolve().parent
OUT = ROOT/"raster"
OUT.mkdir(exist_ok=True)
INK = '#d1cfc5'; RED = '#a62d26'; BLACK = '#15191b'
FONTS = { 'sans':TTFont(ROOT/'fonts/LiberationSans-Regular.ttf'), 'serif':TTFont(ROOT/'fonts/LiberationSerif-Bold.ttf') }

def text(s, x, y, size, color=INK, anchor='middle', font='sans', width=None):
    f=FONTS[font]; gs=f.getGlyphSet(); cmap=f.getBestCmap(); upm=f['head'].unitsPerEm
    natural=sum(f['hmtx'].metrics[cmap[ord(c)]][0] for c in s)*size/upm
    sx=(width/natural if width else 1)*size/upm; sy=size/upm
    actual=natural*(width/natural if width else 1)
    start=x-(actual/2 if anchor=='middle' else actual if anchor=='end' else 0)
    paths=[]; cur=0
    for c in s:
        name=cmap[ord(c)]; pen=SVGPathPen(gs)
        gs[name].draw(TransformPen(pen,(sx,0,0,-sy,start+cur*sx,y)))
        paths.append(f'<path d="{pen.getCommands()}"/>');cur+=f['hmtx'].metrics[name][0]
    return f'<g aria-label="{escape(s)}" data-font="Liberation {font}" fill="{color}"><title>{escape(s)}</title>'+''.join(paths)+'</g>'

def path(d, color=INK, sw=2, fill='none'):
    return f'<path d="{d}" fill="{fill}" stroke="{color}" stroke-width="{sw}" stroke-linejoin="miter"/>'
def rect(x,y,w,h,fill,stroke=None,sw=1):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>'
def polygon(points,fill,stroke=None,sw=1):
    return f'<polygon points="{points}" fill="{fill}"'+(f' stroke="{stroke}" stroke-width="{sw}"' if stroke else '')+'/>'
def svg(w,h,body,title):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><title>{title}</title><desc>New vector reconstruction of functional inscriptions. No photographic pixels. See ATTRIBUTION.txt.</desc>{body}</svg>'

# Each panel in a normalized, editable drawing space; these are not photo crops.
# Mapping from drawing coordinates to retained atlas UVs is explicit and reproducible.
regions=[]
def region(name,w,h,uv,body):
    tl,tr,bl=uv
    a=(tr[0]-tl[0])*4096/w; b=(tr[1]-tl[1])*4096/w
    c=(bl[0]-tl[0])*4096/h; d=(bl[1]-tl[1])*4096/h
    e=tl[0]*4096; f=tl[1]*4096
    regions.append(f'<g id="{name}" transform="matrix({a} {b} {c} {d} {e} {f})">{body}</g>')
    (ROOT/(name+'.svg')).write_text(svg(w,h,body,name))

# CARTRIDGE INPUT red band, text and stacked upward arrow.
body=rect(-5,-5,1010,110,RED)
body+=text('CARTRIDGE INPUT',465,64,30)
for k in range(7):
    half=3+k*2.3; y=32+k*5
    body+=path(f'M {623-half} {y} H {623+half}',sw=2)
region('cartridge_header',1000,100,[(.503750026,.456250012),(.817499995,.455624998),(.503750026,.482500017)],body)

# RESET / PAUSE frames; molded buttons remain separate, unchanged mesh objects.
body=rect(-5,-5,1010,110,BLACK)
body+=path('M 18 12 H 487 L 476 88 H 13 Z M 508 12 H 982 L 978 88 H 493 Z',sw=2)
body+=text('RESET',344,61,28)+text('PAUSE',632,61,28)
region('button_labels',1000,100,[(.504374981,.487500012),(.816874981,.486874998),(.504374981,.519374967)],body)

# Main functional diagram. Coordinates and labels redrawn with basic geometry.
body=rect(-8,-8,1016,456,RED)
# Deliberate thin silkscreen connections and filled arrowheads.
body+=path('M 164 84 H 131 L 110 207 H 190 M 145 207 L 123 331 H 285 M 502 131 L 484 206 H 714 M 590 206 L 573 283',sw=2)
body+=polygon('181,203 190,207 181,211',INK)
body+=polygon('478,196 484,207 489,194',INK)
body+=polygon('703,202 714,206 703,210',INK)
body+=polygon('584,216 590,206 593,216',INK)
# Cartridge and Card white tabs.
body+=polygon('151,67 315,67 309,100 145,100',INK)
body+=text('CARTRIDGE',230,90,21,BLACK)
body+=polygon('280,315 442,315 437,347 275,347',INK)
body+=text('CARD',358,338,21,BLACK)
# Control outlines.
body+=path('M 424 66 H 601 L 588 131 H 411 Z M 519 283 H 695 L 682 348 H 506 Z',sw=2)
body+=text('CONTROL 1',505,107,21)+text('CONTROL 2',599,323,21)
# Power indicator triangular route and TV target.
body+=polygon('208,129 466,207 181,284',INK)
body+=polygon('216,142 441,207 194,269',BLACK)
body+=polygon('326,185 386,202 380,220 321,237','#075140')
body+=text('POWER ON',275,215,20)
body+=polygon('721,160 905,160 888,249 702,249',INK)
body+=polygon('729,170 892,170 877,238 714,238',BLACK)
body+=text('TV SYSTEM',803,211,21)
# The bottom diagonal stripe is procedural, clipped to one band.
body+='<defs><clipPath id="stripe_clip"><rect x="21" y="392" width="958" height="31"/></clipPath></defs><g clip-path="url(#stripe_clip)" stroke="#161719" stroke-width="5">'
for x in range(-12,1000,12):body+=f'<path d="M {x} 423 l 31 -31"/>'
body+='</g>'
region('information_panel',1000,440,[(.504374981,.520624995),(.813750029,.519374967),(.506250024,.65625)],body)

# Front labels: deliberate dark base, frame and arrows. No captured plastic/shadows.
body=rect(-5,-5,1010,205,BLACK)
body+=rect(38,26,920,127,RED,INK,7)+text('POWER',500,125,88)
body+=polygon('481,176 519,176 500,200',INK)
region('power_label',1000,200,[(.108125001,.698125005),(.189374998,.698125005),(.108125001,.715000033)],body)
body=rect(-5,-5,1010,105,BLACK)
body+=rect(12,15,469,66,BLACK,INK,3)+rect(510,15,478,66,BLACK,INK,3)
body+=text('CONTROL 1',246,64,47)+text('CONTROL 2',749,64,47)
body+=polygon('232,90 254,90 243,104',INK)+polygon('737,90 759,90 748,104',INK)
region('control_labels',1000,100,[(.416249990,.696874976),(.577499986,.696874976),(.416249990,.712499976)],body)
body=rect(-5,-5,1010,175,BLACK)+rect(166,21,805,118,BLACK,INK,6)+text('CARD INPUT',568,111,78)
for k in range(7):
    x=137-k*11; half=45-k*6;body+=path(f'M {x} {80-half} V {80+half}',sw=5)
region('card_label',1000,170,[(.793124974,.696874976),(.891250014,.696874976),(.793124974,.713124990)],body)

atlas=svg(4096,4096,rect(0,0,4096,4096,BLACK)+''.join(regions),'Master System functional inscription atlas, independently redrawn')
(ROOT/'master_system_atlas_4k.svg').write_text(atlas)

# Authentic path geometry from attributed SEGA mark. Drop its white background
# silhouette; turn blue letter paths and registration mark into white silkscreen.
sega=ET.parse(ROOT/'SEGA_logo_original.svg').getroot()
paths=[]
for node in sega:
    if node.tag.endswith('path') and '255, 255, 255' not in node.attrib.get('style',''):
        paths.append('<path d="'+node.attrib['d']+'" fill="#e5e5df"/>')
logo='<g id="authentic_sega_mark" transform="translate(8 10) scale(1.44)">'+''.join(paths)+'</g>'
logo+=text('MASTER SYSTEM/Power Base',484,136,120,'#e5e5df',anchor='start',font='serif',width=1546)
(ROOT/'master_system_wordmark_4k.svg').write_text(svg(2048,168,logo,'SEGA MASTER SYSTEM/Power Base, vector lettering'))

for stem,width,height in [('master_system_atlas_4k',4096,4096),('master_system_wordmark_4k',4096,336)]:
    target=OUT/(stem+'.png')
    subprocess.run(['inkscape',str(ROOT/(stem+'.svg')),'--export-type=png',f'--export-filename={target}',f'--export-width={width}',f'--export-height={height}'],check=True)
manifest={'generated_from':'Vector paths, type outlines and procedural shapes only; no photograph is read by this script.','fonts':{'functional':'Liberation Sans Regular, SIL OFL 1.1','wordmark_text':'Liberation Serif Bold, SIL OFL 1.1; documented approximation, not certified factory font'},'sega_source':'https://commons.wikimedia.org/wiki/File:SEGA_logo.svg','sega_direct':'https://upload.wikimedia.org/wikipedia/commons/1/13/SEGA_logo.svg','sega_sha256':hashlib.sha256((ROOT/'SEGA_logo_original.svg').read_bytes()).hexdigest(),'output_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [OUT/'master_system_atlas_4k.png',OUT/'master_system_wordmark_4k.png']}}
(ROOT/'ART_MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
