"""Real local RPC evidence. No production endpoint, provider send, or fake order."""
import base64,datetime,hashlib,json,subprocess,urllib.request,uuid,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PRIVATE=ROOT/'.private'
STATUS=json.loads((PRIVATE/'backend-status.json').read_text())
assert STATUS['API_URL']=='http://127.0.0.1:59821'
BASE=STATUS['API_URL']
DB='supabase_db_festapp-vo-wordpress-20261023'
def sql(query):
    return subprocess.check_output(['docker','exec',DB,'psql','-X','-U','postgres','-d','postgres','-Atqc',query],text=True).strip()
assert sql('select title from public.organizations where id=1')=='Test Organization'
def request(path,body=None,token=None,headers=None):
    hdr={'apikey':STATUS['ANON_KEY'],'Content-Type':'application/json'}
    if token:hdr['Authorization']='Bearer '+token
    hdr.update(headers or {})
    req=urllib.request.Request(BASE+path,data=json.dumps(body).encode() if body is not None else None,headers=hdr)
    with urllib.request.urlopen(req,timeout=45) as r:
        raw=r.read()
        return json.loads(raw) if raw else None
def rpc(name,args,token=None):return request('/rest/v1/rpc/'+name,args,token)
receipt={'environment':'owned disposable canonical Supabase','source_head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'cases':[]}
def passed(name,**data):receipt['cases'].append({'case':name,'status':'PASS',**data})
# Replay the exact UI request captured by agent-browser, using the same identity.
har=json.loads((PRIVATE/os.environ.get('VO_ACCEPTANCE_HAR','final-order.har')).read_text())
entry=next(e for e in har['log']['entries'] if e['request']['url']==BASE+'/functions/v1/send-ticket-order' and e['request']['method']=='POST')
payload=json.loads(entry['request']['postData']['text'])
before=int(sql('select count(*) from eshop.orders'))
a=request('/functions/v1/send-ticket-order',payload,STATUS['ANON_KEY'])
b=request('/functions/v1/send-ticket-order',payload,STATUS['ANON_KEY'])
assert a['code']==b['code']==200 and a['ticketOrder']['order']['id']==b['ticketOrder']['order']['id']
assert int(sql('select count(*) from eshop.orders'))==before
passed('exact UI request replay twice creates no duplicate',order_id=a['ticketOrder']['order']['id'],orders_before=before,orders_after=before)
# Authenticate through the real local Auth owner; retain no credentials in evidence.
auth=request('/auth/v1/token?grant_type=password',{'email':'1+t@t.com','password':'test'})
token=auth['access_token']; assert auth['user']['email']=='1+t@t.com'
passed('organizer authentication through local Auth')
# Read the saved form as the actual organizer, with server authorization.
form=rpc('get_form_for_edit',{'form_link':'embedded-synthetic'},token)
assert form['code']==200
(PRIVATE/'form-edit-response.json').write_text(json.dumps(form))
passed('organizer reads saved form through authoritative editor RPC')
# Payment confirmation uses the existing authorized manual transaction owner.
ids=json.loads(sql("select json_agg(id) from eshop.orders where data->>'email' in ('acceptance@example.invalid','seats-final@example.invalid')"))
assert ids and len(ids)==2, 'Complete both final UI purchases first'
(PRIVATE/'final-order-ids.json').write_text(json.dumps(ids))
for oid in ids:
    info=json.loads(sql(f"select row_to_json(x) from (select o.id,o.state,o.price,o.payment_info,p.variable_symbol,p.currency_code from eshop.orders o join eshop.payment_info p on p.id=o.payment_info where o.id={int(oid)})x"))
    assert float(info['price'])==120
    if info['state']=='ordered':
        rpc('insert_manual_transaction',{'p_amount':120,'p_currency':'CZK','p_unit_id':1,'p_variable_symbol':str(info['variable_symbol']),'p_date':datetime.datetime.now(datetime.timezone.utc).isoformat(),'p_note':'Synthetic WordPress acceptance; no real payment','p_payment_info_id':info['payment_info']},token)
    assert sql(f'select state from eshop.orders where id={int(oid)}') in ('paid','sent')
passed('bank order confirmed by canonical manual transaction, no provider payment',order_ids=ids)
capacity=json.loads(sql("select public.get_form_capacity_snapshot_internal(id) from forms where link='embedded-synthetic'"))
passed('canonical form capacity after UI orders',snapshot=capacity)
# Capture real canonical email queue rendering; never start the provider dispatcher.
env=dict(l.split('=',1) for l in (PRIVATE/'edge.env').read_text().splitlines() if '=' in l)
capture=request('/functions/v1/vo-local-capture',headers={'x-local-capture':env['VO_CAPTURE_SECRET']})
(PRIVATE/'email-captures.json').write_text(json.dumps(capture))
selected=[c for c in capture.get('captures',[]) if c.get('order_id') in ids]
assert selected and all(not c.get('error') for c in selected),[(c.get('kind'),c.get('error','').splitlines()[:2]) for c in selected]
pdf_count=0
for c in selected:
    for attachment in c.get('prepared',{}).get('attachments',[]):
        if attachment['contentType']=='application/pdf':
            data=base64.b64decode(attachment['content']);assert data.startswith(b'%PDF-')
            path=PRIVATE/f'order-{c["order_id"]}-{pdf_count}.pdf';path.write_bytes(data);pdf_count+=1
            passed('real ticket PDF from canonical queued email rendering',order_id=c['order_id'],bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
assert pdf_count>=2,'Ticket PDFs missing'
passed('confirmation and tickets captured from canonical queue without provider send',kinds=sorted(set(c['kind'] for c in selected)),mode=capture['mode'])
# Lookup and admission use the existing scanner session and durable operation RPCs.
session=rpc('open_scanner_session',{'p_occasion':1,'p_device_name':'WordPress local acceptance'},token)
assert session['code']==200
scope={'p_session':session['data']['session_id'],'p_token':session['data']['token']}
symbols=[]
for oid in ids:
    tickets=json.loads(sql(f'select json_agg(t) from (select distinct t.id,t.ticket_symbol from eshop.tickets t join eshop.order_product_ticket opt on opt.ticket=t.id where opt."order"={int(oid)})t'))
    for t in tickets:
        symbols.append(t['ticket_symbol'])
        lookup=rpc('lookup_scanner_ticket',{**scope,'p_symbol':t['ticket_symbol']},token)
        assert lookup['code']==200
        op={'operation_id':str(uuid.uuid4()),'origin_session_id':scope['p_session'],'ticket_id':t['id'],'action':'admit_ticket','snapshot_id':None,'settings_revision':lookup['settings_revision'],'eligibility_fingerprint':lookup['data']['eligibility_fingerprint'],'confirm_unpaid':False,'captured_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
        result=rpc('sync_scanner_operations',{**scope,'p_operations':[op]},token)
        (PRIVATE/f'admission-{t["id"]}.json').write_text(json.dumps(result))
        first=result['data'][0]
        assert first['outcome']=='accepted',first.get('reason')
        replay=rpc('sync_scanner_operations',{**scope,'p_operations':[op]},token)
        assert replay['data'][0]['replayed']
        op['operation_id']=str(uuid.uuid4())
        again=rpc('sync_scanner_operations',{**scope,'p_operations':[op]},token)
        assert again['data'][0]['reason']=='already_used'
        passed('real scanner admission, same-operation replay and second-entry rejection',ticket_id=t['id'],first=first['reason'],second=again['data'][0]['reason'])
(PRIVATE/'expected-ticket-symbols.json').write_text(json.dumps(symbols))
(ROOT/('evidence/'+os.environ.get('VO_ACCEPTANCE_RECEIPT','service-receipt.json'))).write_text(json.dumps(receipt,indent=2)+'\n')
print(f'PASS: {len(receipt["cases"])} local real-service cases; {pdf_count} PDFs captured; no external sends or payments')
