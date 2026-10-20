#!/usr/bin/env python3
"""Exercise real local RPC financial commands and restore swap positions afterward."""
import json, urllib.request, uuid
from blueprint_local_e2e import BACKEND,PROJECT,sql,private_json

def main():
    if sql("SELECT project FROM festapp_test_support.disposable_environment WHERE singleton",capture=True).strip()!=PROJECT:raise RuntimeError('Owned disposable backend required')
    config=json.loads((BACKEND/'private-defines.json').read_text());f=json.loads((BACKEND/'fixture.json').read_text())
    base=config['FESTAPP_SUPABASE_URL'];key=config['FESTAPP_SUPABASE_ANON_KEY']
    def post(path,body,token=key):
        request=urllib.request.Request(base+path,data=json.dumps(body).encode(),headers={'apikey':key,'Authorization':'Bearer '+token,'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=45) as response:return json.load(response)
    token=post('/auth/v1/token?grant_type=password',{'email':'1+t@t.com','password':'test'})['access_token']
    def rpc(name,body):return post('/rest/v1/rpc/'+name,body,token)
    spots=f['business']['spotIds'];orders=f['business']['orders'];ids=','.join(str(value) for value in orders.values())
    def money():return json.loads(sql("SELECT jsonb_object_agg(o.id,jsonb_build_object('price',o.price,'state',o.state,'amount',p.amount,'paid',p.paid)) FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id IN ("+ids+")",capture=True))
    def assignments():return json.loads(sql('SELECT jsonb_object_agg(id,order_product_ticket) FROM eshop.spots WHERE blueprint='+str(f['blueprint']),capture=True))
    initial_money=money();initial_spots=assignments();evidence=[]
    for label,left,right in [
        ('paid_to_free',spots['Other order A'],spots['Free premium']),
        ('same_order',spots['Same order A'],spots['Same order B']),
        ('different_orders',spots['Other order A'],spots['Other order B']),
    ]:
        preview=rpc('preview_blueprint_swap',{'p_spot_1':left,'p_spot_2':right})
        if preview.get('code')!=200:raise RuntimeError(label+' preview rejected '+str(preview.get('reason')))
        command=str(uuid.uuid4());params={'p_spot_1':left,'p_spot_2':right,'p_command_id':command}
        result=rpc('swap_spot_tickets_client_sync_v1',params)
        if result.get('status')!='applied':raise RuntimeError(label+' swap rejected')
        changed=money();replayed=rpc('swap_spot_tickets_client_sync_v1',params)
        if money()!=changed or replayed.get('mutation',{}).get('commandId') != command:raise RuntimeError('Swap replay changed money or missing replay receipt')
        inverse=rpc('swap_spot_tickets_client_sync_v1',{**params,'p_command_id':str(uuid.uuid4())})
        if inverse.get('status')!='applied' or money()!=initial_money or assignments()!=initial_spots:raise RuntimeError(label+' inverse did not restore authoritative balances/identities')
        evidence.append({'case':label,'preview':preview,'after':changed,'replayStable':True,'inverseRestored':True})
    used=rpc('preview_blueprint_swap',{'p_spot_1':spots['Used ticket'],'p_spot_2':spots['Free premium']})
    if money()!=initial_money or assignments()!=initial_spots:raise RuntimeError('Used preview changed live assignments or money')
    evidence.append({'case':'used_preview_authoritative_policy','result':used,'previewRolledBack':True})
    private_json(BACKEND/'finance-smoke.json',evidence)
    print(json.dumps({'realFinancialScenarios':len(evidence),'swapReplayStable':True,'paidBalancesAndSpotIdentitiesRestored':True,'usedPreviewCode':used.get('code'),'usedReason':used.get('reason')}))
if __name__=='__main__':main()
