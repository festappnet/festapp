import test from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import { readFile } from 'node:fs/promises';
const url=process.env.SCANNER_DATABASE_URL;
function assertIsolated() { const u=new URL(url); assert.ok(['127.0.0.1','localhost'].includes(u.hostname)); assert.match(u.pathname,/^\/festapp_scanner_/); }
test('C04-C05: two SQL connections serialize admission, cancellation and payment; replay after unused is immutable',{skip:!url},async()=>{
    assertIsolated(); const a=new pg.Client({connectionString:url}),b=new pg.Client({connectionString:url});await a.connect();await b.connect();
    try {
        await a.query(await readFile(new URL('../../../database/tests/scanning/fixture.sql',import.meta.url),'utf8'));
        const fx=(await a.query('select public.scanner_test_fixture(4) fx')).rows[0].fx;
        const open=async client=>(await client.query('select public.open_scanner_session($1) r',[fx.scan_code])).rows[0].r.data;
        const sa=await open(a),sb=await open(b);
        const lookup=async(client,s,tid)=>(await client.query('select public.lookup_scanner_ticket($1,$2,(select ticket_symbol from eshop.tickets where id=$3)) r',[s.session_id,s.token,tid])).rows[0].r;
        const operation=(s,r)=>({operation_id:crypto.randomUUID(),origin_session_id:s.session_id,action:'admit_ticket',ticket_id:r.data.ticket_id,snapshot_id:null,settings_revision:r.settings_revision,eligibility_fingerprint:r.data.eligibility_fingerprint,confirm_unpaid:false,captured_at:new Date().toISOString()});
        const sync=async(client,s,op)=>(await client.query('select public.sync_scanner_operations($1,$2,$3) r',[s.session_id,s.token,JSON.stringify([op])])).rows[0].r.data[0];
        const ra=await lookup(a,sa,fx.tickets[0]),rb=await lookup(b,sb,fx.tickets[0]);const oa=operation(sa,ra),ob=operation(sb,rb);
        await a.query('begin');const accepted=await sync(a,sa,oa);assert.equal(accepted.outcome,'accepted');
        let finished=false;const second=sync(b,sb,ob).then(r=>{finished=true;return r;});await new Promise(r=>setTimeout(r,80));assert.equal(finished,false,'second connection waits for ticket owner');await a.query('commit');assert.equal((await second).reason,'already_used');
        const historic=await sync(a,sa,oa);assert.equal(historic.replayed,true);assert.equal(historic.committed_at,accepted.committed_at);
        await a.query("update eshop.tickets set state='sent',updated_at=clock_timestamp() where id=$1",[fx.tickets[0]]);await sync(a,sa,oa);assert.equal((await a.query('select state from eshop.tickets where id=$1',[fx.tickets[0]])).rows[0].state,'sent');
        for(const kind of ['storno','payment']) {
            const tid=fx.tickets[kind==='storno'?1:2],r=await lookup(b,sb,tid),op=operation(sb,r);
            const parent=(await a.query('select "order" id from eshop.order_product_ticket where ticket=$1',[tid])).rows[0].id;
            await a.query('begin');await a.query('select public.lock_order_capacity_scope_internal(ARRAY[$1]::bigint[])',[parent]);
            await a.query("update eshop.orders set state=$2,updated_at=clock_timestamp() where id=$1",[parent,kind==='storno'?'storno':'paid']);
            const waiting=sync(b,sb,op);await new Promise(r=>setTimeout(r,50));await a.query('commit');const result=await waiting;assert.notEqual(result.outcome,'accepted',`${kind} race cannot use stale eligibility`);
        }
        console.log('SQL concurrency: 2 connections, 3 contested parent/ticket transactions, no deadlock');
    } finally {await a.query('rollback').catch(()=>{});await b.query('rollback').catch(()=>{});await a.end();await b.end();}
});
