"""Verify native Safari UI requests against disposable canonical owners.

Run after the documented native Safari purchases, before stopping the backend.
Private inputs contain real browser command identities and never enter evidence.
"""
import base64,datetime,hashlib,json,subprocess,urllib.request,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
P=ROOT/'.private'
s=json.loads((P/'backend-status.json').read_text())
assert s['API_URL']=='http://127.0.0.1:59821'
DB='supabase_db_festapp-vo-wordpress-20261023'
def sql(q):return subprocess.check_output(['docker','exec',DB,'psql','-X','-U','postgres','-d','postgres','-Atqc',q],text=True).strip()
assert sql('select title from public.organizations where id=1')=='Test Organization'
def request(path,body=None,token=None,headers=None):
 h={'apikey':s['ANON_KEY'],'Authorization':'Bearer '+(token or s['ANON_KEY']),'Content-Type':'application/json'}
 h.update(headers or {})
 req=urllib.request.Request(s['API_URL']+path,data=json.dumps(body).encode() if body is not None else None,headers=h)
 with urllib.request.urlopen(req,timeout=60) as r:
  raw=r.read();return json.loads(raw) if raw else None
calls=json.loads((P/'safari-order-fetch.json').read_text())
payloads=[json.loads(c['body']) for c in calls]
assert [c['status'] for c in calls]==[0,0,200]
assert len({p['commandId'] for p in payloads})==len({p['clientId'] for p in payloads})==1
rows=json.loads(sql("select json_agg(x) from (select o.id,o.state,o.price,o.payment_info,p.variable_symbol,o.data->>'email' email from eshop.orders o join eshop.payment_info p on p.id=o.payment_info where o.data->>'email' in ('safari-retry@example.invalid','safari-seat@example.invalid'))x"))
assert len(rows)==2 and all(float(r['price'])==120 for r in rows)
ordinary=next(r for r in rows if r['email']=='safari-retry@example.invalid')
for _ in range(2):assert request('/functions/v1/send-ticket-order',payloads[-1])['ticketOrder']['order']['id']==ordinary['id']
assert sql('select count(*) from eshop.orders')=='2'
auth=request('/auth/v1/token?grant_type=password',{'email':'1+t@t.com','password':'test'})
token=auth['access_token']
def rpc(name,args):return request('/rest/v1/rpc/'+name,args,token)
for row in rows:
 if row['state']=='ordered':
  rpc('insert_manual_transaction',{'p_amount':120,'p_currency':'CZK','p_unit_id':1,'p_variable_symbol':str(row['variable_symbol']),'p_date':datetime.datetime.now(datetime.timezone.utc).isoformat(),'p_note':'Synthetic Safari acceptance; no real payment','p_payment_info_id':row['payment_info']})
 assert sql(f"select state from eshop.orders where id={int(row['id'])}") in ('paid','sent')
