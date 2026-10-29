# /// script
# requires-python = ">=3.11"
# dependencies = ["vtracer", "numpy", "pillow", "resvg-py", "fonttools"]
# ///
"""Run: uv run assets/brand/vstupenky-online/tools/build_vectors.py"""
from pathlib import Path
import tempfile, json, base64
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image
import vtracer, resvg_py

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'concepts/selected-wide-no-head.png'
NAVY, BLUE = '#19243b', '#80bdf2'
NS = '{http://www.w3.org/2000/svg}'
original = np.asarray(Image.open(SOURCE).convert('RGB')).astype(float)
# Nearest-color segmentation discards generated lighting while retaining silhouette.
palette = np.array([[255,255,255],[25,36,59],[113,184,241]])
labels = ((original[:,:,None,:] - palette[None,None,:,:]) ** 2).sum(axis=3).argmin(axis=2)
# Generated image has a faint border. It is outside the logo's clear space.
labels[:30,:] = labels[-30:,:] = 0
labels[:,:30] = labels[:,-30:] = 0
layers = {}
with tempfile.TemporaryDirectory(prefix='vo-vector-') as temp:
    for name, color, area in [('ticket',1,(0,580)),('center',2,(0,580)),('name',1,(580,1024)),('domain',2,(580,1024))]:
        mask = labels == color
        if color == 2:
            allowed = np.zeros(mask.shape,dtype=bool)
            allowed[240:480,370:655] = True
            allowed[735:900,190:835] = True
            mask &= allowed
        mask[:area[0],:] = False
        mask[area[1]:,:] = False
        src, dst = Path(temp)/(name+'.png'), Path(temp)/(name+'.svg')
        Image.fromarray(np.where(mask,0,255).astype('uint8')).save(src)
        vtracer.convert_image_to_svg_py(str(src),str(dst),colormode='binary',mode='spline',filter_speckle=8,corner_threshold=60,length_threshold=3.5,max_iterations=10,splice_threshold=45,path_precision=3)
        paths=[]
        for path in ET.parse(dst).getroot().iter(NS+'path'):
            attrs=' '.join(f'{key}="{value}"' for key,value in path.attrib.items() if key not in ('fill','stroke'))
            paths.append('<path '+attrs+'/>')
        layers[name]=''.join(paths)

# Precisely mapped clean geometry: mirror the ticket halves and use exact circles
# for the side notches rather than retaining raster edge noise.
left='M250 254H307L494 563H250C220.177 563 196 538.823 196 509V464C229.137 464 256 437.137 256 405C256 372.863 229.137 346 196 346V308C196 278.177 220.177 254 250 254Z'
layers['ticket']=f'<path d="{left}"/><path d="{left}" transform="translate(1024 0) scale(-1 1)"/>'
layers['center']='<path d="M378 254H646L512 472Z"/>'

# Typography is the exact Roboto Bold font from the user-selected landing preview.
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen
font=TTFont(ROOT/'source/Roboto-Bold.ttf'); glyphs=font.getGlyphSet(); cmap=font.getBestCmap(); upm=font['head'].unitsPerEm
def lettering(text, x, y, width, height):
    paths=[]; pos=0; bounds=[]
    for ch in text:
        glyph=glyphs[cmap[ord(ch)]]; pen=SVGPathPen(glyphs)
        glyph.draw(TransformPen(pen,(1,0,0,-1,pos,0)))
        paths.append('<path d="'+pen.getCommands()+'"/>')
        bp=BoundsPen(glyphs); glyph.draw(bp)
        if bp.bounds:
            x0,y0,x1,y1=bp.bounds; bounds.append((x0+pos,-y1,x1+pos,-y0))
        pos+=glyph.width-upm*.035
    x0=min(b[0] for b in bounds); y0=min(b[1] for b in bounds); x1=max(b[2] for b in bounds); y1=max(b[3] for b in bounds)
    scale=min(width/(x1-x0),height/(y1-y0))
    tx=x+(width-(x1-x0)*scale)/2; ty=y+(height-(y1-y0)*scale)/2
    return f'<g transform="translate({tx:.4f} {ty:.4f}) scale({scale:.7f}) translate({-x0} {-y0})">'+''.join(paths)+'</g>'
