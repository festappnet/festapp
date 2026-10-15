import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import pg from '../../web_client/node_modules/pg/lib/index.js';
const url = process.env.DATABASE_URL;
if (!url || !['127.0.0.1', 'localhost'].includes(new URL(url).hostname)) throw new Error('Isolated local DATABASE_URL required');
test('backfill preserves existing cross-tenant duplicate URLs and blocks new claims', async () => {
    const db = new pg.Client({ connectionString: url });
    await db.connect();
    try {
        await db.query('BEGIN');
        const orgs = (await db.query("INSERT INTO public.organizations(title) VALUES('Legacy A'),('Legacy B') RETURNING id")).rows.map(row => row.id);
        const slug = 'legacy-' + crypto.randomUUID();
        const rows = (await db.query("INSERT INTO public.occasions(title,link,organization,start_time,end_time,is_open,is_hidden) VALUES('Existing A',$1,$2,now(),now()+interval '1 day',true,false),('Existing B',$1,$3,now(),now()+interval '1 day',true,false) RETURNING id,title,link", [slug, ...orgs])).rows;
        await db.query('TRUNCATE public.legacy_occasion_link_bindings,public.occasion_link_reservations,public.form_link_reservations');
        await db.query(await readFile(new URL('../../database/functions/public_links/backfill.sql', import.meta.url), 'utf8'));
        const after = (await db.query('SELECT id,title,link FROM public.occasions WHERE id=ANY($1::bigint[]) ORDER BY id', [rows.map(row => row.id)])).rows;
        assert.deepEqual(after, rows);
        for (let i = 0; i < 2; i++) {
            assert.equal((await db.query('SELECT public.resolve_occasion_link_internal($1,$2) id', [slug, orgs[i]])).rows[0].id, rows[i].id);
            const config = (await db.query("SELECT public.get_app_config_v218(jsonb_build_object('platform',jsonb_build_object('platform','web'),'organization',$1::bigint,'link',$2::text)) config", [orgs[i],slug])).rows[0].config;
            assert.equal(String(config.occasion.id), rows[i].id);
        }
        assert.equal((await db.query('SELECT public.resolve_occasion_link_internal($1,NULL) id', [slug])).rows[0].id, null);
        await db.query("UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',id,$1) WHERE id=$2", [slug+'-new',rows[0].id]);
        assert.equal((await db.query('SELECT public.resolve_occasion_link_internal($1,$2) id', [slug,orgs[0]])).rows[0].id, rows[0].id);
        await db.query("UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',id,$1) WHERE id=$2", [slug,rows[0].id]);
        await db.query('DELETE FROM public.occasions WHERE id=$1', [rows[0].id]);
        assert.equal((await db.query('SELECT public.resolve_occasion_link_internal($1,$2) id', [slug,orgs[0]])).rows[0].id, null);
        const target = (await db.query("INSERT INTO public.occasions(title,link,start_time,end_time) VALUES('Future event','',now(),now()+interval '1 day') RETURNING id")).rows[0].id;
        await db.query('SAVEPOINT collision');
        await assert.rejects(db.query("SELECT public.reserve_public_link_internal('occasion',$1,$2,true)", [target,slug]), error => error.code === '23505');
        await db.query('ROLLBACK TO collision');
        assert.equal((await db.query('SELECT public.resolve_occasion_link_internal($1,$2) id', [slug,orgs[1]])).rows[0].id, rows[1].id);
    } finally {
        await db.query('ROLLBACK');
        await db.end();
    }
});
