#!/usr/bin/env python3
"""Rebuild original fictional sleeve art. SVGs contain editable vectors, not fonts.
Requires fontTools; uses the project's existing OFL fonts. No downloaded imagery.
"""
from pathlib import Path
from xml.sax.saxutils import escape
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
import math

ROOT = Path(__file__).resolve().parent
FONTS = ROOT.parent / 'fonts'
FONT = TTFont(FONTS / 'ChakraPetch-Regular.ttf')
DISPLAY = TTFont(FONTS / 'Orbitron.ttf')


def text(s, x, y, size, color='#f9f0de', tracking=0, display=False, anchor='start'):
    font = DISPLAY if display else FONT
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    scale = size / font['head'].unitsPerEm
    advances = [font['hmtx'].metrics[cmap.get(ord(c), '.notdef')][0] * scale + tracking for c in s]
    width = sum(advances) - tracking
    cursor = x - (width / 2 if anchor == 'middle' else width if anchor == 'end' else 0)
    out = []
    for c, advance in zip(s, advances):
        pen = SVGPathPen(glyphs)
        glyphs[cmap.get(ord(c), '.notdef')].draw(pen)
        d = pen.getCommands()
        if d:
            out.append(f'<path d="{d}" transform="translate({cursor:.3f} {y}) scale({scale:.6f} {-scale:.6f})" fill="{color}"/>')
        cursor += advance
    return ''.join(out)


def start(w, h, name):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
<title>{escape(name)} — estudo fictício / não oficial</title>
<desc>Arte vetorial original para um modelo visual de caixa no RETRO PASS ULTIMATE. Não é reprodução de embalagem, personagem, edição ou arte oficial. Não contém ROM.</desc>
<defs>
 <linearGradient id="sky" x2="0" y2="1"><stop stop-color="#192942"/><stop offset=".58" stop-color="#52677a"/><stop offset="1" stop-color="#d7977c"/></linearGradient>
 <linearGradient id="water" x2="1" y2="1"><stop stop-color="#76e3cc"/><stop offset="1" stop-color="#1f6075"/></linearGradient>
 <linearGradient id="sand" x2="0" y2="1"><stop stop-color="#efbd83"/><stop offset="1" stop-color="#c47267"/></linearGradient>
 <linearGradient id="body" x2="1" y2="1"><stop stop-color="#17273c"/><stop offset="1" stop-color="#0b1425"/></linearGradient>
 <pattern id="grid" width="28" height="28" patternUnits="userSpaceOnUse"><path d="M28 0H0V28" stroke="#bee3db" stroke-opacity=".06" fill="none"/></pattern>
 <clipPath id="frame"><rect x="28" y="28" width="844" height="1204" rx="16"/></clipPath>
 <clipPath id="detail"><rect x="56" y="465" width="788" height="305" rx="4"/></clipPath>
</defs>'''


def stars():
    out=[]
    for i in range(28):
        x=55+(i*137)%790; y=350+(i*61)%300
        out.append(f'<circle cx="{x}" cy="{y}" r="{1.4 if i%3 else 2.5}" fill="#e2e6d6" opacity="{.35+(i%4)*.12}"/>')
    return ''.join(out)


def palm(x,y,s,ink='#123340'):
    return f'''<g transform="translate({x} {y}) scale({s})" fill="{ink}">
 <path d="M-5 0L7 0L1-145L-11-145Z"/>
 <path d="M-6-140Q-68-192-115-139Q-52-158-6-140M-6-140Q-70-146-98-95Q-45-126-6-140M-6-140Q-26-203 26-212Q-2-173-6-140M-6-140Q57-194 101-150Q38-164-6-140M-6-140Q62-147 91-100Q34-130-6-140"/>
 </g>'''


def scene(theme='alex', small=False):
    # Every landscape element is an original geometric illustration.
    sky = '<rect x="28" y="340" width="844" height="775" fill="url(#sky)"/>'
    sun = '<circle cx="645" cy="525" r="110" fill="#f1c19a"/><circle cx="645" cy="525" r="135" fill="none" stroke="#f1c19a" stroke-opacity=".32"/>'
    horizon='''<path d="M28 720L155 565L257 658L358 506L515 689L599 616L721 725L872 600V1120H28Z" fill="#526776"/>
<path d="M28 761L197 638L306 764L441 624L541 748L738 644L872 776V1120H28Z" fill="#355267"/>
<path d="M28 835L230 731L381 842L506 715L675 827L872 751V1120H28Z" fill="#203c53"/>
<path d="M28 873Q263 807 462 897T872 867V1120H28Z" fill="url(#water)"/>
<path d="M255 929Q480 891 707 926M365 956Q553 927 770 959M151 984Q388 950 550 980" fill="none" stroke="#b0efda" stroke-opacity=".42" stroke-width="3"/>'''
    rocks='''<path d="M28 816L186 758L320 824L328 1108H28Z" fill="#c47b6d"/>
