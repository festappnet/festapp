# /// script
# requires-python = ">=3.11"
# dependencies = ["fonttools", "skia-pathops", "resvg-py", "pillow"]
# ///
"""Build the global Festapp Tickets identity. No production adapters are changed."""
from pathlib import Path
import base64, copy, hashlib, json, re, zipfile
import xml.etree.ElementTree as ET
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import SVGPath, parse_path
import pathops, resvg_py
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
REGIONAL=ROOT.parent/'vstupenky-online'
NS='{http://www.w3.org/2000/svg}'
NAVY,BLUE='#19243b','#80bdf2'
SOURCE=ROOT/'source/Festapp_Tickets_asymmetric.svg'
FONT=REGIONAL/'source/Roboto-Bold.ttf'
font=TTFont(FONT);glyphs=font.getGlyphSet();cmap=font.getBestCmap();upm=font['head'].unitsPerEm

def path(d):
 p=pathops.Path();parse_path(d,p.getPen());return p

def dstring(p):
 pen=SVGPathPen(None);p.draw(pen);return pen.getCommands()

def union(parts):
 p=pathops.Path()
 for part in parts:p=pathops.op(p,part,pathops.PathOp.UNION)
 return p

def transformed(p,t):
 out=pathops.Path();p.draw(TransformPen(out.getPen(),t));return out

def bounds(p):
 pen=BoundsPen(None);p.draw(pen);return pen.bounds

# The approved regional SVG owns the curves, corner radii and side notches.
# Union its actual mirrored ticket halves with the central rectangle to recover
# the complete outer envelope. Only the interior separator differs globally.
regional=ET.parse(REGIONAL/'vstupenky-online-symbol.svg').getroot()
regional_group=next(x for x in regional if x.get('id')=='ticket')
regional_halves=[]
for el in regional_group:
 wrapper=ET.Element(NS+'svg');node=copy.deepcopy(el)
 if node.get('transform')=='translate(1024 0) scale(-1 1)':node.set('transform','matrix(-1 0 0 1 1024 0)')
 wrapper.append(node);p=pathops.Path();SVGPath.fromstring(ET.tostring(wrapper)).draw(p.getPen());regional_halves.append(p)
left_bounds=bounds(regional_halves[0]);right_bounds=bounds(regional_halves[1])
assert left_bounds==(196.0,254.0,494.0,563.0), 'Review changed regional master before rebuilding'
assert right_bounds==(530.0,254.0,828.0,563.0)
envelope=union(regional_halves+[path('M256 254H768V563H256Z')])
# Internal edge control points are taken from the supplied asymmetric source.
upload=ET.parse(SOURCE).getroot()
original_left=upload.find(".//*[@id='navy-half']").get('d')
original_right=upload.find(".//*[@id='blue-half']").get('d')
# Guard the source contract rather than silently ignoring a revised upload.
assert 'L488 216 H409 C395 216 390 222 384 234 L326 361' in original_left
assert 'L407 241 H486 C498 241 505 234 509 225' in original_right
sx,sy=632/494,309/244
mapping=(sx,0,0,sy,196-190*sx,254-117*sy)
left_region=path('M0 0H534V117L488 216H409C395 216 390 222 384 234L326 361V500H0Z')
right_region=path('M561 0H900V500H352V361L407 241H486C498 241 505 234 509 225L561 117Z')
left=pathops.op(envelope,transformed(left_region,mapping),pathops.PathOp.INTERSECTION)
right=pathops.op(envelope,transformed(right_region,mapping),pathops.PathOp.INTERSECTION)
layers={'ticket':dstring(left),'center':dstring(right)}

