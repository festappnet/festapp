import test from 'node:test';
import assert from 'node:assert/strict';
import {expectedDisposableProject} from './postgres.mjs';

test('custom SQL fixture requires the exact task URL, port and bootstrap identity',()=>{
 const url='postgresql://postgres:postgres@127.0.0.1:59632/postgres';
 const env={FESTAPP_MCP_TEST_DATABASE_URL:url,FESTAPP_LOCAL_DB_PORT:'59632',FESTAPP_LOCAL_DB_PROJECT_ID:'festapp-owned-fixture'};
 assert.equal(expectedDisposableProject(url,env),'festapp-owned-fixture');
 for(const key of Object.keys(env)) assert.throws(()=>expectedDisposableProject(url,{...env,[key]:undefined}));
 assert.throws(()=>expectedDisposableProject(url,{...env,FESTAPP_LOCAL_DB_PORT:'55442'}));
 assert.throws(()=>expectedDisposableProject(url,{...env,FESTAPP_LOCAL_DB_PROJECT_ID:'production'}));
 assert.throws(()=>expectedDisposableProject(url.replace('127.0.0.1','example.com'),env));
});

test('existing forwarded fixture bindings remain mandatory',()=>{
 const url='postgresql://postgres:postgres@127.0.0.1:61032/postgres';
 assert.throws(()=>expectedDisposableProject(url,{}));
 assert.equal(expectedDisposableProject(url,{FESTAPP_AUTHORIZATION_DATABASE_URL:url}),'festapp-mcp-hardening-20261029');
 assert.equal(expectedDisposableProject(url.replace('61032','55432'),{}),'festapp-db-tests-pg15');
});
