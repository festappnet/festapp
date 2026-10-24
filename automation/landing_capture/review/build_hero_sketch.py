#!/usr/bin/env python3
"""Build product-inspired line drawings: two independently persistent drawing lanes."""
from pathlib import Path
import json, math, re
ROOT=Path(__file__).resolve().parents[3]
doc=json.loads((ROOT/'automation/release/organizers/hero-large-hall.json').read_text())
def rect(x,y,w,h):return f'M{x:.2f} {y:.2f}h{w:.2f}v{h:.2f}h{-w:.2f}Z'
def circle(x,y,r):return f'M{x+r:.2f} {y:.2f}a{r:.2f} {r:.2f} 0 1 1 {-2*r:.2f} 0a{r:.2f} {r:.2f} 0 1 1 {2*r:.2f} 0'
def path(d,fill=False):return f'<path pathLength="1" vector-effect="non-scaling-stroke" class="{"sketch-fill" if fill else "sketch-line"}" d="{d}"/>'
def seat(x,y,r=5):return path(circle(x,y,r),True)
def table(x,y,w=40,h=24):
 p=[path(rect(x-w/2,y-h/2,w,h),True)]
 for sx,sy in [(-w*.3,-h/2-10),(w*.3,-h/2-10),(w/2+10,0),(w*.3,h/2+10),(-w*.3,h/2+10),(-w/2-10,0)]:p.append(seat(x+sx,y+sy))
 return p
def qr_paths(x,y,width):
 # Decorative QR mark, deliberately sparse; not a payment or scannable ticket.
 unit=width/17;p=[]
 for dx,dy in [(0,0),(10,0),(0,10)]:
  p.extend([path(rect(x+dx*unit,y+dy*unit,7*unit,7*unit)),path(rect(x+(dx+2)*unit,y+(dy+2)*unit,3*unit,3*unit),True)])
 for dx,dy,w,h in [(9,8,2,2),(13,9,4,2),(9,12,2,4),(13,13,2,2),(15,16,2,1)]:p.append(path(rect(x+dx*unit,y+dy*unit,w*unit,h*unit),True))
 return p
motifs=[]
def add(name,parts):motifs.append((name,''.join(parts)))
def template_paths(source):
 # Preserve real template coordinates, including recursive group transforms.
 ns={n['id']:n for n in source['nodes']}
 def pos(n):
  t=n['transform'];x,y,r=t.get('x',0),t.get('y',0),t.get('rotation',0)
  if n.get('parentId')in ns:
   px,py,pr=pos(ns[n['parentId']]);a=math.radians(pr)
   return px+x*math.cos(a)-y*math.sin(a),py+x*math.sin(a)+y*math.cos(a),pr+r
  return x,y,r
 cw=source['canvas']['width'];ch=source['canvas']['height'];seats=[n for n in ns.values()if n['kind']=='seat']
 # An enclosing room frame always contains the exact source seat footprint.
 bounds=[(pos(n)[0]-n['width']/2,pos(n)[1]-n['height']/2,pos(n)[0]+n['width']/2,pos(n)[1]+n['height']/2)for n in seats]
 minx=min([0]+[v[0]-12 for v in bounds]);miny=min([0]+[v[1]-12 for v in bounds]);maxx=max([cw]+[v[2]+12 for v in bounds]);maxy=max([ch]+[v[3]+12 for v in bounds])
 scale=min(280/(maxx-minx),365/(maxy-miny));ox=(300-(maxx-minx)*scale)/2;oy=(390-(maxy-miny)*scale)/2
 def mapped(x,y):return ox+(x-minx)*scale,oy+(y-miny)*scale
 p=[path(rect(ox,oy,(maxx-minx)*scale,(maxy-miny)*scale))]
 def draw_order(n):
  x,y,_=pos(n)
  if n['kind']!='seat':return (0,y,x,0)
  parent=ns.get(n.get('parentId'))
  if parent and parent['kind']=='table':
   px,py,_=pos(parent);return (1,py,px,math.atan2(y-py,x-px))
  row=re.match(r'\d+',str(n.get('label','')))
  return (1,int(row[0])if row else 999,x,y)
 for n in sorted(ns.values(),key=draw_order):
  if n['kind']not in ['table','seat','shape']:continue
  x,y,r=pos(n);x,y=mapped(x,y);w=n['width']*scale;h=n['height']*scale
  if n['kind']=='seat':
   radius=min(w,h)*.48
   assert x-radius>=ox and y-radius>=oy and x+radius<=ox+(maxx-minx)*scale and y+radius<=oy+(maxy-miny)*scale
   p.append(seat(x,y,radius));continue
  if n.get('role')=='obstacle':continue
  if n.get('points'):
   points=[]
   for px,py in n['points']:
    a=math.radians(r);points.append((x+(px*math.cos(a)-py*math.sin(a))*scale,y+(px*math.sin(a)+py*math.cos(a))*scale))
   p.append(path('M'+'L'.join(f'{px:.2f} {py:.2f}'for px,py in points)));continue
  if n.get('surface',{}).get('type')in ['circle','ellipse']or n.get('shape')in ['circle','ellipse']:
   p.append(path(f'M{x+w/2:.2f} {y:.2f}a{w/2:.2f} {h/2:.2f} 0 1 1 {-w:.2f} 0a{w/2:.2f} {h/2:.2f} 0 1 1 {w:.2f} 0',True));continue
  a=math.radians(r);points=[(x+px*math.cos(a)-py*math.sin(a),y+px*math.sin(a)+py*math.cos(a))for px,py in [(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2)]]
  p.append(path('M'+'L'.join(f'{px:.2f} {py:.2f}'for px,py in points)+'Z',True))
 return p
