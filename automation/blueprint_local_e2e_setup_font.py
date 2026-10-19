#!/usr/bin/env python3
"""Real unit-authorized existing Edge font preparation before an occasion exists."""
import json,time,urllib.request,uuid
from blueprint_local_e2e import BACKEND,PROJECT,sql

def main():
    if sql("SELECT project FROM festapp_test_support.disposable_environment WHERE singleton",capture=True).strip()!=PROJECT:raise RuntimeError('Owned disposable backend required')
    config=json.loads((BACKEND/'private-defines.json').read_text());f=json.loads((BACKEND/'fixture.json').read_text());base=config['FESTAPP_SUPABASE_URL'];key=config['FESTAPP_SUPABASE_ANON_KEY']
    def post(path,body,token=key):
        request=urllib.request.Request(base+path,data=json.dumps(body).encode(),headers={'apikey':key,'Authorization':'Bearer '+token,'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=45) as response:
            raw=response.read()
            return json.loads(raw) if raw else None
    token=post('/auth/v1/token?grant_type=password',{'email':'1+t@t.com','password':'test'})['access_token']
    unit=int(sql('SELECT unit FROM public.occasions WHERE id='+str(f['occasion']),capture=True));identifier=str(uuid.uuid4())
    draft=post('/rest/v1/rpc/create_occasion_setup_draft',{'p_id':identifier,'p_unit':unit},token)
    try:
        start=time.monotonic()
        outline=post('/functions/v1/preview-ticket-layout',{'mode':'font','fontProtocol':2,'setupDraftId':identifier,'fontId':'builtin:futura-pt-book:571b3803a43928d59f695acb37e73c9dc89666f5d541183e2b53c19c8986ab44','outline':True,'characters':'Židle wizard'},token)
        if not outline.get('glyphs',{}).get('Ž'):raise RuntimeError('Actual setup outline missing real glyphs')
        resources=post('/rest/v1/rpc/get_occasion_setup_blueprint_resources',{'p_draft':identifier},token)
        if outline['id'] not in resources.get('resources',{}).get('fonts',{}):raise RuntimeError('Ready setup resource read failed')
        print(json.dumps({'actualSetupFont':True,'glyphs':len(outline['glyphs']),'seconds':round(time.monotonic()-start,3),'unitScoped':True,'noOccasionCreated':True}))
    finally:
        post('/rest/v1/rpc/delete_occasion_setup_draft',{'p_id':identifier,'p_unit':unit,'p_expected_revision':draft['revision']},token)
if __name__=='__main__':main()
