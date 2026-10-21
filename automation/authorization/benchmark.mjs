// Real SQL workload measurements. Only the task-owned, email-fenced local DB.
import { createRequire } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
import { performance } from 'node:perf_hooks';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
const { Client } = createRequire(new URL('../../web_client/package.json', import.meta.url))('pg');
export const databaseUrl = process.env.FESTAPP_AUTHORIZATION_DATABASE_URL;
export async function connect() {
    const u = new URL(databaseUrl);
    assert.equal(u.hostname, '127.0.0.1'); assert.equal(u.port, '61022');
    const db = new Client({ connectionString: databaseUrl }); await db.connect();
    assert.equal((await db.query('select project from festapp_test_support.disposable_environment')).rows[0].project, 'festapp-authz-20261020');
    assert.equal((await db.query('show cron.launch_active_jobs')).rows[0]['cron.launch_active_jobs'], 'off');
    assert.equal((await db.query('select bool_and(paused AND worker_url IS NULL) safe from email_capacity')).rows[0].safe, true);
    return db;
}
export async function executionContract(db) {
    const functions=(await db.query(`select p.oid::regprocedure::text signature,md5(p.prosrc) body_md5,
        p.prosecdef definer,p.provolatile volatility,p.proconfig settings
        from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f'
        and not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass and d.objid=p.oid and d.deptype='e')
        order by 1`)).rows;
    const policies=(await db.query("select schemaname,tablename,policyname,cmd,roles,qual,with_check from pg_policies where schemaname in ('public','eshop','storage') order by 1,2,3")).rows;
    return {functions,policies};
}
export function verifyWorkload(name,response,f) {
    if(name==='context') assert.equal(response.rows[0].get_app_config_v218.code,200);
    if(name==='editor_bundle') assert.equal(response.rows[0].get_map_editor_bundle_v1.code,200);
    if(name==='operator') assert.equal(response.rows[0].get_operator_access_v1.occasions.length,f.count);
    if(name==='rls_list') assert.equal(response.rows.length,50,'RLS workload must return every owned visible fixture place');
    if(name==='write') assert.equal(response.rows[0].create_occasion_client_sync_v1.status,'applied');
}
export async function fixture(db, count, bankCount=0) {
    const alias='authorization-'+randomUUID();
    await db.query('select public.create_user_for_test($1,$2)',[alias,alias+'@example.invalid']);
    const actor=(await db.query('select public.get_user_id($1) id',[alias])).rows[0].id;
    const org = Number((await db.query("insert into organizations(title,data) values('Authorization benchmark','{}') returning id")).rows[0].id);
    const unit = Number((await db.query("insert into units(title,organization) values('Authorization benchmark',$1) returning id", [org])).rows[0].id);
    await db.query(`insert into abuse_policy_overrides(rule_key,target_kind,target_id,base_limit,expires_at,reason,author) select rule_key,scope_kind,CASE WHEN scope_kind='unit' THEN $1::bigint ELSE $2::bigint END,least(hard_cap,greatest(base_limit,$3::bigint+100)),now()+interval '1 hour','Synthetic authorization benchmark fixture','authorization benchmark' from abuse_policy_rules where kind='occupancy' AND scope_kind IN ('unit','organization')`,[unit,org,count]);
    await db.query('update user_info set organization=$1 where id=$2',[org,actor]);
    await db.query('insert into unit_users(unit,"user",is_manager,is_editor,is_editor_view) values($1,$2,true,true,true)',[unit,actor]);
    if(bankCount>0) {
        const banks=(await db.query("insert into eshop.bank_accounts(title,type,account_number) select 'Authorization benchmark bank','FIO',$1||s from generate_series(1,$2) s returning id",[alias,bankCount])).rows.map(r=>r.id);
        await db.query('insert into eshop.unit_bank_accounts(unit,bank_account,priority) select $1,unnest($2::bigint[]),0',[unit,banks]);
        await db.query('insert into eshop.bank_account_users(bank_account,"user",is_admin) select unnest($1::bigint[]),$2,true',[banks,actor]);
    }
    const rows = (await db.query(`insert into occasions(title,link,organization,unit,start_time,end_time,is_open,is_hidden,data,features)
      select 'Authz '||s,gen_random_uuid()::text,$1,$2,now(),now()+interval '1 day',true,false,'{}','[]' from generate_series(1,$3) s returning id,link`,[org,unit,count])).rows;
    await db.query('insert into occasion_link_reservations(slug,occasion) select link,id from occasions where organization=$1',[org]);
    await db.query('insert into occasion_users(occasion,"user",is_editor,is_editor_view,is_editor_order,is_editor_order_view,is_manager) select unnest($1::bigint[]),$2,true,true,true,true,true',[rows.map(r=>r.id),actor]);
    await db.query("insert into places(occasion,title) select $1,'Benchmark place '||s from generate_series(1,50) s",[rows[0].id]);
    await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true),set_config('festapp.email_wake','scheduled',true)",[actor]);
    await db.query('ANALYZE public.occasions; ANALYZE public.occasion_users; ANALYZE public.unit_users; ANALYZE public.places; ANALYZE public.demo_occasions; ANALYZE eshop.bank_account_users; ANALYZE eshop.bank_accounts; ANALYZE eshop.unit_bank_accounts');
    return {actor,org,unit,occasion:Number(rows[0].id),link:rows[0].link,count,bankCount};
}
export function workloads(f) {
    return [
        ['context','select public.get_app_config_v218($1::jsonb)',[JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})]],
        ['operator','select public.get_operator_access_v1($1,null,null)',[f.org]],
        ['editor_bundle','select public.get_map_editor_bundle_v1($1)',[f.occasion]],
        ['layout_authoring','select public.get_ticket_layout_for_authoring_v1($1)',[f.occasion]],
        ['rls_list','select id,title from public.places where occasion=$1 order by id',[f.occasion]],
        ['write','select public.create_occasion_client_sync_v1($1,$2::jsonb)',[randomUUID(),JSON.stringify({unit:f.unit,organization:f.org,title:'Benchmark write',start_time:'2027-01-01T18:00:00Z',end_time:'2027-01-02T02:00:00Z',is_hidden:true,is_open:false})]],
    ];
}
export async function measure(db,f,rounds=15,selected=null) {
    const result = {};
    await db.query('SET LOCAL ROLE authenticated');
    for(const [name,sql,args] of workloads(f)) {
        if(selected&&!selected.includes(name)) continue;
        const times=[],cold=[];
        for(let i=0;i<rounds+3;i++) {
            await db.query('SAVEPOINT workload');
            const start=performance.now(); const response=await db.query(sql,args); const elapsed=performance.now()-start;
            verifyWorkload(name,response,f);
            await db.query('ROLLBACK TO SAVEPOINT workload'); await db.query('RELEASE SAVEPOINT workload');
            if(i>=3) times.push(elapsed); else cold.push(elapsed);
        }
        await db.query('SAVEPOINT workload');
        const plan=(await db.query('EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) '+sql,args)).rows[0]['QUERY PLAN'];
        await db.query('ROLLBACK TO SAVEPOINT workload'); await db.query('RELEASE SAVEPOINT workload');
        const sorted=times.toSorted((a,b)=>a-b);
        result[name]={coldConnectionSamplesMs:cold,samplesMs:times,p50:sorted[Math.floor(sorted.length*.5)],p95:sorted[Math.ceil(sorted.length*.95)-1],throughputPerSecond:1000*times.length/times.reduce((a,b)=>a+b,0),rpcCount:1,plan};
    }
    await db.query('RESET ROLE'); return result;
}
if(process.argv[1]?.endsWith('/benchmark.mjs')) {
    const db=await connect(); const results={server:(await db.query('select version()')).rows[0].version,workloads:{}};
    try { for(const n of [8,1000]) {
        await db.query('BEGIN'); const f=await fixture(db,n);
        results.workloads[n]={fixture:{occasions:n,places:50,unitMemberships:1,occasionMemberships:n},results:await measure(db,f)};
        await db.query('ROLLBACK');
    }} finally {await db.end();}
    await writeFile(process.argv[2],JSON.stringify(results,null,2)+'\n');
    console.log('Measured 6 SQL workloads at 8 and 1000 occasions.');
}