# Each complete word is a boolean-unioned path from the exact canonical font.
baselines={}
def lettering(text,x,y,width,height):
 parts=[];cursor=0
 for ch in text:
  g=glyphs[cmap[ord(ch)]];p=pathops.Path();g.draw(TransformPen(p.getPen(glyphs),(1,0,0,-1,cursor,0)));parts.append(p)
  cursor+=g.width-upm*.035
 word=union(parts);x0,y0,x1,y1=bounds(word);scale=min(width/(x1-x0),height/(y1-y0))
 baselines[text]=y+(height-(y1-y0)*scale)/2-y0*scale
 return dstring(transformed(word,(scale,0,0,scale,x+(width-(x1-x0)*scale)/2-x0*scale,y+(height-(y1-y0)*scale)/2-y0*scale)))
layers['name']=lettering('Festapp',82,600,860,170)
layers['domain']=lettering('Tickets',180,795,664,130)

# Header variants preserve the reference's visible height and icon-to-text gap.
regional_words=ET.parse(REGIONAL/'vstupenky-online-wordmark.svg').getroot()
def svg_bounds(element):
 wrapper=ET.Element(NS+'svg');wrapper.append(copy.deepcopy(element))
 p=pathops.Path();SVGPath.fromstring(ET.tostring(wrapper)).draw(p.getPen())
 return bounds(p)
reference_words=svg_bounds(regional_words)
reference_name=svg_bounds(next(e for e in regional_words if e.get('id')=='name'))
reference_box=list(map(float,regional_words.get('viewBox').split()))
name_bounds=bounds(path(layers['name']))
word_bounds=bounds(union([path(layers['name']),path(layers['domain'])]))
header_scale=(reference_words[3]-reference_words[1])/(word_bounds[3]-word_bounds[1])
word_center=(word_bounds[0]+word_bounds[2])/2
header_first_x=word_center+(name_bounds[0]-word_center)*header_scale
header_box=[header_first_x-(reference_name[0]-reference_box[0]),*reference_box[1:]]
header_transform=f'translate({word_center} {reference_words[1]}) scale({header_scale}) translate({-word_center} {-word_bounds[1]})'


def group(name,color):return f'<g id="{name}" fill="{color}"><path d="{layers[name]}"/></g>'
def svg(body,title='Festapp Tickets',box='0 0 1024 1024',size=(1024,1024)):
 return f'<svg xmlns="http://www.w3.org/2000/svg" width="{size[0]}" height="{size[1]}" viewBox="{box}" role="img" aria-label="{title}"><title>{title}</title>{body}</svg>\n'
def save(name,s,render=True):
 (ROOT/(name+'.svg')).write_text(s)
 if render:(ROOT/(name+'.png')).write_bytes(resvg_py.svg_to_bytes(svg_string=s))
 return s
prefix='festapp-tickets'
for dark in (False,True):
 suffix='-dark' if dark else '';ink='#ffffff' if dark else NAVY;bg=NAVY if dark else '#ffffff'
 mark=group('ticket',ink)+group('center',BLUE);words=group('name',ink)+group('domain',BLUE)
 square=save(prefix+'-square'+suffix,svg(f'<path fill="{bg}" d="M0 0H1024V1024H0Z"/>'+mark+words))
 save(prefix+'-transparent'+suffix,svg(mark+words))
 save(prefix+'-symbol'+suffix,svg(mark,'Festapp Tickets - symbol','170 225 685 365',(685,365)))
 save(prefix+'-wordmark'+suffix,svg(words,'Festapp Tickets - wordmark','65 580 900 370',(900,370)))
 save(prefix+'-wordmark-stacked-header'+suffix,svg(f'<g transform="{header_transform}">{words}</g>','Festapp Tickets - stacked header wordmark',' '.join(str(v) for v in header_box),(900,330)))
 # Align the actual font baselines, not the bounding boxes (Festapp has descenders).
 horizontal=group('name',ink)+f'<g transform="translate(628.4381866455078 {baselines["Festapp"]-baselines["Tickets"]})">'+group('domain',BLUE)+'</g>'
 save(prefix+'-wordmark-horizontal'+suffix,svg(horizontal,'Festapp Tickets - horizontal wordmark','126 580 1320 200',(1320,200)))
 header=f'<g transform="translate(16 14) scale(.65) translate(-196 -254)">{mark}</g><g transform="translate(470 14) scale(.65) translate(-82 -600)">{words}</g>'
 save(prefix+'-header'+suffix,svg(header,'Festapp Tickets','0 0 1060 240',(1060,240)))
 icon=f'<path fill="{bg}" d="M0 0H1024V1024H0Z"/><g transform="translate(102.4 311.7) scale(1.2962) translate(-196 -254)">{mark}</g>'
 icon_svg=save(prefix+'-icon'+suffix,svg(icon,'Festapp Tickets - icon'))
 for n in (300,400):(ROOT/f'{prefix}-linkedin-{n}{suffix}.png').write_bytes(resvg_py.svg_to_bytes(svg_string=square,width=n,height=n))
 for n in (32,64,180):(ROOT/f'{prefix}-icon-{n}{suffix}.png').write_bytes(resvg_py.svg_to_bytes(svg_string=icon_svg,width=n,height=n))
 # The social image is deliberately simple, with the actual logo as its content.
 social=f'<path fill="{bg}" d="M0 0H1200V630H0Z"/><g transform="translate(310 -20) scale(.57)">{mark+words}</g>'
 save(prefix+'-social'+suffix,svg(social,'Festapp Tickets','0 0 1200 630',(1200,630)))

