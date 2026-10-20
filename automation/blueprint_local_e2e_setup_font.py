#!/usr/bin/env python3
"""Real unit-authorized existing Edge font preparation before an occasion exists."""
import base64,hashlib,json,time,urllib.request,uuid
from pathlib import Path
from blueprint_local_e2e import BACKEND,PROJECT,sql

def main():
    if sql("SELECT project FROM festapp_test_support.disposable_environment WHERE singleton",capture=True).strip()!=PROJECT:raise RuntimeError('Owned disposable backend required')
    config=json.loads((BACKEND/'private-defines.json').read_text());f=json.loads((BACKEND/'fixture.json').read_text());base=config['FESTAPP_SUPABASE_URL'];key=config['FESTAPP_SUPABASE_ANON_KEY']
    def post(path,body,token=key):
        request=urllib.request.Request(base+path,data=json.dumps(body).encode(),headers={'apikey':key,'Authorization':'Bearer '+token,'Content-Type':'application/json'})
        try: response=urllib.request.urlopen(request,timeout=45)
        except urllib.error.HTTPError as error: raise RuntimeError(f'Local request {path} returned {error.code}: '+error.read().decode()) from None
        with response:
            raw=response.read()
            return json.loads(raw) if raw else None
    token=post('/auth/v1/token?grant_type=password',{'email':'1+t@t.com','password':'test'})['access_token']
    unit=int(sql('SELECT unit FROM public.occasions WHERE id='+str(f['occasion']),capture=True));identifier=str(uuid.uuid4())
    draft=post('/rest/v1/rpc/create_occasion_setup_draft',{'p_id':identifier,'p_unit':unit},token)
    try:
        start=time.monotonic()
        catalog=json.loads((Path(__file__).resolve().parent.parent/'supabase/functions/_shared/ticket-assets/font-catalog.json').read_text())
        family=next(item for item in catalog['families'] if item['family']=='Roboto');face=family['faces']['400:normal']
        native_faces=0
        for native in family['faces'].values():
            reply=post('/functions/v1/preview-ticket-layout',{'mode':'font','fontProtocol':2,'setupDraftId':identifier,'fontId':native},token)
            if reply.get('id')!=native or hashlib.sha256(base64.b64decode(reply['font'])).hexdigest()!=native.split(':',1)[1] or not reply.get('metrics'):raise RuntimeError('Native face bytes mismatch')
            native_faces+=1
        request={'text':'Židle před vytvořením akce','role':'text','fontFamilyId':family['id'],'fontFaceId':face,'size':24,'language':'cs','direction':'auto','lineHeight':1.2,'align':'left','box':{'x':-200,'y':-50,'width':400,'height':100},'fit':'wrap'}
        prepared=post('/functions/v1/preview-ticket-layout',{'mode':'layout-text','resourceProtocol':2,'setupDraftId':identifier,'batch':{'requests':[request],'numericFaces':[]}},token)
        layouts=prepared.get('textLayouts',{})
        if prepared.get('protocol')!=2 or len(layouts)!=1 or not next(iter(layouts.values())).get('path'):raise RuntimeError('Prepared whole text missing')
        document={'schemaVersion':2,'symbolSetVersion':1,'canvas':{'x':0,'y':0,'width':2400,'height':1600,'fill':'#FFFFFFFF'},'styles':{},'seatingDefaults':{},'textPolicy':{'language':'und','direction':'auto'},'nodes':[{'id':str(uuid.uuid4()),'kind':'text','width':400,'height':100,'text':request['text'],'transform':{'x':500,'y':300,'rotation':0},'style':{'label':{'fontFamilyId':family['id'],'size':24,'language':'cs','direction':'auto','lineHeight':1.2,'align':'left'}}}],'sections':[],'selectionUnits':[],'attachments':[],'presets':[]}
        data=dict(draft.get('data') or {});data['blueprintLayoutDraft']={'layout':document,'seatBindings':[],'groupProducts':[],'areaBindings':[]}
        draft=post('/rest/v1/rpc/save_occasion_setup_draft',{'p_id':identifier,'p_expected_revision':draft['revision'],'p_data':data,'p_step':0},token)
        resources=post('/rest/v1/rpc/get_occasion_setup_blueprint_resources',{'p_draft':identifier},token)
        if not set(layouts).issubset(resources.get('resources',{}).get('textLayouts',{})):raise RuntimeError('Prepared setup resource read failed')
        print(json.dumps({'actualSetupWholeText':True,'verifiedNativeFaces':native_faces,'seconds':round(time.monotonic()-start,3),'unitScoped':True,'noOccasionCreated':True}))
    finally:
        post('/rest/v1/rpc/delete_occasion_setup_draft',{'p_id':identifier,'p_unit':unit,'p_expected_revision':draft['revision']},token)
if __name__=='__main__':main()
