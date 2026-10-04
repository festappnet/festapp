import assert from 'node:assert/strict';
import pg from 'pg';
const target = new URL(process.env.DATABASE_URL ?? '');
if (!['127.0.0.1', 'localhost'].includes(target.hostname) || !target.pathname.startsWith('/festapp_banksync_')) {
  throw new Error('BankSync concurrency checks require a dedicated local festapp_banksync_* database');
}
const clients = [new pg.Client({connectionString:target.toString()}),new pg.Client({connectionString:target.toString()})];
await Promise.all(clients.map(c=>c.connect()));
const [a,b]=clients;
let bank, connection, pi;
let delivery=1;
const event=(movement,amount=1000)=>({event:'transaction.received',event_version:'2',delivery_id:`01K${String(delivery++).padStart(23,'0')}`,
  pairing_code:'0123456789',data:{id:delivery,bank_account_id:42,amount_cents:amount,currency:'CZK',date:'2026-10-04T12:00:00Z',
  direction:amount>0?'incoming':amount<0?'outgoing':'zero',identity_kind:'movement',identity_provenance:'fio_api_column22',
  source:'fio_api',transaction_id:String(movement),raw_vs:'12345',payer_reference:null}});
const ingest=(client,payload)=>client.query('SELECT public.ingest_bank_sync_transaction($1,$2,$3,$4) AS receipt',['concurrency','festapp','a'.repeat(64),payload]);
try {
  bank=(await a.query("INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies) VALUES('Concurrency fixture','FIO','771234/2010',ARRAY['CZK']) RETURNING id")).rows[0].id;
  connection=(await a.query(`INSERT INTO eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,bank_account_id,physical_account,
    provider,mode,state,pairing_code,manifest_sha256) VALUES('concurrency','festapp','42',$1,'771234/2010','FIO','api','shadow','0123456789',$2) RETURNING id`,[bank,'a'.repeat(64)])).rows[0].id;
  pi=(await a.query("INSERT INTO eshop.payment_info(bank_account,variable_symbol,amount,currency_code) VALUES($1,12345,20,'CZK') RETURNING id",[bank])).rows[0].id;
  // Activation serializes with account updates before adopting movement IDs.
  await a.query('BEGIN');
  await a.query('SELECT id FROM eshop.bank_accounts WHERE id=$1 FOR UPDATE',[bank]);
  let activated=false;
  const activation=b.query('SELECT public.activate_bank_sync_connection($1,$2)',[connection,'a'.repeat(64)]).then(()=>activated=true);
  await new Promise(r=>setTimeout(r,50));assert.equal(activated,false);
  await a.query('COMMIT');await activation;
  const first=event('770002');
  await a.query('BEGIN');const r1=await ingest(a,first);
  let committed=false;const retry=ingest(b,first).then(r=>{committed=true;return r;});
  await new Promise(r=>setTimeout(r,50));assert.equal(committed,false);
  await a.query('COMMIT');assert.deepEqual((await retry).rows[0].receipt,r1.rows[0].receipt);
  await Promise.all([ingest(a,event('770003')),ingest(b,event('770004'))]);
  assert.equal((await a.query('SELECT paid FROM eshop.payment_info WHERE id=$1',[pi])).rows[0].paid,'30.00');
  const tx=(await a.query("SELECT id FROM eshop.transactions WHERE bank_account_id=$1 AND transaction_id=770002",[bank])).rows[0].id;
  await a.query('BEGIN');await a.query("SELECT public.apply_transaction_pairing($1,NULL,'test_unpair','system')",[tx]);
  const newTransport=ingest(b,event('770002'));await a.query('COMMIT');
  assert.equal((await newTransport).rows[0].receipt.outcome,'already_ingested');
  assert.equal((await a.query('SELECT paid FROM eshop.payment_info WHERE id=$1',[pi])).rows[0].paid,'20.00');
  console.log('PASS: duplicate delivery, concurrent payments, manual unpair/replay and account activation barrier (two sessions)');
} finally {
  await Promise.all(clients.map(c=>c.query('ROLLBACK').catch(()=>{})));
  if(bank) {
    await a.query('DELETE FROM eshop.bank_sync_inbox WHERE instance_id=$1',['concurrency']);
    await a.query('DELETE FROM eshop.bank_transaction_identities WHERE instance_id=$1',['concurrency']);
    await a.query('DELETE FROM eshop.transaction_pairing_events WHERE transaction_id IN (SELECT id FROM eshop.transactions WHERE bank_account_id=$1)',[bank]);
    await a.query('DELETE FROM eshop.transactions WHERE bank_account_id=$1',[bank]);
    await a.query('DELETE FROM eshop.bank_sync_connections WHERE id=$1',[connection]);
    await a.query('DELETE FROM eshop.payment_info WHERE id=$1',[pi]);
    await a.query('DELETE FROM eshop.bank_accounts WHERE id=$1',[bank]);
  }
  await Promise.all(clients.map(c=>c.end()));
}
