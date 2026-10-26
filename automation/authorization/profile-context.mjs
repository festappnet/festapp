import {evidenceDirectory} from './evidence.mjs';
// Task-owned nested SQL diagnostic; never connects to a provider or production.
import {connect,fixture} from './benchmark.mjs';
import {readFile,writeFile} from 'node:fs/promises';
const root=new URL('../../',import.meta.url),folder=await evidenceDirectory();
const db=await connect();const messages=[];db.on('notice',event=>messages.push(event.message));
try {
 await db.query('BEGIN');const f=await fixture(db,8,4);
 await db.query("LOAD 'auto_explain'");
 await db.query("SET LOCAL client_min_messages=log; SET LOCAL auto_explain.log_min_duration=0; SET LOCAL auto_explain.log_nested_statements=on; SET LOCAL auto_explain.log_analyze=on; SET LOCAL auto_explain.log_buffers=on; SET LOCAL auto_explain.log_format=json");
 messages.length=0;
 await db.query('SET LOCAL ROLE authenticated');
 await db.query('select public.get_app_config_v218($1::jsonb)',[JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})]);
 await db.query('RESET ROLE');
 await writeFile(new URL('context-nested-profile.json',folder),JSON.stringify({scope:'One cold function-plan call on task-owned synthetic data; instrumentation overhead included',messages},null,2)+'\n');
 console.log(`Captured ${messages.length} nested plan messages.`);
}finally{await db.query('ROLLBACK');await db.end();}
