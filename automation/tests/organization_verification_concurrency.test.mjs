// Opt-in against the disposable local DB only. No .env or remote fallback.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';
const require = createRequire(new URL('../../web_client/package.json', import.meta.url));
const { Client } = require('pg');
const connectionString = process.env.FESTAPP_VERIFICATION_TEST_DATABASE_URL;

test('Unit lock serializes first creation and save versus review', { skip: !connectionString }, async () => {
    const url = new URL(connectionString);
    assert.ok(['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname), 'disposable loopback DB required');
    const db = new Client({ connectionString }); const a = new Client({ connectionString }); const b = new Client({ connectionString });
    await Promise.all([db.connect(), a.connect(), b.connect()]);
    let org; let unit; const manager = randomUUID(); const admin = randomUUID();
    const profile = { legalName: 'Concurrent fixture', countryCode: 'CZ', registrationNumber: '27074358', address: { street: 'Test 1', city: 'Praha', postalCode: '11000' }, contactEmail: 'fixture@example.invalid' };
    const rpc = async (client, sql, params) => (await client.query(sql, params)).rows[0].result;
    try {
        org = (await db.query("INSERT INTO organizations(title) VALUES('Concurrent legal fixture') RETURNING id")).rows[0].id;
        unit = (await db.query("INSERT INTO units(title,organization) VALUES('Concurrent legal fixture',$1) RETURNING id", [org])).rows[0].id;
        await db.query('INSERT INTO auth.users(id) VALUES($1),($2)', [manager, admin]);
        await db.query('INSERT INTO user_info(id,organization) VALUES($1,$3),($2,$3)', [manager, admin, org]);
        await db.query('INSERT INTO unit_users(unit,"user",is_manager) VALUES($1,$2,true)', [unit, manager]);
        await db.query('INSERT INTO organization_users(organization,"user",is_admin) VALUES($1,$2,true)', [org, admin]);
        await Promise.all([a.query("select set_config('request.jwt.claim.sub',$1,false)", [manager]), b.query("select set_config('request.jwt.claim.sub',$1,false)", [manager])]);
        await a.query('BEGIN');
        const first = await rpc(a, 'select save_unit_legal_profile($1,0,$2) result', [unit, profile]);
        assert.equal(first.code, 200);
        // B must wait on the Unit even though its transaction cannot yet see A's profile.
        const second = rpc(b, 'select save_unit_legal_profile($1,0,$2) result', [unit, profile]);
        await a.query('COMMIT');
        assert.equal((await second).code, 409);
        assert.equal((await db.query('select count(*)::int n from unit_legal_profile_audit where unit_id=$1', [unit])).rows[0].n, 1);
        assert.equal((await rpc(a, 'select submit_unit_verification($1,1) result', [unit])).code, 200);
        await b.query("select set_config('request.jwt.claim.sub',$1,false)", [admin]);
        await a.query('BEGIN');
        assert.equal((await rpc(a, 'select save_unit_legal_profile($1,2,$2) result', [unit, { ...profile, legalName: 'Changed while pending' }])).code, 200);
        const review = rpc(b, "select review_unit_verification($1,2,'approve',null,null,'Synthetic evidence') result", [unit]);
        await a.query('COMMIT');
        assert.equal((await review).code, 409);
        const row = (await db.query('select status,revision from unit_legal_profiles where unit_id=$1', [unit])).rows[0];
        assert.equal(row.status, 'unverified'); assert.equal(Number(row.revision), 3);
        assert.equal((await db.query('select count(*)::int n from unit_legal_profile_audit where unit_id=$1', [unit])).rows[0].n, 3);
    } finally {
        await Promise.allSettled([a.query('ROLLBACK'), b.query('ROLLBACK')]);
        if (unit) {
            await db.query('delete from unit_legal_profile_audit where unit_id=$1', [unit]);
            await db.query('delete from unit_users where unit=$1', [unit]);
            await db.query('delete from units where id=$1', [unit]);
        }
        if (org) {
            await db.query('delete from organization_users where organization=$1', [org]);
            await db.query('delete from user_info where id=any($1::uuid[])', [[manager, admin]]);
            await db.query('delete from auth.users where id=any($1::uuid[])', [[manager, admin]]);
            await db.query('delete from organizations where id=$1', [org]);
        }
        await Promise.all([a.end(), b.end(), db.end()]);
    }
});
