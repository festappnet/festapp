#!/usr/bin/env python3
"""Reproduce reviewed native geometry for six raster-backed legacy layouts.

Offline only. Requires Python3 and opencv-python. Inputs stay in a private
export directory; no source images or inventory data are copied into the repo.
The template argument is the public archive's templates.json (scout-ball-182).
Run with --input-dir PRIVATE_EXPORT --templates PUBLIC_TEMPLATES_JSON.
Output contains native furniture/architecture only, never seats or inventory.
"""
import argparse, hashlib, json, math, copy, os
import cv2
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input-dir',required=True)
parser.add_argument('--templates',required=True)
parser.add_argument('--output')
args=parser.parse_args()
P=os.path.abspath(args.input_dir)+os.sep
reviewed_artwork={
 'jpeg':'a9f5ac7a2634c24a4fa3ab069e8aa7e8e5986a62367dfe6f3bff714496f791c2',
 'scout':'37a346f6c7063c3e10cef03d462f736cefe41d7610e713bdaaaf3e778b807d77',
 'parish':'0db0c9e33991b52029b08df3d99ba947945c5ad074d45ac11f5eb78f4bfe81e0',
}
assets=json.load(open(P+'private-existing-blueprints-assets.json'))['assets']; bundle=json.load(open(P+'private-existing-blueprints-converted.json'))['blueprints']; templates=json.load(open(args.templates)); font=next(iter(json.load(open(P+'private-existing-blueprints-font-resources.json'))['fonts']))
result={}
for bid in [22,25,32,33,59,87]:
 entry=next(x for x in bundle if x['blueprintId']==bid)
 source=json.loads(entry['reviewedSourceText']); a=assets[str(bid)]
 expected=reviewed_artwork['jpeg' if bid in [22,32,87] else 'scout' if bid in [25,33] else 'parish']
 if hashlib.sha256(open(a['sourcePath'],'rb').read()).hexdigest()!=expected or a['sourceSha256']!=expected:
  raise ValueError(f'Unreviewed artwork for blueprint {bid}')
 if hashlib.sha256(entry['reviewedSourceText'].encode()).hexdigest()!=a['conversionSourceSha256'] or entry['sourceSha256']!=a['conversionSourceSha256']:
  raise ValueError(f'Blueprint source hash mismatch for {bid}')
 dims=source['configuration']['dimensions']; W,H=dims['width']*48,dims['height']*48
 im=cv2.imread(a['sourcePath']); ih,iw=im.shape[:2]; scale=max(W/iw,H/ih); ox=(W-iw*scale)/2;oy=(H-ih*scale)/2;nodes=[];mapping={}
 def rect(id,x,y,w,h,kind='shape',fill='#FFFFFFFF',corner=0,label='',size=40,color='#000000FF',stroke=2):
  n=dict(id=id,kind=kind,transform=dict(x=ox+(x+w/2)*scale,y=oy+(y+h/2)*scale,rotation=0),width=w*scale,height=h*scale,shape='roundedRect' if corner else 'rect',fill=fill,stroke='#000000FF',strokeWidth=stroke*scale,cornerRadius=corner*scale,label=label,fontId=font,size=size*scale,color=color,z=-20 if kind=='shape' else 0);nodes.append(n);return n
 def text(id,label,x,y,size=48,color='#000000FF',rotation=0):
  nodes.append(dict(id=id,kind='text',transform=dict(x=ox+x*scale,y=oy+y*scale,rotation=rotation),width=max(size,len(label)*size*.65)*scale,height=size*1.3*scale,text=label,label=label,fontId=font,size=size*scale,color=color,align='center',fill=color,z=-5))
 def line(id,pts,width=3,arrow=False):
  xs=[p[0] for p in pts];ys=[p[1] for p in pts];cx=(min(xs)+max(xs))/2;cy=(min(ys)+max(ys))/2
  nodes.append(dict(id=id,kind='shape',shape='arrow' if arrow else 'polyline',transform=dict(x=ox+cx*scale,y=oy+cy*scale,rotation=0),width=max(max(xs)-min(xs),1)*scale,height=max(max(ys)-min(ys),1)*scale,points=[[(x-cx)*scale,(y-cy)*scale] for x,y in (pts[:2] if arrow else pts)],stroke='#000000FF',strokeWidth=width*scale,fill='#00000000',z=-10))
 if bid in [25,33]:
  doc=next(t['document'] for t in templates if t['id']=='scout-ball-182');factor=.48
  lengths={'width','height','size','strokeWidth','cornerRadius','seatWidth','seatHeight','seatGap','gap','padding','radius'}
  for n0 in doc['nodes']:
   if n0['kind'] in ['seat','group']:continue
   n=copy.deepcopy(n0);n.pop('parentId',None);n['id']='template-'+n['id'];n['transform']={**n['transform'],'x':n['transform']['x']*factor,'y':n['transform']['y']*factor}
   style=doc.get('appearance',{}).get(n['kind'],{});n={**style,**n}
   for k in lengths:
    if isinstance(n.get(k),(int,float)):n[k]*=factor
   if 'points'in n:n['points']=[[p[0]*factor,p[1]*factor] for p in n['points']]
   if n['kind']=='text' or n.get('label'):n['fontId']=font
   if n['kind']=='shape':n['z']=n.get('z',-10)
   nodes.append(n)
   if n['kind']=='table':
    for g in source['groups']:
     if str(g['title'])==str(n.get('label')):mapping[str(g['id'])]=n['id']
 elif bid in [22,32,87]:
  b,g,r=[x.astype(int) for x in cv2.split(im)];mask=((r>45)&(r<150)&(g<110)&(b>r+10)&(b>g+20)).astype('uint8')*255
  _,_,stats,_=cv2.connectedComponentsWithStats(mask); boxes=[(x,y,w,h) for x,y,w,h,area in stats[1:] if area>150];used=set()
  for group in source['groups']:
   seats=[o for o in source['objects'] if o.get('group')==group['id'] and o.get('type')=='spot']
   if not seats:continue
   cx=sum((o['x']+.5)*48 for o in seats)/len(seats);cy=sum((o['y']+.5)*48 for o in seats)/len(seats)
   ix=min((i for i in range(len(boxes)) if i not in used),key=lambda i:(ox+(boxes[i][0]+boxes[i][2]/2)*scale-cx)**2+(oy+(boxes[i][1]+boxes[i][3]/2)*scale-cy)**2);used.add(ix);x,y,w,h=boxes[ix];id='table-'+str(group['id']);rect(id,x,y,w,h,'table','#574569FF',8,group['title'],32 if group['title'].startswith('S') else 26,'#FFFFFFFF',0);mapping[str(group['id'])]=id
  rect('hall-outline',1,1,1510,2719,fill='#00000000',stroke=2);line('stage-wall',[(0,189),(1512,189)],2);text('stage-title','PÓDIUM',756,90,48)
  text('bar-title','BAR 2',1280,375,48);line('bar-arrow',[(1390,378),(1480,378),(1465,365),(1480,378),(1465,391)],4,arrow=True)
  line('balcony-wall',[(0,2003),(113,2003),(113,2381),(1399,2381),(1399,2003),(1512,2003)],6)
  for y in [2495,2608]:
   line('rail-left-'+str(y),[(0,y),(680,y)],2);line('rail-right-'+str(y),[(832,y),(1512,y)],2)
  text('entry-title-1','HLAVNÍ',756,2130,48);text('entry-title-2','VSTUP',756,2190,48);line('entry-arrow',[(756,2240),(756,2340),(740,2320),(756,2340),(772,2320)],5,arrow=True);text('balcony-title','BALKÓN',756,2550,48)
 else:
  for group in source['groups']:
   num=int(group['title'].replace('č.',''));id='table-'+str(group['id'])
   if num<=18:
    row=(num-1)//3;col=(num-1)%3;x=[148,827,1416][col];y=[1800,1500,1201,897,602,298][row];w=[530,450,531][col];h=154
   else:
    positions={25:(2249,302),24:(2624,302),23:(2249,602),22:(2624,602),21:(2249,901),20:(2624,901),19:(2249,1201)};x,y=positions[num];w=226;h=150
   rect(id,x,y,w,h,'table',label=str(num),size=130,stroke=4);mapping[str(group['id'])]=id
  line('main-hall-wall',[(1946,452),(1946,77),(148,77),(148,1954),(1946,1954),(1946,602)],4)
  line('main-header',[(148,227),(1946,227)],4);text('main-title','HLAVNÍ SÁL',1047,151,120,'#FF3B3BFF')
  rect('balcony-outline',2249,73,679,2106,fill='#00000000',stroke=4);line('balcony-header',[(2249,227),(2928,227)],4);text('balcony-title','BALKÓN',2588,151,120,'#FF3B3BFF')
  rect('balcony-entry',2767,1800,161,379,fill='#00000000',stroke=4)
  for i,ch in enumerate('VSTUP'):text('balcony-entry-'+str(i),ch,2847,1840+i*70,60)
  text('entrance-top','VSTUP',2020,530,45,rotation=-40);text('entrance-bottom','VSTUP',2020,2020,45,rotation=-40)
  rect('dance-floor',153,2100,1797,898,fill='#00000000',stroke=4);text('dance-title','Taneční parket',1050,2550,175)
  rect('stage',153,3222,1797,225,fill='#00000000',stroke=4);text('stage-title','Pódium',1050,3340,130)
 if bid==25:
  mapping.pop('1',None)
  for gid,label in [('4','18'),('5','19'),('6','17')]:mapping[gid]=next(n['id'] for n in nodes if n['kind']=='table' and n.get('label')==label)
 for n in nodes:
  if bid==32 and n['kind']=='table':n['bold']=True
  if bid==32 and n.get('shape')=='arrow':n['arrowHeadLength']=32
  n['appearanceOverrides']=[k for k in ['fill','stroke','strokeWidth','cornerRadius','color'] if k in n]
 result[str(bid)]={'sourceSha256':a['conversionSourceSha256'],'artworkSourceSha256':a['sourceSha256'],'nodes':nodes,'tableGroups':mapping,'complete':True,'issues':[],'reviewNotes':['Native reconstruction from original source; no seats emitted. Empty B1 has no physical source table.'] if bid in [22,32,87] else (['Business group1 spans physical tables1 and5; left unattached rather than moving unrelated chairs. Groups4/5/6 mapped spatially to physical18/19/17.'] if bid==25 else [])}
path=args.output or P+'private-existing-blueprints-native-raster.json';open(path,'w').write(json.dumps(result,ensure_ascii=False,separators=(',',':')));os.chmod(path,0o600)
print({k:{'nodes':len(v['nodes']),'tables':sum(n['kind']=='table' for n in v['nodes']),'mappedGroups':len(v['tableGroups'])} for k,v in result.items()})
