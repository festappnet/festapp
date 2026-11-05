#!/usr/bin/env node
// One call is one committed transaction. This runner never invokes maintenance.
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
export async function drain(client,{maxCalls=200,budget=500,maxMilliseconds=10000}={}) {
 const start=performance.now();let processed=0,prepared=0,repairedViews=0,calls=0;
 while(calls<maxCalls && performance.now()-start<maxMilliseconds) {
  const {rows:[row]}=await client.query('SELECT public.project_notification_center($1) processed',[budget]);
  calls++;processed+=row.processed;
  const {rows:[scope]}=await client.query('SELECT public.prepare_notification_center($1) processed',[budget]);
  const {rows:[views]}=await client.query('SELECT public.prepare_notification_center_views($1) processed',[budget]);
  prepared+=scope.processed;repairedViews+=views.processed;
  // No busy spin on locked, backing-off or quarantined work. Durable SQL work
  // survives this exit; the next recovery invocation retries it.
  if(row.processed===0&&scope.processed===0&&views.processed===0)break;
 }
 return {processed,prepared,repairedViews,calls,elapsedMs:Math.round(performance.now()-start)};
}
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
 const connectionString=process.env.NOTIFICATION_CENTER_DATABASE_URL;
 if(!connectionString)throw Error('NOTIFICATION_CENTER_DATABASE_URL is required');
 assertLocalDatabaseUrl(connectionString);
 const client=new Client({connectionString,application_name:'notification-center-drain'});
 await client.connect();
 try{
  await assertDisposableDatabase(client);
  await client.query("SET statement_timeout='2s'; SET lock_timeout='100ms'");
  console.log(JSON.stringify(await drain(client)));
 }finally{await client.end();}
}
