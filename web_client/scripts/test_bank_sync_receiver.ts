// Optional real PostgreSQL integration check. Run only against the disposable local DB.
import {buildWebhookEnvelope,signWebhook,type Transaction} from 'npm:@festapp/banksync@0.2.2';
import {bankSyncWebhook} from '../../supabase/functions/bank-sync-webhook/handler.ts';
const target = new URL(Deno.env.get('DATABASE_URL') ?? '');
if (!['127.0.0.1','localhost'].includes(target.hostname) || !target.pathname.startsWith('/festapp_banksync_')) {
  throw new Error('Receiver integration requires a dedicated local festapp_banksync_* database');
}
const literal = (value:string) => "'"+value.replaceAll("'","''")+"'";
async function sql(query:string) {
  const result = await new Deno.Command('psql',{args:[target.toString(),'-X','-qAt','-v','ON_ERROR_STOP=1','-c',query],stdout:'piped',stderr:'piped'}).output();
  if (!result.success) throw new Error(new TextDecoder().decode(result.stderr));
  return new TextDecoder().decode(result.stdout).trim();
}
function assert(value:unknown,message:string):asserts value {if(!value) throw new Error(message);}
const namespace='receiver-fixture-'+crypto.randomUUID();
const secret='synthetic-receiver-test-secret';
let bank:string|undefined, connection:string|undefined, payment:string|undefined;
let organization:string|undefined, unit:string|undefined, occasion:string|undefined, order:string|undefined, ticket:string|undefined;
try {
  assert(await sql('SELECT paused AND worker_url IS NULL FROM public.email_capacity WHERE singleton')==='t','local queue must be paused and targetless to prohibit real sends');
  organization=await sql("INSERT INTO public.organizations(title) VALUES('Receiver ticket fixture') RETURNING id");
  unit=await sql(`INSERT INTO public.units(title,organization) VALUES('Receiver unit',${organization}) RETURNING id`);
  occasion=await sql(`INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time,is_order_synchronization_enabled)
    VALUES('Receiver occasion',${organization},${unit},${literal(crypto.randomUUID())},now(),now()+interval '1 day',true) RETURNING id`);
  bank=await sql("INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies) VALUES('Receiver fixture','FIO','881234/2010',ARRAY['EUR']) RETURNING id");
  connection=await sql(`INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256) VALUES(${literal(namespace)},'festapp','42',${bank},'881234/2010','FIO','api','shadow','0123456789',repeat('a',64)) RETURNING id`);
  await sql(`SELECT public.activate_bank_sync_connection(${connection},repeat('a',64))`);
  payment=await sql(`INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code) VALUES(${bank},4567,10.07,'EUR') RETURNING id`);
  order=await sql(`INSERT INTO eshop.orders(occasion,state,data,price,currency_code,payment_info)
    VALUES(${occasion},'ordered','{"email":"receiver@example.invalid"}',10.07,'EUR',${payment}) RETURNING id`);
  ticket=await sql(`INSERT INTO eshop.tickets(occasion,state) VALUES(${occasion},'ordered') RETURNING id`);
  await sql(`INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(${order},${ticket})`);
  const transaction:Transaction={id:1,bank_account_id:42,amount_cents:1007,currency:'EUR',date:'2026-10-04T12:00:00Z',
    vs:'4567',raw_vs:'4567',payer_reference:null,ks:null,ss:null,message:null,counter_account:null,bank_code:null,bank_name:null,
    sender_name:null,user_identification:null,transaction_type:null,performed_by:null,comment:null,command_id:'777',
    source:'fio_api',date_offset_min:0,transaction_id:'880001',external_id:null,direction:'incoming',identity_kind:'movement',identity_provenance:'fio_api_column22'};
  const event=buildWebhookEnvelope({delivery_id:'01K00000000000000000000001',pairing_code:'0123456789',transaction,event_version:'2'});
  let calls=0;
  const deps={secret,instanceId:namespace,ingest:async(digest:string,envelope:unknown)=>{
    calls++;
    return JSON.parse(await sql(`SELECT public.ingest_bank_sync_transaction(${literal(namespace)},'festapp',${literal(digest)},${literal(JSON.stringify(envelope))}::jsonb)`));
  }};
  async function request(envelope=event,badSignature=false) {
    const signed=await signWebhook({secret,envelope});
    const headers=new Headers(signed.headers);
    if(badSignature) headers.set('x-banksync-signature','sha256='+'0'.repeat(64));
    return bankSyncWebhook(new Request('https://api.festapp.net/functions/v1/bank-sync-webhook',{method:'POST',headers,body:new Uint8Array(signed.bodyBytes)}),deps);
  }
  const first=await request();assert(first.status===200,'first valid bank fact must commit');const receipt=await first.json();
  const retry=await request();assert(retry.status===200,'lost HTTP response must be retryable');
  assert(JSON.stringify(await retry.json())===JSON.stringify(receipt),'retry returns stable committed receipt');
  assert(await sql(`SELECT paid FROM eshop.payment_info WHERE id=${payment}`)==='10.07','one financial effect');
  assert(await sql(`SELECT state FROM eshop.orders WHERE id=${order}`)==='paid','webhook atomically makes order paid');
  assert(await sql(`SELECT state FROM eshop.tickets WHERE id=${ticket}`)==='paid','webhook makes ticket eligible');
  assert(await sql(`SELECT count(*) FROM public.email_messages WHERE order_id=${order} AND message_kind='order_tickets' AND workflow_state='pending' AND target_time<=now()`)==='1','webhook immediately creates one due ticket intent behind the global gate');
  const duplicate=await request({...event,delivery_id:'01K00000000000000000000002'});
  assert(duplicate.status===200,'new transport identity must receive a receipt');
  assert(await sql(`SELECT paid FROM eshop.payment_info WHERE id=${payment}`)==='10.07','new transport does not re-credit');
  assert(await sql(`SELECT count(*) FROM public.email_messages WHERE order_id=${order} AND message_kind='order_tickets'`)==='1','webhook transport retries do not re-enqueue ticket mail');
  const conflict=await request({...event,data:{...event.data,amount_cents:1008}});
  assert(conflict.status===409,'same delivery with changed facts must conflict');
  const before=calls;assert((await request(event,true)).status===401 && calls===before,'bad HMAC never reaches SQL');
  const outgoing=await request({...event,delivery_id:'01K00000000000000000000003',data:{...event.data,id:2,transaction_id:'880002',amount_cents:-1007,direction:'outgoing'}});
  assert(outgoing.status===200,'outgoing bank fact is retained');
  assert(await sql(`SELECT sum(amount) FROM eshop.transactions WHERE bank_account_id=${bank}`)==='0.00','signed ledger total preserved');
  console.log('PASS: pinned package -> raw HMAC receiver -> real SQL matcher -> stable receipt, signed ledger, one financial effect and immediately due globally gated ticket intent');
} finally {
  if(bank) await sql(`DELETE FROM eshop.bank_sync_inbox WHERE instance_id=${literal(namespace)};
    DELETE FROM eshop.bank_transaction_identities WHERE instance_id=${literal(namespace)};
    DELETE FROM eshop.transaction_pairing_events WHERE transaction_id IN (SELECT id FROM eshop.transactions WHERE bank_account_id=${bank});
    DELETE FROM eshop.transactions WHERE bank_account_id=${bank};DELETE FROM eshop.bank_sync_connections WHERE id=${connection ?? 'NULL'};
    DELETE FROM public.email_messages WHERE order_id=${order ?? 'NULL'};
    DELETE FROM eshop.order_product_ticket WHERE "order"=${order ?? 'NULL'};DELETE FROM eshop.tickets WHERE id=${ticket ?? 'NULL'};
    DELETE FROM eshop.orders WHERE id=${order ?? 'NULL'};
    DELETE FROM eshop.payment_info WHERE id=${payment ?? 'NULL'};DELETE FROM eshop.bank_accounts WHERE id=${bank};`);
  if(occasion) await sql(`DELETE FROM public.occasions WHERE id=${occasion}`);
  if(unit) await sql(`DELETE FROM public.units WHERE id=${unit}`);
  if(organization) await sql(`DELETE FROM public.organizations WHERE id=${organization}`);
}
