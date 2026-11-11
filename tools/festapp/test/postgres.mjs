import {readdir} from '../../../automation/lib/migration_inputs_async.mjs';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const {Client}=createRequire(new URL('../../../web_client/package.json',import.meta.url))('pg');

const migrationVersion=(await readdir(new URL('../../../supabase/migrations/',import.meta.url)))
    .filter(name=>/^\d{14}_.+\.sql$/.test(name)).sort().at(-1).slice(0,14);

/** Test data runs against the real migrated schema; fixtures never install application SQL. */
export async function assertSchema(db) {
    assert.equal((await db.query('select exists(select 1 from supabase_migrations.schema_migrations where version=$1) ready',[migrationVersion])).rows[0].ready,
        true, 'Migrate the marked disposable database through '+migrationVersion+' before running the complete suite');
}

// Explicitly supported disposable projects only. A URL alone is never proof
// that this task owns the data, and no remote/production fallback is accepted.
export function expectedDisposableProject(connection, env=process.env) {
    const url=new URL(connection);
    assert.equal(url.hostname,'127.0.0.1');
    if(['55432','61022','61032'].includes(url.port)) {
        if(url.port!=='55432') assert.equal(connection,env.FESTAPP_AUTHORIZATION_DATABASE_URL);
        return url.port==='61032'?'festapp-mcp-hardening-20261029':url.port==='61022'?'festapp-authz-20261020':'festapp-db-tests-pg15';
    }
    // A task-owned bootstrap must bind both its URL and exact database marker.
    assert.equal(connection,env.FESTAPP_MCP_TEST_DATABASE_URL);
    assert.equal(url.port,env.FESTAPP_LOCAL_DB_PORT);
    assert.match(env.FESTAPP_LOCAL_DB_PROJECT_ID??'',/^festapp-[a-z0-9-]+$/);
    return env.FESTAPP_LOCAL_DB_PROJECT_ID;
}

export async function openDisposableDatabase(connection) {
    const expectedProject=expectedDisposableProject(connection);
    const url=new URL(connection);
    const db=new Client({connectionString:connection});await db.connect();
    try {
        const project=(await db.query('select project from festapp_test_support.disposable_environment')).rows[0].project;
        assert.equal(project,expectedProject);
        if(url.port!=='55432') {
            assert.equal((await db.query('show cron.launch_active_jobs')).rows[0]['cron.launch_active_jobs'],'off');
            assert.equal((await db.query('select bool_and(paused AND worker_url IS NULL) safe from email_capacity')).rows[0].safe,true);
        }
        await assertSchema(db);
        return db;
    } catch(error) {await db.end();throw error;}
}
