import pg from 'pg';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const url=process.env.DATABASE_URL;
if (!url || !['127.0.0.1','localhost'].includes(new URL(url).hostname) || process.env.FESTAPP_DISPOSABLE_PRICE_DB!=='yes') throw new Error('Disposable loopback database required');
const db=new pg.Client({connectionString:url});await db.connect();
try {
 await db.query('begin');
 await db.query('drop index eshop.planned_product_price_instant_unique; drop index eshop.planned_product_price_pending; drop index eshop.planned_changes_due; alter table eshop.planned_changes drop column revision,drop column failed_at,drop column failure_code');
 const actor=(await db.query('select id,organization from public.user_info limit 1')).rows[0];
 const unit=(await db.query('select id from public.units where organization=$1 limit 1',[actor.organization])).rows[0].id;
 const occasion=(await db.query("insert into public.occasions(organization,unit,title,link,start_time,end_time) values($1,$2,'Migration','price-migration-'||gen_random_uuid(),now(),now()+interval '1 day') returning id",[actor.organization,unit])).rows[0].id;
 const type=(await db.query("insert into eshop.product_types(occasion,title) values($1,'Migration') returning id",[occasion])).rows[0].id;
 const product=(await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code) values($1,$2,'Migration',100,'CZK') returning id,occasion",[occasion,type])).rows[0];
 const insert=async(value,days,subject=product.id) => (await db.query(`insert into eshop.planned_changes(change_type,subject_id,new_value,change_time,occasion)
 values('products.price',$1,$2,now()+($3||' days')::interval,null) returning id`,[subject,value,days])).rows[0].id;
 const valid=await insert('999',100); const dup1=await insert('1000',101); const dup2=await insert('1001',101);
 const bad=await insert('bad-value',102);const orphan=await insert('100',103,-100);
 await db.query(fs.readFileSync('supabase/migrations/20261004150000_product_price_scheduling.sql','utf8'));
 const rows=(await db.query('select * from eshop.planned_changes where id=any($1::bigint[])',[[valid,dup1,dup2,bad,orphan]])).rows;
 assert.equal(rows.length,5);const good=rows.find(r=>r.id===valid);
 assert.equal(good.occasion,product.occasion);assert.equal(good.failed_at,null);assert.equal(good.new_value,'999');
 assert.equal(rows.filter(r=>r.failed_at!==null).length,4);assert.equal(rows.filter(r=>r.applied).length,0);
 console.log('PASS: legacy valid plan preserved, ownership backfilled, both duplicates + invalid value + orphan retained as failures');
} finally {await db.query('rollback');await db.end();}