fixtures=ROOT/'automation/landing_capture/layout/fixtures'
add('modern-ball-template',template_paths(json.loads((fixtures/'vivid-document.cs.json').read_text())))
add('large-banquet-182',template_paths(doc))
p=[path('M0 125h300v48a18 18 0 0 0 0 36v48H0v-48a18 18 0 0 0 0-36Z',True),path('M220 125v132'),path('M20 153h160M20 169h110M20 230h65')]+qr_paths(235,165,50)
add('concert-ticket',p)
p=[path(rect(55,5,190,380),True),path(rect(65,15,170,360)),path('M90 80h120M90 96h88M100 118h100M110 260h80')]+qr_paths(112,282,76)
add('gala-ticket',p)
p=[path('M55 0H245V390H172M128 390H55V0'),path(rect(75,10,150,28),True)]
for y in [85,160,235,310]:p+=table(150,y,76,28)
add('long-corridor',p)
add('theatre-template',template_paths(json.loads((fixtures/'brand-theatre.cs.json').read_text())))
# A single shared lattice: the two legs and bridge meet on the same cell edges.
cell=21;gx=45;gy=65;cols=10;rows=12
occupied={(c,r)for c in range(cols)for r in range(rows)if c<2 or c>=8 or r>=10}
p=[path(f'M{gx} {gy}H{gx+2*cell}V{gy+(rows-2)*cell}H{gx+(cols-2)*cell}V{gy}H{gx+cols*cell}V{gy+rows*cell}H{gx}Z',True)]
edges={}
for c,r in occupied:
 x=gx+c*cell;y=gy+r*cell
 for a,b in [((x,y),(x+cell,y)),((x+cell,y),(x+cell,y+cell)),((x,y+cell),(x+cell,y+cell)),((x,y),(x,y+cell))]:
  edge=tuple(sorted((a,b)));edges[edge]=edges.get(edge,0)+1
for (a,b),count in sorted(edges.items()):
 if count==2:p.append(path(f'M{a[0]} {a[1]}L{b[0]} {b[1]}'))
for r in range(0,rows,2):
 y=gy+(r+1)*cell;p.extend([seat(gx-15,y),seat(gx+cols*cell+15,y)])
for c in range(0,cols,2):p.append(seat(gx+(c+1)*cell,gy+rows*cell+15))
assert all((gx+c*cell-gx)%cell==0 and (gy+r*cell-gy)%cell==0 for c,r in occupied)
add('grid-banquet-table',p)
add('cinema-template',template_paths(json.loads((fixtures/'brand-cinema.cs.json').read_text())))
add('ticket-qr',qr_paths(35,80,230))
p=[path('M0 100H300V270H0Z',True),path('M20 118h260M20 135h165M215 100v170'),path('M20 166h55M20 184h80M20 222h120')]+qr_paths(230,168,55)
for x in range(24,185,8):p.append(path(rect(x,240,2,12),True))
add('boarding-pass',p)
p=[path(rect(5,25,290,345)),path(rect(20,40,260,45),True),path('M40 60h110M40 73h75')]
for i in range(3):
 y=115+i*58;p.extend([path(f'M25 {y}h95'),path(rect(25,y+10,250,28),True)])
for i in range(2):p.extend([seat(32,305+i*23),path(f'M48 {305+i*23}h145')])
add('event-form',p)
p=[path(rect(5,55,290,280)),path(rect(20,75,78,38),True),path(rect(110,75,78,38),True),path(rect(200,75,78,38),True),path('M25 145v160h250M25 265h250M25 220h250M25 175h250'),path('M25 290 75 275 125 240 175 230 225 190 275 155')]
add('orders-report',p)
# Alternating product stories, no random flicker or synchronized clearing.
left=[0,2,4,6,8,10];right=[1,7,3,5,9,11]
hall_sizes={'large-banquet-182':sum(n['kind']=='seat'for n in doc['nodes'])}
for name,filename in [('modern-ball-template','vivid-document.cs.json'),('theatre-template','brand-theatre.cs.json'),('cinema-template','brand-cinema.cs.json')]:
 hall_sizes[name]=sum(n['kind']=='seat'for n in json.loads((fixtures/filename).read_text())['nodes'])
groups=[]
for side,indices in [('left',left),('right',right)]:
 for index in indices:
  name,body=motifs[index];groups.append(f'<g class="sketch-scene" data-sketch-scene="{index}" data-sketch-side="{side}" data-sketch-motif="{name}" data-sketch-seats="{hall_sizes.get(name,0)}">{body}</g>')
svg='<div class="hero-outlines" aria-hidden="true"><svg class="architectural-plan" data-hero-sketch viewBox="0 0 1200 650" fill="none">'+''.join(groups)+'<circle class="sketch-pen" r="2.2" fill="#4465a6" stroke="none"/></svg></div>'
p=ROOT/'automation/release/organizers/page.html';s=p.read_text();a=s.index('<div class="hero-outlines"');b=s.index('<div class="hero-copy">',a);p.write_text(s[:a]+svg+s[b:])
print('Hero SVG: real halls68/182/188/198 seats, aligned21-unit U table, 2 alternating lanes')
