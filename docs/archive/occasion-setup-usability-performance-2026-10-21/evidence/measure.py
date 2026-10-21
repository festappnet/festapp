import json,time,urllib.request,uuid,statistics,sys
from pathlib import Path
cfg=json.loads(Path('../festapp-wizard-usability-main-20261021/wizard-defines.json').read_text())
base=cfg['FESTAPP_SUPABASE_URL']; key=cfg['FESTAPP_SUPABASE_ANON_KEY']
def request(path,data,token=key):
 r=urllib.request.Request(base+path,data=json.dumps(data).encode(),headers={'apikey':key,'Authorization':'Bearer '+token,'Content-Type':'application/json'})
 t=time.perf_counter()
 try:
  with urllib.request.urlopen(r) as f: body=f.read()
 except urllib.error.HTTPError as e:
  print(e.read().decode());raise SystemExit(1)
 return (json.loads(body) if body else None),round((time.perf_counter()-t)*1000,2),len(body)
token=request('/auth/v1/token?grant_type=password',{'email':'1+t@t.com','password':'test'})[0]['access_token']
def rpc(name,data):return request('/rest/v1/rpc/'+name,data,token)
measurements=[]
for i in range(4):
 d,t,n=rpc('create_occasion_setup_draft',{'p_unit':1,'p_id':str(uuid.uuid4())}); measurements.append({'run':i,'stage':'create','ms':t,'bytes':n})
 rows,t,n=rpc('get_occasion_setup_sources',{'p_unit':1});measurements.append({'run':i,'stage':'sources','ms':t,'bytes':n})
 # Save a valid normal transition while preserving the canonical generated data.
 data=d['data']; data.update(title='Synthetic performance fixture',link='',start='2026-12-01T18:00:00+01:00',end='2026-12-02T02:00:00+01:00',step=1)
 saved,t,n=rpc('save_occasion_setup_draft',{'p_id':d['id'],'p_expected_revision':d['revision'],'p_data':data,'p_step':1});measurements.append({'run':i,'stage':'save','ms':t,'bytes':n})
 rpc('delete_occasion_setup_draft',{'p_id':saved['id'],'p_unit':1,'p_expected_revision':saved['revision']})
Path('/tmp/festapp-setup-20261021/'+sys.argv[1]+'.json').write_text(json.dumps(measurements,indent=2))
print(json.dumps(measurements))
