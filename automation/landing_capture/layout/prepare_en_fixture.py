"""Prepare the synthetic row through the canonical local resource/save owners.

Only the disposable EN tenant on loopback 57321/57322 is accepted. Never use
this capture fixture for provisioning. Auth input is an explicit private file.
"""
import argparse,json,subprocess,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--auth-file',type=Path,required=True);p.add_argument('--defines',type=Path,required=True);p.add_argument('--requests',type=Path,required=True);a=p.parse_args()
ROOT=Path(__file__).resolve().parents[3]
DB='postgresql://postgres:postgres@127.0.0.1:57322/postgres'
def sql(query): return subprocess.check_output(['psql',DB,'-X','-At','-v','ON_ERROR_STOP=1','-c',query],text=True).strip()
def literal(value): return "'"+value.replace("'","''")+"'"
assert sql("SELECT count(*) FROM public.organizations WHERE id=900001 AND title='Festapp Tickets local EN'")=='1','Synthetic tenant required'
defines=json.loads(a.defines.read_text());assert defines['FESTAPP_SUPABASE_URL']=='http://127.0.0.1:57321'
auth=json.loads(a.auth_file.read_text());auth=json.loads(auth) if isinstance(auth,str) else auth
requests=json.loads(a.requests.read_text())
faces=list({(r['fontFamilyId'],r['fontFaceId']) for r in requests})
payload={'occasionId':20,'mode':'layout-text','resourceProtocol':2,'batch':{'requests':requests,'numericFaces':[{'fontFamilyId':f,'fontFaceId':face} for f,face in faces]}}
request=urllib.request.Request('http://127.0.0.1:57321/functions/v1/preview-ticket-layout',data=json.dumps(payload).encode(),headers={'Authorization':'Bearer '+auth['access_token'],'apikey':defines['FESTAPP_SUPABASE_ANON_KEY'],'content-type':'application/json'})
with urllib.request.urlopen(request,timeout=90) as response: resources=json.load(response)
assert resources['protocol']==2
assert sql('SELECT count(*) FROM eshop.blueprints WHERE occasion=20')=='0','Refusing to replace an existing authored blueprint'
product=int(sql("SELECT id FROM eshop.products WHERE occasion=20 AND title='Standard ticket'"))
doc=json.loads((ROOT/'test/fixtures/ticketing_profiles/layout.en.json').read_text())
seats=[dict(nodeId=n['id'],productId=product,title=n.get('label',''),groupNodeId=n.get('parentId'),selectionUnitId=None,blocked=False,productAssignmentMode='override') for n in doc['nodes'] if n['kind']=='seat']
groups=[dict(groupNodeId=n['id'],productId=product) for n in doc['nodes'] if n['kind']=='table']
draft=dict(layout=doc,seatBindings=seats,groupProducts=groups,areaBindings=[])
query=f"""DO $fixture$ DECLARE bp bigint; BEGIN
 PERFORM set_config('request.jwt.claim.sub',{literal(auth['user']['id'])},true);
 IF NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=20 AND organization=900001) THEN RAISE EXCEPTION 'Synthetic event required'; END IF;
 bp:=public.materialize_setup_blueprint_layout_internal({literal(json.dumps(draft))}::jsonb,{literal(json.dumps({str(product):product}))}::jsonb,NULL,20,900001);
 UPDATE public.forms SET blueprint=bp WHERE occasion=20;
 INSERT INTO public.form_fields(form,type,title,is_ticket_field,is_required,\"order\") SELECT id,'spot','Choose your seats',true,true,-1 FROM public.forms WHERE occasion=20;
 UPDATE public.occasions SET features=features||'[{{"code":"blueprint","is_enabled":true}}]'::jsonb WHERE id=20;
END $fixture$;"""
result=subprocess.run(['psql',DB,'-X','-q','-1','-v','ON_ERROR_STOP=1'],input=query,text=True,capture_output=True)
if result.returncode: raise RuntimeError(result.stderr[:1200])
print('Prepared English row: 5 tables and 30 canonical sellable seats')