<path d="M28 816L186 758L320 824L163 881Z" fill="url(#sand)"/>
<path d="M163 881L320 824L328 1108H178Z" fill="#9c5c63"/>
<path d="M43 858L153 901M57 926L159 960M184 931L285 893" stroke="#e6a37e" opacity=".35" stroke-width="3"/>
<path d="M584 914L757 814L872 855V1118H597Z" fill="#9c6c6c"/>
<path d="M584 914L757 814L872 855L710 952Z" fill="#ddb48a"/>
<path d="M710 952L872 855V1118H708Z" fill="#664e62"/>
<path d="M362 1004L443 969L505 1000L422 1038Z" fill="#f2c28e"/>
<path d="M362 1004V1055L422 1090L505 1049V1000L422 1038Z" fill="#a77472"/>
<path d="M448 926L496 902L535 926L486 953Z" fill="#eac492"/>
<path d="M448 926V958L486 979L535 953V926L486 953Z" fill="#b57b73"/>
<path d="M535 872L565 854L591 870L561 890Z" fill="#f1d2a2"/>
<path d="M535 872V891L561 910L591 889V870L561 890Z" fill="#c08f83"/>'''
    arch='''<path d="M144 792V658Q144 602 195 602Q246 602 246 658V817L218 829V659Q218 629 195 629Q172 629 172 659V805Z" fill="#efd4a9"/>
<path d="M157 792V659Q157 615 195 615Q232 615 232 659V815" fill="none" stroke="#9fe3d4" stroke-width="3"/>
<path d="M184 692L195 681L206 692L195 703Z" fill="#a6e9df"/>
<path d="M190 714L195 709L200 714L195 719Z" fill="#a6e9df" opacity=".6"/>'''
    palms=palm(794,845,.75)+palm(79,825,.55)+palm(844,885,.58)
    fore='''<path d="M28 1057L134 1009L239 1066L293 1117H28Z" fill="#132c3e"/><path d="M611 1117L720 1029L793 1060L872 1000V1117Z" fill="#132c3e"/>
