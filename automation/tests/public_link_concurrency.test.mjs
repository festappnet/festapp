import test from 'node:test';
import assert from 'node:assert/strict';
import pg from '../../web_client/node_modules/pg/lib/index.js';
const url = process.env.DATABASE_URL;
if (!url || !['127.0.0.1', 'localhost'].includes(new URL(url).hostname)) throw new Error('Isolated local DATABASE_URL required');
test('two real sessions cannot claim the same current or historical slug', async () => {
    const a = new pg.Client({ connectionString: url });
    const b = new pg.Client({ connectionString: url });
    await Promise.all([a.connect(), b.connect()]);
    const slug = 'concurrent-' + crypto.randomUUID();
    let ids = [];
    try {
        const rows = await a.query("INSERT INTO public.occasions(title,link,start_time,end_time) VALUES('Concurrency A','',now(),now()+interval '1 day'),('Concurrency B','',now(),now()+interval '1 day') RETURNING id");
        ids = rows.rows.map(row => row.id);
        await Promise.all([a.query('BEGIN'), b.query('BEGIN')]);
        await a.query("UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',id,$1,true) WHERE id=$2", [slug, ids[0]]);
        const loser = b.query("UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',id,$1,true) WHERE id=$2", [slug, ids[1]]);
        // Attach a rejection handler before releasing the winning transaction.
        const collision = assert.rejects(loser, error => error.code === '23505');
        await a.query('COMMIT');
        await collision;
        await b.query('ROLLBACK');
        await a.query("UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',id,$1) WHERE id=$2", [slug + '-new', ids[0]]);
        await assert.rejects(b.query("SELECT public.reserve_public_link_internal('occasion',$1,$2)", [ids[1], slug]), error => error.code === '23505');
        const row = await b.query('SELECT public.resolve_occasion_link_internal($1) id', [slug]);
        assert.equal(row.rows[0].id, ids[0]);
    } finally {
        await Promise.all([a.query('ROLLBACK'), b.query('ROLLBACK')]);
        if (ids.length) await a.query('DELETE FROM public.occasions WHERE id=ANY($1::bigint[])', [ids]);
        await a.query('DELETE FROM public.occasion_link_reservations WHERE slug IN ($1,$2)', [slug, slug + '-new']);
        await Promise.all([a.end(), b.end()]);
    }
});