layers['name']=lettering('vstupenky',82,598,872,166)
layers['domain']=lettering('.online',210,778,604,122)

def group(name,color):return f'<g id="{name}" fill="{color}">{layers[name]}</g>'
def svg(body,title,box='0 0 1024 1024',size=(1024,1024)):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" viewBox="{box}" role="img" aria-label="{title}"><title>{title}</title>{body}</svg>\n'
def save(name,s,render=True):
    (ROOT/(name+'.svg')).write_text(s)
    if render:(ROOT/(name+'.png')).write_bytes(resvg_py.svg_to_bytes(svg_string=s))
    return s
logos={}
for dark in [False,True]:
    suffix='-dark' if dark else ''
    ink='#ffffff' if dark else NAVY
    background=NAVY if dark else '#ffffff'
    mark=group('ticket',ink)+group('center',BLUE)
    lettering_paths=group('name',ink)+group('domain',BLUE)
    body=mark+lettering_paths
    square=save('vstupenky-online-square'+suffix,svg(f'<path fill="{background}" d="M0 0H1024V1024H0Z"/>'+body,'vstupenky.online'))
    logos['dark' if dark else 'light']=square
    header=f'<g transform="translate(16 14) scale(.65) translate(-196 -254)">{mark}</g><g transform="translate(470 14) scale(.65) translate(-82 -598)">{lettering_paths}</g>'
    save('vstupenky-online-header'+suffix,svg(header,'vstupenky.online','0 0 1060 230',(1060,230)))

    save('vstupenky-online-transparent'+suffix,svg(body,'vstupenky.online'),False)
    icon_body=f'<path fill="{background}" d="M0 0H1024V1024H0Z"/><g transform="translate(102.4 311.7) scale(1.2962) translate(-196 -254)">{mark}</g>'
    icon=save('vstupenky-online-icon'+suffix,svg(icon_body,'vstupenky.online - symbol'))
    save('vstupenky-online-symbol'+suffix,svg(mark,'vstupenky.online - symbol','170 225 685 365',(685,365)),False)
    save('vstupenky-online-wordmark'+suffix,svg(lettering_paths,'vstupenky.online','65 580 900 330',(900,330)))
    for size in [300,400]:
        (ROOT/f'vstupenky-online-linkedin-{size}{suffix}.png').write_bytes(resvg_py.svg_to_bytes(svg_string=square,width=size,height=size))
    for size in [32,64,180]:
        (ROOT/f'vstupenky-online-icon-{size}{suffix}.png').write_bytes(resvg_py.svg_to_bytes(svg_string=icon,width=size,height=size))

icons=ROOT/'web-icons'; icons.mkdir(exist_ok=True)
icon_svg=(ROOT/'vstupenky-online-icon-dark.svg').read_text()
for name,size in [('favicon-16x16.png',16),('favicon-32x32.png',32),('android-chrome-192x192.png',192),('android-chrome-512x512.png',512),('apple-touch-icon.png',180)]:
    (icons/name).write_bytes(resvg_py.svg_to_bytes(svg_string=icon_svg,width=size,height=size))
Image.open(icons/'android-chrome-512x512.png').save(icons/'favicon.ico',format='ICO',sizes=[(16,16),(32,32),(48,48)])

# Compare the rendered foreground silhouette with the source color segmentation.
import io
render=np.asarray(Image.open(io.BytesIO(resvg_py.svg_to_bytes(svg_string=logos['light']))).convert('RGB'))
render_mask=(render.min(axis=2)<210)
source_mask=(labels>0)
intersection=int((render_mask&source_mask).sum());union=int((render_mask|source_mask).sum())
report={'reference':str(SOURCE.relative_to(ROOT)),'method':'analytically mapped ticket; lettering outlined from Roboto Bold, matching the selected landing preview','foreground_intersection_over_union':round(intersection/union,5),'embedded_raster_images':0,'live_text_elements':0,'note':'Flat canonical colors replace generated gradients, highlights and texture. Symbol follows source geometry; Roboto Bold lettering replaces the generated lettering by explicit user request. Whole-logo overlap therefore includes an intentional typography change.'}
(ROOT/'vector-verification.json').write_text(json.dumps(report,indent=2)+'\n')