# Both products use one outline/fill animation generator and timing contract.
# The global loading identity is the symbol alone, with its canonical viewport.
timeline=json.loads((REGIONAL/'source/loading-timeline.json').read_text())
timeline['viewBox']=[170,225,685,365]
timeline['parts']={name:timeline['parts'][name] for name in ('ticket','center')}
(ROOT/'source/loading-timeline.json').write_text(json.dumps(timeline,indent=2)+'\n')
import sys
sys.path.insert(0,str(REGIONAL/'tools'))
from outline_animation import emit_outline_assets
emit_outline_assets(ROOT,prefix='festapp-tickets',title='Festapp Tickets',
                    dart_prefix='_globalBrand',dart_filename='brand_loading_global_paths.dart')
icons=ROOT/'web-icons';icons.mkdir(exist_ok=True)
icon_svg=(ROOT/f'{prefix}-icon-dark.svg').read_text()
for filename,n in [('favicon-16x16.png',16),('favicon-32x32.png',32),('android-chrome-192x192.png',192),('android-chrome-512x512.png',512),('apple-touch-icon.png',180)]:
 (icons/filename).write_bytes(resvg_py.svg_to_bytes(svg_string=icon_svg,width=n,height=n))
Image.open(icons/'android-chrome-512x512.png').save(icons/'favicon.ico',format='ICO',sizes=[(16,16),(32,32),(48,48)])

(icons/'site.webmanifest').write_text(json.dumps({
 'name':'Festapp Tickets','short_name':'Festapp Tickets',
 'start_url':'https://tickets.festapp.net/','scope':'https://tickets.festapp.net/',
 'display':'standalone','background_color':NAVY,'theme_color':NAVY,
 'icons':[{'src':f'android-chrome-{n}x{n}.png','sizes':f'{n}x{n}','type':'image/png','purpose':'any'} for n in (192,512)]
},indent=2)+'\n')


# Audit the uploaded glyph contours against the font, before normalization.
font_audit=[]
for ident,text in [('word-festapp','Festapp'),('word-tickets','Tickets')]:
 row=next(el for el in upload if el.get('id')==ident)
 assert len(row)==len(text)
 for ch,el in zip(text,row):
  actual=path(el.get('d'));expected=pathops.Path();glyphs[cmap[ord(ch)]].draw(expected.getPen(glyphs));area=pathops.op(actual,expected,pathops.PathOp.XOR).area
  font_audit.append({'character':ch,'difference_area_font_units_squared':round(area,6),'reference_area':round(expected.area,6),'exact_match':area<.001})
