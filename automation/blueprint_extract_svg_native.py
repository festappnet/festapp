#!/usr/bin/env python3
"""Offline, bounded structural SVG extraction for the reviewed legacy corpus.
No renderer, network, database or image processing. Cubics become editable
polygon vertices; unsupported syntax is explicit and prevents completeness.
"""
import argparse, hashlib, json, math, os, re, unicodedata
import xml.etree.ElementTree as ET

NUMBER=r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?'
IDENTITY=(1,0,0,1,0,0)
def nums(s): return [float(x) for x in re.findall(NUMBER,s or '')]
def mul(a,b):
 return (a[0]*b[0]+a[2]*b[1],a[1]*b[0]+a[3]*b[1],a[0]*b[2]+a[2]*b[3],a[1]*b[2]+a[3]*b[3],a[0]*b[4]+a[2]*b[5]+a[4],a[1]*b[4]+a[3]*b[5]+a[5])
def point(m,p):return [m[0]*p[0]+m[2]*p[1]+m[4],m[1]*p[0]+m[3]*p[1]+m[5]]
def transform(s):
 m=IDENTITY
 for name,args in re.findall(r'([A-Za-z]+)\s*\(([^)]*)\)',s or ''):
  v=nums(args)
  if name=='matrix' and len(v)==6:t=tuple(v)
  elif name=='translate':t=(1,0,0,1,v[0],v[1] if len(v)>1 else 0)
  elif name=='scale':t=(v[0],0,0,v[1] if len(v)>1 else v[0],0,0)
  elif name=='rotate':
   r=math.radians(v[0]);t=(math.cos(r),math.sin(r),-math.sin(r),math.cos(r),0,0)
   if len(v)==3:t=mul(mul((1,0,0,1,v[1],v[2]),t),(1,0,0,1,-v[1],-v[2]))
  else:raise ValueError('unsupported transform '+name)
  m=mul(m,t)
 return m

def style(el,parent):
 s=dict(parent)
 for k in ['fill','fill-opacity','stroke','stroke-opacity','stroke-width','stroke-dasharray','opacity','font-size','font-family','font-weight','text-anchor','display']:
  if k in el.attrib:s[k]=el.get(k)
 for item in el.get('style','').split(';'):
  if ':' in item:k,v=item.split(':',1);s[k.strip()]=v.strip()
 return s

def color(v,alpha=1):
 if v=='none':return '#00000000'
 v=(v or '#000000').lower();names={'black':'#000000','white':'#ffffff','gray':'#808080','grey':'#808080'};v=names.get(v,v)
 if re.fullmatch(r'#[0-9a-f]{3}',v):v='#'+''.join(x*2 for x in v[1:])
 if not re.fullmatch(r'#[0-9a-f]{6}',v):raise ValueError('unsupported color '+v)
 return v.upper()+f'{round(max(0,min(1,float(alpha)))*255):02X}'

def path_parts(d):
 tokens=re.findall(r'[A-Za-z]|'+NUMBER,d);i=0;cmd=None;cur=[0.,0.];start=None;parts=[];points=[];closed=False
 def flush():
  nonlocal points,closed
  if points:parts.append((points,closed))
  points=[];closed=False
 while i<len(tokens):
  if tokens[i].isalpha():cmd=tokens[i];i+=1
  if cmd is None:raise ValueError('path without command')
  relative=cmd.islower();c=cmd.upper()
  if c=='Z':
   closed=True;cur=start[:];flush();cmd=None;continue
  n={'M':2,'L':2,'H':1,'V':1,'C':6,'Q':4}.get(c)
  if n is None:raise ValueError('unsupported path command '+cmd)
  if i+n>len(tokens) or any(t.isalpha() for t in tokens[i:i+n]):raise ValueError('incomplete path command '+cmd)
  v=list(map(float,tokens[i:i+n]));i+=n;base=cur[:]
  if c in ('M','L'):
   p=[v[0]+(base[0] if relative else 0),v[1]+(base[1] if relative else 0)]
   if c=='M':flush();start=p[:];cmd='l' if relative else 'L'
   points.append(p);cur=p
  elif c=='H':cur=[v[0]+(base[0] if relative else 0),base[1]];points.append(cur)
  elif c=='V':cur=[base[0],v[0]+(base[1] if relative else 0)];points.append(cur)
  else:
   q=[[v[j]+(base[0] if relative else 0),v[j+1]+(base[1] if relative else 0)] for j in range(0,n,2)]
   for step in range(1,9):
    t=step/8;u=1-t
    if c=='C':p=[u**3*base[k]+3*u*u*t*q[0][k]+3*u*t*t*q[1][k]+t**3*q[2][k] for k in (0,1)]
    else:p=[u*u*base[k]+2*u*t*q[0][k]+t*t*q[1][k] for k in (0,1)]
    points.append(p)
   cur=q[-1]
 flush();return parts

