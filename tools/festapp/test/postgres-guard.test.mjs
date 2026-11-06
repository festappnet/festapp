import test from 'node:test';
import assert from 'node:assert/strict';
import {expectedDisposableProject} from './postgres.mjs';
import {readFile} from 'node:fs/promises';
import {expectedAuthorizationProject,connect as connectAuthorization} from '../../../automation/authorization/benchmark.mjs';

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

test('authorization SQL fixture binds a task clone to its explicit URL, port and marker',()=>{
 const url='postgresql://postgres:postgres@127.0.0.1:59632/task_clone';
 const env={FESTAPP_AUTHORIZATION_DATABASE_URL:url,FESTAPP_LOCAL_DB_PORT:'59632',FESTAPP_LOCAL_DB_PROJECT_ID:'festapp-owned-fixture'};
 assert.equal(expectedAuthorizationProject(url,env),'festapp-owned-fixture');
 for(const key of Object.keys(env))assert.throws(()=>expectedAuthorizationProject(url,{...env,[key]:undefined}));
 assert.throws(()=>expectedAuthorizationProject(url,{...env,FESTAPP_LOCAL_DB_PORT:'55442'}));
 assert.throws(()=>expectedAuthorizationProject(url,{...env,FESTAPP_LOCAL_DB_PROJECT_ID:'production'}));
 assert.throws(()=>expectedAuthorizationProject(url.replace('127.0.0.1','example.com'),env));
 assert.equal(expectedAuthorizationProject(url.replace('59632','61022'),{}),'festapp-authz-20261020');
 assert.equal(expectedAuthorizationProject(url.replace('59632','61032'),{}),'festapp-mcp-hardening-20261029');
});

test('authorization catalog requires the verified session to match the actual task marker',
 {skip:!process.env.FESTAPP_AUTHORIZATION_DATABASE_URL},async t=>{
 const db=await connectAuthorization();t.after(()=>db.end());
 const project=(await db.query("select current_setting('festapp.authorization_fixture_project') value")).rows[0].value;
 const sql=await readFile(new URL('../../../automation/authorization/catalog.sql',import.meta.url),'utf8');
 const end=sql.indexOf('-- Keep deparser');assert(end>0);const guard=sql.slice(0,end);
 await db.query(guard);
 if(!['festapp-authz-20261020','festapp-mcp-hardening-20261029'].includes(project)){
  for(const mismatch of ['', 'festapp-wrong-fixture']){
   await db.query("select set_config('festapp.authorization_fixture_project',$1,false)",[mismatch]);
   await assert.rejects(db.query(guard),/task-owned email-fenced authorization database required/);
  }
  await db.query("select set_config('festapp.authorization_fixture_project',$1,false)",[project]);
  await db.query(guard);
 }
});