# Exterior evidence: the clipped halves must reproduce the original envelope
# exactly in the complete left and right edge bands (including all corner curves).
mark_union=union([left,right]);edge_band=union([path('M0 0H307V1024H0Z'),path('M717 0H1024V1024H717Z')])
edge_difference=pathops.op(pathops.op(mark_union,edge_band,pathops.PathOp.INTERSECTION),pathops.op(union(regional_halves),edge_band,pathops.PathOp.INTERSECTION),pathops.PathOp.XOR).area
outside_area=pathops.op(mark_union,envelope,pathops.PathOp.DIFFERENCE).area
assert edge_difference<.01 and outside_area<.01
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report={'reference':'../vstupenky-online/vstupenky-online-symbol.svg','reference_sha256':sha(REGIONAL/'vstupenky-online-symbol.svg'),'uploaded_source_sha256':sha(SOURCE),'canonical_font':'../vstupenky-online/source/Roboto-Bold.ttf','canonical_font_sha256':sha(FONT),'uploaded_glyph_comparisons':font_audit,'uploaded_symbol_bounds':[190,117,684,361],'canonical_envelope_bounds':list(bounds(envelope)),'uploaded_notch_half_width':48,'canonical_notch_half_width':60,'uploaded_left_corner_extent':47,'uploaded_right_corner_extent':49,'canonical_corner_extent':54,'normalization':'Canonical regional outer envelope; preserve and map uploaded stepped interior edges to envelope bounds; regenerate complete word contours from the canonical Roboto Bold font.','outer_edge_bands':[ [0,307],[717,1024] ],'outer_edge_xor_area':edge_difference,'outside_envelope_area':outside_area,'lettering_tracking_em':-.035,'lettering_paths_per_row':1,'glyph_overlap_boundaries_removed':True,'embedded_raster_images':0,'live_text_elements':0,'status':'canonical global source assets; production deployment not performed'}
(ROOT/'vector-verification.json').write_text(json.dumps(report,indent=2)+'\n')
# Diagnostic overlays use actual path geometry, with the upload normalized to
# the canonical width/height. They are proof artifacts, not production logos.
proof=ROOT/'proof';proof.mkdir(exist_ok=True)
upload_envelope=transformed(union([path(original_left),path(original_right),path('M238 117H636V361H238Z')]),mapping)
for label,outline in [('uploaded',upload_envelope),('normalized',envelope)]:
 overlay=f'<path fill="white" d="M0 0H1024V1024H0Z"/><path d="{dstring(envelope)}" fill="none" stroke="{NAVY}" stroke-width="2"/><path d="{dstring(outline)}" fill="none" stroke="#c45121" stroke-width="1"/>'
 (proof/(label+'-outer-overlay.svg')).write_text(svg(overlay,'Canonical outline (navy) and '+label+' outline (orange)','180 235 664 350',(996,525)))

# No fonts or rendering dependencies are needed by exported assets.
(ROOT/'usage.txt').write_text('Festapp Tickets\nContact: info@festapp.net\nNavy: #19243b; blue: #80bdf2.\nUse *-dark files on dark surfaces. Transparent and symbol assets have no background.\nPreserve aspect ratio, side notches, canonical corner curves and the asymmetric separator. Do not recolor individual fragments or replace outlined lettering. Use icon/web-icons exports at small sizes.\nSVG masters contain real paths and require no external fonts. Loading SVG respects reduced motion.\n')
files=sorted([p for p in ROOT.glob(prefix+'*') if p.suffix in ('.svg','.png')]+list(icons.iterdir())+[ROOT/'usage.txt'])
manifest={str(p.relative_to(ROOT)):sha(p) for p in files};(ROOT/'export-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
with zipfile.ZipFile(ROOT/(prefix+'-logos.zip'),'w',zipfile.ZIP_DEFLATED) as z:
 for p in files:z.write(p,p.relative_to(ROOT))
 z.write(ROOT/'export-manifest.json','export-manifest.json')
print(f'Built {len(files)} deliverables; outer-edge XOR area {edge_difference:g}; uploaded matching glyphs {sum(x["exact_match"] for x in font_audit)}/{len(font_audit)}.')