def data(s):return 'data:image/svg+xml;base64,'+base64.b64encode(s.encode()).decode()
reference='data:image/png;base64,'+base64.b64encode(SOURCE.read_bytes()).decode()
html='''<!doctype html><html lang="cs"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>vstupenky.online - finální SVG</title><style>*{box-sizing:border-box}body{margin:0;background:#ebf1f6;color:#19243b;font:17px/1.5 system-ui,sans-serif}main{max-width:1240px;margin:auto;padding:36px 24px}h1{font-size:30px;letter-spacing:-.03em;margin:0 0 12px}p{max-width:75ch}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:28px;margin:28px 0}figure{margin:0}img{display:block;width:100%;height:auto}figcaption{padding:12px 0}a{color:#4465a6;text-underline-offset:4px}.links{display:flex;gap:18px;flex-wrap:wrap}a:focus-visible{outline:3px solid #4465a6;outline-offset:4px}::selection{background:#80bdf2;color:#19243b}.icon{width:160px;height:160px}.proof{display:grid;grid-template-columns:1fr 1fr;gap:12px}h2{font-size:23px}@media(max-width:680px){main{padding:24px 16px}.grid{grid-template-columns:1fr}}</style><main><h1>vstupenky.online</h1><p>Vybraná širší varianta bez hlavičky. Skutečné SVG cesty, nápis v písmu Roboto Bold z vybraného návrhu landing page. Světlá a tmavá verze mají totožnou geometrii; barvy jsou sjednocené s landing page.</p><div class="grid"><figure><img src="LIGHT" alt="Světlé SVG logo"><figcaption>Světlá verze</figcaption><div class="links"><a href="vstupenky-online-square.svg" download>SVG</a><a href="vstupenky-online-transparent.svg" download>SVG bez pozadí</a><a href="vstupenky-online-linkedin-400.png" download>PNG pro LinkedIn</a></div></figure><figure><img src="DARK" alt="Tmavé SVG logo"><figcaption>Tmavá verze</figcaption><div class="links"><a href="vstupenky-online-square-dark.svg" download>SVG</a><a href="vstupenky-online-transparent-dark.svg" download>SVG bez pozadí</a><a href="vstupenky-online-linkedin-400-dark.png" download>PNG pro LinkedIn</a></div></figure></div><h2>Samostatný symbol</h2><div class="grid"><figure><img class="icon" src="vstupenky-online-icon.svg" alt="Světlá ikona"><figcaption><a href="vstupenky-online-symbol.svg" download>Symbol SVG bez pozadí</a></figcaption></figure><figure><img class="icon" src="vstupenky-online-icon-dark.svg" alt="Tmavá ikona"><figcaption><a href="vstupenky-online-symbol-dark.svg" download>Symbol SVG pro tmavé pozadí</a></figcaption></figure></div><h2>Předloha a vektorové zpracování</h2><p>Vlevo stažený koncept, vpravo SVG. Rastrová textura a odlesky jsou odstraněné. Symbol má čistou geometrii a nápis používá Roboto Bold z vybrané landing page.</p><div class="proof"><figure><img src="REFERENCE" alt="Původní rastrová předloha"><figcaption>Předloha z ChatGPT</figcaption></figure><figure><img src="LIGHT" alt="Vektorové obrysy"><figcaption>SVG - ploché barvy</figcaption></figure></div><p>Na web ani LinkedIn zatím nenasazeno.</p></main></html>'''
(ROOT/'preview.html').write_text(html.replace('LIGHT',data(logos['light'])).replace('DARK',data(logos['dark'])).replace('REFERENCE',reference))
# Rebuild the selected tenant's source adapters alongside the vector masters.
import shutil
adapters=ROOT.parents[1]/'icons'
for source,target in [('header','vstupenky.svg'),('header-dark','vstupenky.dark.svg'),('symbol','vstupenky-symbol.svg'),('symbol-dark','vstupenky-symbol.dark.svg'),('icon-dark','vstupenky-icon.svg')]:
    shutil.copyfile(ROOT/f'vstupenky-online-{source}.svg',adapters/target)
print(f'Vectors and exports ready; foreground silhouette IoU: {intersection/union:.2%}.')
