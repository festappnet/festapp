// A fresh disposable loopback database only. Creates synthetic rows; project is
// discarded after the run. Never use against a shared local or production DB.
import pg from 'pg';
import assert from 'node:assert/strict';
const url = process.env.DATABASE_URL;
if (!url || !['127.0.0.1', 'localhost'].includes(new URL(url).hostname) ||
    process.env.FESTAPP_DISPOSABLE_PRICE_DB !== 'yes') throw new Error('Disposable loopback database required');
const connections = [0,1,2].map(() => new pg.Client({ connectionString: url }));
const [setup, a, b] = connections;
await Promise.all(connections.map(c => c.connect()));
await Promise.all(connections.map(c => c.query("set lock_timeout='5s'; set statement_timeout='10s'")));
try {
  const aPid=(await a.query('select pg_backend_pid()')).rows[0].pg_backend_pid;
  const bPid=(await b.query('select pg_backend_pid()')).rows[0].pg_backend_pid;
  const waitLock=async pid => {
    for(let i=0;i<200;i++) {
      const blocked=(await setup.query("select wait_event_type='Lock' blocked from pg_stat_activity where pid=$1",[pid])).rows[0]?.blocked;
      if(blocked) return;
      await new Promise(resolve=>setTimeout(resolve,10));
    }
    throw new Error('Expected real lock contention');
  };
  const actor = (await setup.query('select id,organization from public.user_info limit 1')).rows[0];
  const unit = (await setup.query('select id from public.units where organization=$1 limit 1',[actor.organization])).rows[0].id;
  const occasion = (await setup.query(`insert into public.occasions(organization,unit,title,link,start_time,end_time)
    values($1,$2,'Concurrency','price-race-'||gen_random_uuid(),now(),now()+interval '1 day') returning id`,[actor.organization,unit])).rows[0].id;
  await setup.query('insert into public.occasion_users("user",occasion,is_editor_order,is_editor_order_view) values($1,$2,true,true)',[actor.id,occasion]);
  const type = (await setup.query("insert into eshop.product_types(occasion,title) values($1,'Race') returning id",[occasion])).rows[0].id;
  const product = (await setup.query("insert into eshop.products(occasion,product_type,title,price,currency_code) values($1,$2,'Race',450,'CZK') returning id",[occasion,type])).rows[0].id;
  const insert = async (amount,minutes) => (await setup.query(`insert into eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion)
    values('products.price',$1,$2,now()-($3||' minutes')::interval,$4) returning id`,[product,String(amount),minutes,occasion])).rows[0].id;
  await insert(550,3); await insert(650,2); await insert(500,1);
  await a.query('begin');
  await a.query('select public.apply_planned_changes()');
  await b.query('select public.apply_planned_changes()'); // advisory lock: no duplicate execution
  await a.query('commit');
  const current = async () => Number((await setup.query('select price from eshop.products where id=$1',[product])).rows[0].price);
  assert.equal(await current(),500);
  assert.equal(Number((await setup.query("select count(*) from public.client_commits where occasion=$1 and source='inventory.product.planned'",[occasion])).rows[0].count),3);
  // Worker owns product lock, cancellation waits then gets a version conflict.
  const late = await insert(600,1);
  await a.query('begin'); await a.query('select public.apply_planned_changes()');
  await b.query("select set_config('request.jwt.claim.sub',$1,false)",[actor.id]);
  const cancel = b.query('select public.cancel_product_price_change($1,$2,1)',[product,late]).then(() => null,e => e);
  await waitLock(bPid);
  await a.query('commit');
  const conflict = await cancel;
  assert.equal(conflict?.code,'40001');
  assert.equal(await current(),600);
  // Cancellation owns the product lock before worker selection: worker rechecks.
  const cancelled = await insert(700,1);
  await b.query('begin'); await b.query('select public.cancel_product_price_change($1,$2,1)',[product,cancelled]);
  const worker = a.query('select public.apply_planned_changes()');
  await waitLock(aPid);
  await b.query('commit'); await worker;
  assert.equal(await current(),600);
  assert.equal((await setup.query('select id from eshop.planned_changes where id=$1',[cancelled])).rowCount,0);
  // Editor moves due plan into the future while worker waits on the product.
  const moved = await insert(800,1);
  await b.query('begin');
  await b.query("select public.save_product_price_change($1,800,now()+interval '1 day',$2,1)",[product,moved]);
  const waiting = a.query('select public.apply_planned_changes()');
  await waitLock(aPid);
  await b.query('commit'); await waiting;
  assert.equal(await current(),600);
  console.log('PASS: two workers, cancel vs apply in both orders, edit vs apply');
} finally { await Promise.all(connections.map(c => c.end())); }
