"""Authenticated canonical form save. Complements the real organizer UI login/open."""
import json,urllib.request,uuid
from pathlib import Path
root=Path(__file__).resolve().parents[1]
s=json.loads((root/'.private/backend-status.json').read_text());assert s['API_URL']=='http://127.0.0.1:59821'
def post(path,body,token=None):
    headers={'apikey':s['ANON_KEY'],'Content-Type':'application/json'}
    if token:headers['Authorization']='Bearer '+token
    req=urllib.request.Request(s['API_URL']+path,data=json.dumps(body).encode(),headers=headers)
    with urllib.request.urlopen(req,timeout=20) as r:return json.load(r)
token=post('/auth/v1/token?grant_type=password',{'email':'1+t@t.com','password':'test'})['access_token']
def rpc(name,body):return post('/rest/v1/rpc/'+name,body,token)
bundle=rpc('get_form_for_edit',{'form_link':'embedded-synthetic'});assert bundle['code']==200
bundle=bundle['data'];form=bundle['form'];form['title']='WordPress verified checkout';form['participant_capacity']=20
form['expected_aggregate_version']=form.pop('aggregate_version')
form['expected_product_versions']={str(x['id']):x['aggregate_version'] for x in bundle['products']}
form['expected_product_type_versions']={str(x['id']):x['aggregate_version'] for x in bundle['product_types']}
form['form_fields']=bundle['form_fields'];form['deleted_field_ids']=[];form['deleted_product_ids']=[]
for f in form['form_fields']:
    if f.get('product_type'):
        pt=dict(next(p for p in bundle['product_types'] if p['id']==f['product_type']))
        pt['products']=[p for p in bundle['products'] if p['product_type']==pt['id']]
        f['product_type']=pt
command={'p_form':form,'p_command_id':str(uuid.uuid4())}
result=rpc('update_form_client_sync_v1',command)
(root/'.private/form-save-result.json').write_text(json.dumps(result))
assert result['code']==200, {k:result.get(k) for k in ['code','message','outcome','reason','aggregate_version']}
assert rpc('update_form_client_sync_v1',command)==result
read=rpc('get_form_for_edit',{'form_link':'embedded-synthetic'})['data']['form']
assert read['title']=='WordPress verified checkout' and read['participant_capacity']==20
(root/'evidence/organizer-save-receipt.json').write_text(json.dumps({'status':'PASS','method':'real authenticated canonical RPC; UI login and saved-form opening separately observed','form_id':read['id'],'saved_slug':read['link'],'aggregate_version':read['aggregate_version'],'idempotent_save_replay':True},indent=2)+'\n')
print('PASS: organizer saved form through canonical authenticated/versioned RPC; replay and readback agree')