seat_order=next(r['id'] for r in rows if r['email']=='safari-seat@example.invalid')
seat=json.loads(sql("select json_agg(json_build_object('title',s.title,'order_id',opt.\"order\")) from eshop.spots s join eshop.order_product_ticket opt on opt.id=s.order_product_ticket where s.title='A2'"))
assert seat and seat[0]['order_id']==seat_order,seat
env=dict(l.split('=',1) for l in (P/'edge.env').read_text().splitlines())
capture=request('/functions/v1/vo-local-capture',headers={'x-local-capture':env['VO_CAPTURE_SECRET']})
assert capture['mode']=='capture_only_no_provider_send'
(P/'safari-email-capture.json').write_text(json.dumps(capture))
pdfs=[]
for row in rows:
 cs=[c for c in capture['captures'] if c['order_id']==row['id']]
 assert {'order_confirmation','order_tickets'}<={c['kind'] for c in cs}
 assert not any(c.get('error') for c in cs)
 for c in cs:
  for a in c.get('prepared',{}).get('attachments',[]):
   if a['contentType']=='application/pdf':
    data=base64.b64decode(a['content']);assert data.startswith(b'%PDF-')
    name=f"safari-order-{row['id']}.pdf";(P/name).write_bytes(data)
    pdfs.append({'order_id':row['id'],'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
assert len(pdfs)==2
session=rpc('open_scanner_session',{'p_occasion':1,'p_device_name':'Native Safari WordPress acceptance'})
assert session['code']==200
scope={'p_session':session['data']['session_id'],'p_token':session['data']['token']}
symbols=[];admissions=[]
for row in rows:
 tickets=json.loads(sql(f"select json_agg(t) from (select distinct t.id,t.ticket_symbol from eshop.tickets t join eshop.order_product_ticket opt on opt.ticket=t.id where opt.\"order\"={int(row['id'])})t"))
 for ticket in tickets:
  symbols.append(ticket['ticket_symbol'])
  lookup=rpc('lookup_scanner_ticket',{**scope,'p_symbol':ticket['ticket_symbol']})
  assert lookup['code']==200
  op={'operation_id':str(uuid.uuid4()),'origin_session_id':scope['p_session'],'ticket_id':ticket['id'],'action':'admit_ticket','snapshot_id':None,'settings_revision':lookup['settings_revision'],'eligibility_fingerprint':lookup['data']['eligibility_fingerprint'],'confirm_unpaid':False,'captured_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
  result=rpc('sync_scanner_operations',{**scope,'p_operations':[op]})['data'][0]
  assert result['outcome']=='accepted',result.get('reason')
  assert rpc('sync_scanner_operations',{**scope,'p_operations':[op]})['data'][0]['replayed']
  op['operation_id']=str(uuid.uuid4())
  assert rpc('sync_scanner_operations',{**scope,'p_operations':[op]})['data'][0]['reason']=='already_used'
  admissions.append({'ticket_id':ticket['id'],'first':'accepted','same_operation':'replayed','second_entry':'already_used'})
(P/'safari-ticket-symbols.json').write_text(json.dumps(symbols))
logs=[json.loads(l) for l in (P/'safari-sink-access.jsonl').read_text().splitlines()]
pdf_get=next(x for x in logs if x['path']=='/ticket.pdf')
assert pdf_get['sha256']==hashlib.sha256((P/'safari-ticket.pdf').read_bytes()).hexdigest()
assert 'Safari/' in pdf_get['user_agent'] and 'iPhone' in pdf_get['user_agent']
receipt={'status':'PASS','browser':'Native Mobile Safari 26.5 / iOS 26.5 simulator, task-owned iPhone 17 Pro','driver':'Apple safaridriver, W3C WebDriver; create session after simctl bootstatus completed','interaction':'Actual DOM input/change, click and TouchEvent through native Safari WebDriver; no order or capacity mock. Native element send-keys/click is unreliable on this host.','anonymous_wp_iframe':True,'ordinary_order_id':ordinary['id'],'seat':'A2','orders':len(rows),'price_each_czk':120,'storage':'localStorage and sessionStorage getters throw SecurityError in ordinary form before entry; natural native Safari settings otherwise unchanged','outage':'Owned Kong stopped, no order; first retry before full recovery also failed; retained form retries [0,0,200] use same command/client identity','replay':'Same accepted UI command replayed twice; still two orders total including seat purchase','payment':'Existing manual transaction RPC; no real transfer or provider','email':capture['mode'],'pdfs':pdfs,'pdf_browser_download':{**pdf_get,'rendered_content_type':'application/pdf','method':'Actual canonical queued-email attachment served by loopback capture sink; native Safari link fetched and opened it in built-in PDF preview. Save to Files/share sheet not tested.'},'admissions':admissions,'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
(ROOT/'evidence/ios-safari-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('PASS: native Safari ordinary + A2, same-command outage retry, two canonical PDFs, native PDF retrieval, real scanner admission/replay/rejection')