<path d="M57 1091L43 1028L81 1069L87 1012L108 1078L145 1047L129 1117Z" fill="#1d4951"/>
<path d="M760 1117L764 1054L784 1082L814 1025L806 1084L843 1065L825 1117Z" fill="#204c51"/>'''
    if theme=='wonder':
        sun=sun.replace('645','255').replace('525','535').replace('#f1c19a','#d2c5ee')
        arch=arch.replace('144','614').replace('195','665').replace('246','716').replace('218','688').replace('172','642').replace('157','627').replace('232','702').replace('184','654').replace('206','676').replace('190','660').replace('200','670')
        arch='<g transform="translate(30 100)">'+arch+'</g>'
        # Distinct, original palette and framing, not franchise imagery.
        horizon=horizon.replace('#526776','#606c84').replace('#355267','#414d70').replace('#203c53','#2a3b5a')
    return '<g clip-path="url(#frame)">'+sky+stars()+sun+horizon+rocks+arch+palms+fore+'</g>'


def front(title, ident, theme):
    s=start(900,1260,title)
    s+='<rect width="900" height="1260" rx="22" fill="url(#body)"/><rect x="28" y="28" width="844" height="1204" rx="16" fill="none" stroke="#a4cbd0" stroke-opacity=".25"/>'
    s+='<path d="M56 76H88L100 56H68Z" fill="#83dcca"/>'
    s+=text('RETRO PASS ULTIMATE',116,77,19,tracking=1.7,display=True)+text('ARQUIVO VISUAL',844,76,21,'#8fadb9',tracking=3,anchor='end')
    s+='<path d="M56 107H844" stroke="#b8d8d6" stroke-opacity=".23"/>'
    s+=text(title,52,223,85 if len(title)<10 else 70,tracking=-2,display=True)
    s+=text('ESTUDO DE CAPA · PAISAGEM ORIGINAL',57,276,24,'#9bc8c6',tracking=2)
    s+=scene(theme)
    s+='<rect x="56" y="373" width="221" height="40" rx="20" fill="#14283b" fill-opacity=".84" stroke="#f2ceaa" stroke-opacity=".35"/>'
    s+=text('EXPERIMENTO '+ident,166,400,17,'#f2ceaa',tracking=1.8,anchor='middle')
    s+='<path d="M56 1149H844" stroke="#b7d7d7" stroke-opacity=".3"/>'
    s+=text('ESTUDO FICTÍCIO / NÃO OFICIAL',450,1192,29,'#f2d9b3',tracking=1.6,anchor='middle')
    s+=text('SEM ROM  ·  SEM EDIÇÃO COMERCIAL ATRIBUÍDA',450,1220,15,'#8ca7b6',tracking=2,anchor='middle')
    return s+'</svg>'


def back(title, ident, theme):
    s=start(900,1260,title+' • verso')+'<rect width="900" height="1260" rx="22" fill="url(#body)"/><rect width="900" height="1260" rx="22" fill="url(#grid)"/>'
    s+='<rect x="28" y="28" width="844" height="1204" rx="16" fill="none" stroke="#a4cbd0" stroke-opacity=".25"/>'
    s+=text('RETRO PASS ULTIMATE / OBJETO '+ident,56,81,21,'#9accc8',tracking=2)
    s+=text(title,54,173,63 if len(title)<10 else 54,tracking=-1.6,display=True)
    s+=text('UM MUNDO PARA CONTEMPLAR.',56,233,28,'#f3cea4',tracking=1.6)
    for j,line in enumerate(['Esta paisagem foi desenhada para explorar a forma,', 'a luz e a presença de uma caixa na biblioteca 3D.', 'É uma interpretação visual original, não uma capa', 'comercial, edição identificada ou material oficial.']):
        s+=text(line,56,295+j*36,25,'#c1d0d9')
    # Original artwork strips, not screenshots of a game.
    s+='<g clip-path="url(#detail)"><g transform="translate(29.858 -202.551) scale(0.933649)">'+scene(theme)+'</g></g>'
    s+='<rect x="56" y="465" width="788" height="305" rx="4" fill="none" stroke="#aacbc7" stroke-opacity=".35"/>'
    s+=text('DETALHE DA ILUSTRAÇÃO ORIGINAL · NÃO É CAPTURA DE JOGO',450,803,18,'#8fafbc',tracking=.8,anchor='middle')
    for x,number,head,body in [(56,'01','FRENTE','Arte vetorial original'),(325,'02','LOMBADA','Objeto tridimensional'),(594,'03','VERSO','Projeto demonstrativo')]:
        s+=text(number,x,881,31,'#79cdbf',display=True)
        s+=text(head,x,921,23,'#e8d7be',tracking=2)
        s+=text(body,x,954,18,'#a9bcc8')
    s+='<path d="M56 1001H844" stroke="#9ec3c8" stroke-opacity=".3"/>'
    s+=text('ESTUDO FICTÍCIO / NÃO OFICIAL',450,1057,29,'#f2d9b3',tracking=1.5,anchor='middle')
    for j,line in enumerate(['Nenhuma ROM, emulação ou integração de conta.', 'Não implica licença, parceria ou endosso dos titulares.', 'O nome do jogo é uma referência na interface.']):
        s+=text(line,450,1101+j*31,22,'#a6bac6',anchor='middle')
    s+=text('MODELO VISUAL',56,1211,17,'#79cdbf',tracking=3)+text('SÉRIE EXPERIMENTAL / '+ident,844,1211,17,'#8fa6b4',tracking=2,anchor='end')
    return s+'</svg>'


def spine(title, ident):
    s=start(160,1260,title+' • lombada')+'<rect width="160" height="1260" fill="url(#body)"/><path d="M11 0V1260M149 0V1260" stroke="#99c8c8" stroke-opacity=".25"/>'
    s+='<path d="M46 77H85L104 49H65Z" fill="#82d7c7"/>'
    s+=text('RETRO PASS ULTIMATE',80,130,9.5,'#cad9d8',tracking=.15,display=True,anchor='middle')
    s+='<g transform="translate(80 240) rotate(90)">'+text(title,0,15,64 if len(title)<10 else 52,'#f1e2c9',tracking=2,display=True)+'</g>'
    s+='<g transform="translate(80 1165) rotate(-90)">'+text('FICTÍCIO / NÃO OFICIAL',0,8,21,'#84c3c3',tracking=1.5)+'</g>'
    s+=text(ident,80,1220,23,'#e1cda9',display=True,anchor='middle')
    return s+'</svg>'


def edge(ident):
    s=start(900,160,'RETRO PASS ULTIMATE '+ident+' • borda')+'<rect width="900" height="160" fill="#101d30"/><path d="M28 26H872M28 134H872" stroke="#7eb7b4" stroke-opacity=".25"/>'
    s+=text('RETRO PASS ULTIMATE',56,94,23,'#89bdbb',tracking=2,display=True)+text('FICTÍCIO / '+ident,844,94,27,'#b1c2ca',tracking=3,anchor='end')
    return s+'</svg>'


if __name__=='__main__':
    for slug,title,ident,theme in [('alex_kidd','ALEX KIDD','01','alex'),('wonder_boy','WONDER BOY','02','wonder')]:
        for face,contents in [('front',front(title,ident,theme)),('back',back(title,ident,theme)),('spine',spine(title,ident)),('edge',edge(ident))]:
            target=ROOT/f'{slug}_{face}.svg'
            target.write_text(contents,encoding='utf-8')
            print(target.name)
