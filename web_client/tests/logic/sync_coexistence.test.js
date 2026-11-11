import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../database/disposable_database.js';

test('Sync Coexistence Integration Test',async t=>{
    const databaseUrl=process.env.DATABASE_URL;
    if(!databaseUrl){t.skip('Run automation/test_all.sh web with its owned SQL workspace');return;}
    assertLocalDatabaseUrl(databaseUrl);
    const client=new pg.Client({connectionString:databaseUrl,ssl:false});
    await client.connect();
    try {
        await assertDisposableDatabase(client);
        await client.query('BEGIN');
        const link='sync-coexistence-'+randomUUID();
        const {rows:[org]}=await client.query("INSERT INTO public.organizations(title) VALUES('Sync coexistence fixture') RETURNING id");
        const {rows:[unit]}=await client.query("INSERT INTO public.units(title,organization) VALUES('Sync coexistence fixture',$1) RETURNING id",[org.id]);
        const {rows:[synced]}=await client.query(`INSERT INTO public.occasions
            (organization,unit,title,link,start_time,end_time,is_open,is_hidden,external_source,external_id)
            VALUES($1,$2,'Synced fixture',$3,now(),now()+interval '1 hour',true,false,'vstupenky_remote',$4) RETURNING id`,
            [org.id,unit.id,link,parseInt(randomUUID().replaceAll('-','').slice(0,12),16)]);
        let nativeId;
        await t.test('Should allow inserting duplicate link (Native)',async()=>{
            const {rows:[native]}=await client.query(`INSERT INTO public.occasions
                (organization,unit,title,link,start_time,end_time,is_open,is_hidden,external_source)
                VALUES($1,$2,'Native fixture',$3,now(),now()+interval '1 hour',true,false,NULL) RETURNING id`,
                [org.id,unit.id,link]);
            nativeId=native.id;assert.ok(nativeId,'Failed to return ID for native insert');
        });
        await t.test('Should have both occasions in DB',async()=>{
            const {rows}=await client.query('SELECT id,external_source FROM public.occasions WHERE link=$1',[link]);
            assert.equal(rows.length,2);
            assert.ok(rows.some(row=>row.id===synced.id&&row.external_source==='vstupenky_remote'),'Synced occasion missing');
            assert.ok(rows.some(row=>row.id===nativeId&&row.external_source===null),'Native occasion missing');
        });
    } finally {
        try {await client.query('ROLLBACK');} finally {await client.end();}
    }
});
