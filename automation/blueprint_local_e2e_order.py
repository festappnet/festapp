#!/usr/bin/env python3
"""Local real-command checkout/replay smoke; external delivery remains queue-only."""
import json, time, urllib.request, urllib.error, uuid
from blueprint_local_e2e import BACKEND, PROJECT, sql, private_json

def main():
    if sql("SELECT project FROM festapp_test_support.disposable_environment WHERE singleton",capture=True).strip()!=PROJECT:raise RuntimeError('Owned disposable backend required')
    if sql("SELECT count(*) FROM public.email_capacity WHERE NOT paused OR worker_url IS NOT NULL",capture=True).strip()!='0':raise RuntimeError('Email delivery fence missing')
    if sql("SELECT count(*) FROM cron.job WHERE active",user='supabase_admin',capture=True).strip()!='0':raise RuntimeError('Scheduler delivery fence missing')
    if sql("SELECT count(*) FROM eshop.external_services",capture=True).strip()!='0':raise RuntimeError('External provider configuration must remain empty')
    config=json.loads((BACKEND/'private-defines.json').read_text());f=json.loads((BACKEND/'fixture.json').read_text())
    base=config['FESTAPP_SUPABASE_URL'];key=config['FESTAPP_SUPABASE_ANON_KEY']
    def post(path,body):
        request=urllib.request.Request(base+path,data=json.dumps(body).encode(),headers={'apikey':key,'Authorization':'Bearer '+key,'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=45) as response:return json.load(response)
    prior=BACKEND/'order-smoke-intent.json'
    intent=json.loads(prior.read_text()) if prior.exists() else {}
    same=intent.get('formKey')==f['formKey']
    if not same:
        intent={'commandId':str(uuid.uuid4()),'clientId':str(uuid.uuid4()),'secret':str(uuid.uuid4()),'spot':f['business']['spotIds']['Free spare'],'formKey':f['formKey']}
        private_json(prior,intent)
    command,client,secret,spot=(intent[k] for k in ['commandId','clientId','secret','spot'])
    committed=sql("SELECT count(*) FROM eshop.spots WHERE id="+str(spot)+" AND order_product_ticket IS NOT NULL",capture=True).strip()=='1'
    if not committed:
        hold=post('/rest/v1/rpc/select_spot',{'form_key':f['formKey'],'secret_id':secret,'spot_id':spot,'selecting':True})
        if hold.get('code')!=200:raise RuntimeError('Actual hold rejected: '+str(hold.get('reason') or hold.get('message')))

    order={'form':f['formKey'],'secret':secret,'email':'local-checkout@example.invalid','lang':'cs','fields':[],'ticket':[{'spot':spot,'fields':[]},{'fields':[{'product_type':f['standingProduct']}]}]}
    payload={'orderDetails':order,'commandId':command,'clientId':client}
    result=post('/functions/v1/send-ticket-order',payload)
    if result.get('code')!=200:raise RuntimeError('Actual Edge order rejected: '+str(result.get('code'))+' '+str(result.get('reason') or result.get('message')))
    replay=post('/functions/v1/send-ticket-order',payload)
    order_data=result.get('ticketOrder',{}).get('order',{})
    if not order_data.get('id'):raise RuntimeError('No actual committed order: '+json.dumps(result))
    replay_order=replay.get('ticketOrder',{}).get('order',{})
    if replay_order.get('id')!=order_data['id']:raise RuntimeError('Replay changed order identity')
    private_json(BACKEND/'order-smoke.json',{'commandId':command,'clientId':client,'result':result,'replay':replay,'spot':spot,'formKey':f['formKey']})
    print(json.dumps({'orderId':order_data['id'],'code':result['code'],'replaySameOrder':True,'paymentAmount':order_data.get('payment_info',{}).get('amount'),'delivery':result.get('delivery'),'actualSpot':spot}))
if __name__=='__main__':main()
