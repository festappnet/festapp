"""Replace the existing public demo geometry fixture with its canonical equivalent.
Requires an explicit protected readback; emits no tenant, price or spot identities.
"""
import json,math,sys,uuid
from pathlib import Path
root=Path(__file__).resolve().parents[2]
folder=Path(sys.argv[1]);old=json.loads((folder/'demo-legacy-reference.json').read_text());current=json.loads((folder/'demo-canonical-reference.json').read_text())
nodes={n['id']:n for n in current['layout']['nodes']};poses={}
def pose(key):
 if key in poses:return poses[key]
 n=nodes[key];t=n['transform'];x,y=t['x'],t['y'];angle=t['rotation']*math.pi/180
 if n.get('parentId') in nodes:
  px,py,a=pose(n['parentId']);x,y=px+math.cos(a)*x-math.sin(a)*y,py+math.sin(a)*x+math.cos(a)*y;angle+=a
 poses[key]=(x,y,angle);return poses[key]
by_position={tuple(round(v,2) for v in pose(b['nodeId'])[:2]):b for b in current['bindings']['seatBindings']}
assert len(by_position)==len(old['objects'])==249
ordered=[by_position[(round(o['x']*48+24,2),round(o['y']*48+24,2))] for o in old['objects']]
assert len({b['nodeId'] for b in ordered})==249
assert all(b['title']==o['title'] for b,o in zip(ordered,old['objects']))
mapping={}
def identities(value):
 if isinstance(value,dict):
  if isinstance(value.get('id'),str):mapping[value['id']]=str(uuid.uuid5(uuid.NAMESPACE_URL,'festapp:public-demo-reference:'+value['id']))
  for child in value.values():identities(child)
 elif isinstance(value,list):
  for child in value:identities(child)
identities(current['layout'])
def remap(value):
 if isinstance(value,str):return mapping.get(value,value)
 if isinstance(value,list):return [remap(x) for x in value]
 if isinstance(value,dict):return {k:remap(v) for k,v in value.items()}
 return value
reference={'layout':remap(current['layout']),'seatBindings':[remap({**{k:b.get(k) for k in ['nodeId','title','groupNodeId','selectionUnitId']},'referenceGroup':o['group']}) for b,o in zip(ordered,old['objects'])], 'seat_count':249,'resources':current['resources']}
sql="-- Public synthetic demo geometry, canonical format only. Source matching proves\n-- all 249 original grid positions; backend and commercial identities are absent.\nCREATE TEMP TABLE demo_reference_blueprint(content jsonb) ON COMMIT DROP;\nINSERT INTO demo_reference_blueprint VALUES ('"+json.dumps(reference,ensure_ascii=False,separators=(',',':')).replace("'","''")+"'::jsonb);\n"
(root/'database/fixtures/demo_occasions/reference.sql').write_text(sql)
print('Sealed canonical demo reference:249 seats, no legacy geometry fields')
