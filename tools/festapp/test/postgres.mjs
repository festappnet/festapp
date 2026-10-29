import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const {Client}=createRequire(new URL('../../../web_client/package.json',import.meta.url))('pg');

// Explicitly supported disposable projects only. A URL alone is never proof
// that this task owns the data, and no remote/production fallback is accepted.
export async function openDisposableDatabase(connection) {
    const url=new URL(connection);
    assert.equal(url.hostname,'127.0.0.1');
    assert(['55432','61022','61032'].includes(url.port));
    if(['61022','61032'].includes(url.port)) assert.equal(connection,process.env.FESTAPP_AUTHORIZATION_DATABASE_URL);
    const db=new Client({connectionString:connection});await db.connect();
    try {
        const project=(await db.query('select project from festapp_test_support.disposable_environment')).rows[0].project;
        assert.equal(project,url.port==='61032'?'festapp-mcp-hardening-20261029':url.port==='61022'?'festapp-authz-20261020':'festapp-db-tests-pg15');
        if(['61022','61032'].includes(url.port)) {
            assert.equal((await db.query('show cron.launch_active_jobs')).rows[0]['cron.launch_active_jobs'],'off');
            assert.equal((await db.query('select bool_and(paused AND worker_url IS NULL) safe from email_capacity')).rows[0].safe,true);
        }
        return db;
    } catch(error) {await db.end();throw error;}
}