def canonical_shape(identifier,points,props,closed=False):
 xs=[p[0] for p in points];ys=[p[1] for p in points];w=max(xs)-min(xs);h=max(ys)-min(ys);cx=(max(xs)+min(xs))/2;cy=(max(ys)+min(ys))/2
 return {'id':identifier,'kind':'shape','transform':{'x':cx,'y':cy,'rotation':0},'width':max(1,w),'height':max(1,h),'properties':dict(props,shape='polygon' if closed else 'polyline',points=[[round(x-cx,6),round(y-cy,6)] for x,y in points])}

def normalize_label(s):return re.sub(r'^(stul|table)\s*','', ''.join(c for c in unicodedata.normalize('NFD',s.lower().strip()) if not unicodedata.combining(c)))

def extract(bp,source):
 root=ET.parse(source).getroot();view=nums(root.get('viewBox'))
 if view:ox,oy,sw,sh=view
 else:ox=oy=0;sw=nums(root.get('width'))[0];sh=nums(root.get('height'))[0]
 dim=bp['configuration']['dimensions'];cw=dim['width']*48;ch=dim['height']*48;scale=max(cw/sw,ch/sh)
 registration=(scale,0,0,scale,(cw-sw*scale)/2-ox*scale,(ch-sh*scale)/2-oy*scale)
 ids={e.get('id'):e for e in root.iter() if e.get('id')};nodes=[];issues=[];font_requirements={};counter=0;source_kinds={};texts=[]
 def visit(el,m,parent_style,stack=()):
  nonlocal counter
  tag=el.tag.rsplit('}',1)[-1];s=style(el,parent_style)
  if s.get('display')=='none':return
  try:m=mul(m,transform(el.get('transform')))
  except ValueError as e:issues.append(str(e));return
  if tag=='use':
   href=el.get('href') or el.get('{http://www.w3.org/1999/xlink}href','')
   if not href.startswith('#') or href[1:] not in ids or href in stack:issues.append('unsupported/cyclic use '+href);return
   visit(ids[href[1:]],mul(m,(1,0,0,1,float(el.get('x',0)),float(el.get('y',0)))),s,stack+(href,));return
  if tag in ['svg','g']:
   for child in el:visit(child,m,s,stack)
   return
  if tag in ['defs','metadata','title','desc','namedview']:return
  counter+=1;identifier=f'svg-{bp["id"]}-{counter}';world=mul(registration,m);sx=math.hypot(world[0],world[1]);sy=math.hypot(world[2],world[3])
  try:
   props={'fill':color(s.get('fill','#000000'),s.get('fill-opacity',1)),'stroke':color(s.get('stroke','none'),s.get('stroke-opacity',1)),'strokeWidth':float(s.get('stroke-width',1))*sx,'role':'decoration','appearanceOverrides':['fill','stroke','strokeWidth']}
   if s.get('stroke-dasharray','none')!='none':
    dash=nums(s['stroke-dasharray'])
    if not dash or any(v<=0 for v in dash):raise ValueError('unsupported non-positive SVG dash pattern')
    props['dash']=[v*sx for v in dash]
   if tag=='text':
    value=''.join(el.itertext()).strip()
    if not value:return
    first=next(iter(el),el);x=nums(first.get('x',el.get('x','0')))[0];y=nums(first.get('y',el.get('y','0')))[0];p=point(world,[x,y]);local_size=nums(s.get('font-size','16'))[0];local_width=max(local_size,len(value)*local_size*.58);size=local_size*sy;width=local_width*sx;anchor=s.get('text-anchor','start');center=point(world,[x+(local_width/2 if anchor=='start' else -local_width/2 if anchor=='end' else 0),y-local_size*.35])
    n={'id':identifier,'kind':'text','label':value,'transform':{'x':center[0],'y':center[1],'rotation':math.degrees(math.atan2(world[1],world[0]))},'width':width,'height':size*1.2,'properties':{'text':value,'align':'left' if anchor=='start' else 'right' if anchor=='end' else 'center','size':size,'lineHeight':1,'bold':s.get('font-weight','400') in ['700','bold','600'],'color':props['fill'],'role':'decoration','appearanceOverrides':['color']}}
    font_requirements[identifier]=s.get('font-family','sans-serif');nodes.append(n);texts.append((value,p,n));return
   if tag=='rect':
    x=float(el.get('x',0));y=float(el.get('y',0));w=float(el.get('width',0));h=float(el.get('height',0));p=point(world,[x+w/2,y+h/2]);rot=math.degrees(math.atan2(world[1],world[0]));n={'id':identifier,'kind':'shape','transform':{'x':p[0],'y':p[1],'rotation':rot},'width':max(1,w*sx),'height':max(1,h*sy),'properties':dict(props,shape='roundedRect' if el.get('rx') else 'rect',cornerRadius=float(el.get('rx',0))*sx)};nodes.append(n);source_kinds[identifier]='rect';return
   if tag=='path':
    for part,(points,closed) in enumerate(path_parts(el.get('d',''))):
     if len(points)<2:continue
     n=canonical_shape(identifier+f'-{part}',[point(world,p) for p in points],props,closed)
     # The source's alternating open paths are the native editable zigzag seam.
     if bp['id'] in (27,91) and not closed and len(points)>=7:
      n['properties'].update(pathPattern='zigzag',zigzagTeeth=max(1,(len(points)-1)//2),zigzagAmplitude=max(1,min(n['width'],n['height'])/2))
     nodes.append(n);source_kinds[n['id']]='path'
    return
   issues.append('unsupported SVG element '+tag)
  except (ValueError,IndexError,TypeError) as e:issues.append(f'{identifier}: {e}')
 visit(root,IDENTITY,{'fill':'#000000','stroke':'none'})
 # Match explicitly labelled source furniture first; otherwise use the seat-group
 # centroid as evidence, never classify a room-sized background as a table.
 table_groups={};binding_issues=[];candidates=[n for n in nodes if n['kind']=='shape' and n['width']*n['height']<cw*ch*.08 and n['properties']['fill']!='#00000000']
 def local(n,p):
  dx=p[0]-n['transform']['x'];dy=p[1]-n['transform']['y'];r=math.radians(-n['transform']['rotation']);return [dx*math.cos(r)-dy*math.sin(r),dx*math.sin(r)+dy*math.cos(r)]
 def contained(n,p):
  x,y=local(n,p);return abs(x)<=n['width']/2+3 and abs(y)<=n['height']/2+3
 captions={}
 for n in candidates:
  chunks=[(local(n,p),value) for value,p,text_node in texts if contained(n,p)]
  chunks.sort(key=lambda pair:pair[0][0])
  caption=''.join(value for p,value in chunks)
  captions[n['id']]=normalize_label(caption).replace(' ','')
  recognized=n['properties']['fill'].upper().startswith('#D0D5C9') or bool(re.fullmatch(r'\d+',captions[n['id']]))
  if recognized:
   radius=n['properties'].get('cornerRadius',min(n['width'],n['height'])*.12)
   n['kind']='table';n['label']='';n['properties']['shape']='roundedRect' if radius>0 else 'rect';n['properties']['cornerRadius']=radius;n['properties'].pop('points',None)
 for group in bp.get('groups') or []:
  label=normalize_label(str(group.get('title',''))).replace(' ','');seats=[o for o in bp.get('objects') or [] if o.get('group')==group['id']]
  matches=[n for n in candidates if n['kind']=='table' and captions[n['id']]==label and n['id'] not in table_groups.values()]
  if not matches:continue
  n=matches[0]
  if seats:
   center=[sum((o['x']+.5)*48 for o in seats)/len(seats),sum((o['y']+.5)*48 for o in seats)/len(seats)]
   if any(abs(local(n,[(o['x']+.5)*48,(o['y']+.5)*48])[0])>n['width']/2+96 or abs(local(n,[(o['x']+.5)*48,(o['y']+.5)*48])[1])>n['height']/2+96 for o in seats):
    binding_issues.append('commercial group '+str(group['id'])+' chairs exceed source table expanded bounds for caption '+label);continue
  table_groups[str(group['id'])]=n['id']
 # A source text occurs once and is parented to its real native table. Local
 # inverse transforms retain exact extracted world centers and text rotation.
 for value,anchor,text_node in texts:
  tables=[n for n in candidates if n['kind']=='table' and contained(n,anchor)]
  if tables:
   table=min(tables,key=lambda n:n['width']*n['height']);tr=text_node['transform'];q=local(table,[tr['x'],tr['y']]);text_node['parentId']=table['id'];text_node['transform']={'x':q[0],'y':q[1],'rotation':tr['rotation']-table['transform']['rotation']}
 for group in bp.get('groups') or []:
  if str(group['id']) not in table_groups and any(o.get('group')==group['id'] for o in bp.get('objects') or []) and 'stání' not in str(group.get('title','')).lower():
   note='unattached commercial group '+str(group['id'])+' ('+str(group.get('title',''))+')'
   if not any('group '+str(group['id'])+' ' in issue for issue in binding_issues):binding_issues.append(note)
 for order,n in enumerate(nodes):
  if n['kind']=='table' or n['properties'].get('shape') in ['rect','roundedRect']:n['properties']['appearanceOverrides'].append('cornerRadius')
  n['z']=-1000+order
  n.update(n.pop('properties'))
 return {'sourceSha256':bp['conversionSourceSha256'],'nodes':nodes,'tableGroups':table_groups,'sourceWidth':sw,'sourceHeight':sh,'complete':not issues,'issues':issues,'fontRequirements':font_requirements,'reviewNotes':binding_issues,'coordinateFrame':'V1 centered BoxFit.cover into configuration dimensions * 48'}

def main():
 p=argparse.ArgumentParser();p.add_argument('--private-dir',default='/Users/miakh/source/festapp-blueprint-b-e2e-20261019');a=p.parse_args();base=a.private_dir
 b=json.load(open(base+'/private-existing-blueprints.json'));assets=json.load(open(base+'/private-existing-blueprints-assets.json'))['assets'];out={}
 for bp in b['blueprints']:
  if bp['id'] not in [1,2,3,4,5,23,27,29,36,44,90,91]:continue
  asset=assets[str(bp['id'])];source=asset['sourcePath'];assert hashlib.sha256(open(source,'rb').read()).hexdigest()==asset['sourceSha256'];out[str(bp['id'])]=extract(bp,source)
 path=base+'/private-existing-blueprints-native-svg.json';fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
 with os.fdopen(fd,'w') as f:json.dump(out,f,ensure_ascii=False,separators=(',',':'))
 os.chmod(path,0o600)
 print(json.dumps({k:{'nodes':len(v['nodes']),'tables':len(v['tableGroups']),'complete':v['complete'],'issues':v['issues']} for k,v in out.items()}))
if __name__=='__main__':main()
