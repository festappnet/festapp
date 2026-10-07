import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {spawn} from 'node:child_process';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const target=process.env.DATABASE_URL;
const url=new URL(target??'http://missing');
assert.equal(url.hostname,'127.0.0.1','explicit loopback disposable URL required');
assert.equal(url.port,'55452','this task uses its own disposable project');
assert.equal(url.pathname,'/postgres');
const client=new Client({connectionString:target});
try{
 await client.connect();
 const {rows}=await client.query("SELECT project FROM festapp_test_support.disposable_environment WHERE singleton");
 assert.equal(rows[0].project,'festapp-canonical-mutation-pg15','bootstrap identity mismatch; no destructive runner started');
}finally{await client.end();}
const filters=process.argv.slice(2);
assert.ok(filters.length,'explicit targeted filters required');
const runner=new URL('../../web_client/scripts/run_db_tests.js',import.meta.url);
const child=spawn(process.execPath,[runner.pathname,...filters],{stdio:'inherit',env:{...process.env,DATABASE_URL:target}});
child.on('exit',code=>process.exitCode=code??1);
