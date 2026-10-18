import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import pg from '../../../web_client/node_modules/pg/lib/index.js';

// Explicit disposable dependencies; never fall back to .env.local or live API.
const url = new URL(process.env.DATABASE_URL ?? 'missing:');
assert.equal(url.hostname, '127.0.0.1');
assert.equal(url.port, '56922');
const status = JSON.parse(fs.readFileSync(process.env.DATA_SECURITY_LOCAL_STATUS, 'utf8'));
assert.equal(status.API_URL, 'http://127.0.0.1:56921');
const db = new pg.Client({connectionString: url.href});
await db.connect();
assert.equal((await db.query('select project from festapp_test_support.disposable_environment')).rows[0].project, 'festapp-data-security-e2e-20261018');
const o = (await db.query("select id from public.occasions where link='security-e2e'")).rows[0].id;
const hidden = (await db.query("select id from public.occasions where link='security-hidden-e2e'")).rows[0].id;
const group = (await db.query('select id,place from public.user_group_info where occasion=$1',[o])).rows[0];
await db.end();
async function request(path, token=status.ANON_KEY, body) {
 const response=await fetch(status.API_URL+path,{method:body?'POST':'GET',headers:{apikey:status.ANON_KEY,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
 return {code:response.status,body:await response.json()};
}
async function login(email) {
 const r=await request('/auth/v1/token?grant_type=password',status.ANON_KEY,{email:'1+'+email,password:'test'});
 assert.equal(r.code,200,'local Auth login');return r.body.access_token;
}
const member=await login('member@security.test');
const outsider=await login('outsider@security.test');
test('REST denies anonymous private tables and hides group location',async()=>{
 for(const table of ['user_groups','user_group_info','user_news','email_templates','occasions']) {
  const r=await request('/rest/v1/'+table+'?select=*');assert(r.code===401 || r.code===403,table);
 }
 const news=await request('/rest/v1/news?select=id&occasion=eq.'+hidden);assert.deepEqual(news.body,[]);
 const r=await request('/rest/v1/places?select=id&id=eq.'+group.place);assert.equal(r.code,200);assert.deepEqual(r.body,[]);
});
test('REST scopes member rows and rejects unrelated identities',async()=>{
 const own=await request('/rest/v1/user_group_info?select=id&id=eq.'+group.id,member);assert.equal(own.code,200);assert.equal(own.body.length,1);
 const other=await request('/rest/v1/user_group_info?select=id&id=eq.'+group.id,outsider);assert.deepEqual(other.body,[]);
 const markers=await request('/rest/v1/user_news?select=*&occasion=eq.'+o,outsider);assert.deepEqual(markers.body,[]);
 const hiddenRows=await request('/rest/v1/occasions?select=id&id=eq.'+hidden,outsider);assert.deepEqual(hiddenRows.body,[]);
});
test('RPC keeps member group DTO minimal and hidden context private',async()=>{
 const r=await request('/rest/v1/rpc/get_user_group_info_with_users',member,{p_group_id:Number(group.id)});assert.equal(r.code,200);
 assert.equal(r.body.places.title,'Private group location');
 for(const peer of r.body.user_groups)assert.deepEqual(Object.keys(peer.user_info).sort(),['id','name','surname']);
 const denied=await request('/rest/v1/rpc/get_occasion_for_context_v1',outsider,{p_occasion:Number(hidden)});assert.equal(denied.code,403);
 const own=await request('/rest/v1/rpc/get_occasion_for_context_v1',member,{p_occasion:Number(hidden)});assert.equal(own.code,200);
});
test('GraphQL cannot recover revoked private collections or foreign group rows',async()=>{
 const anon=await request('/graphql/v1',status.ANON_KEY,{query:'{ user_newsCollection { edges { node { news_id } } } }'});
 assert(anon.body.errors?.length || !anon.body.data?.user_newsCollection,'anonymous GraphQL marker access');
 const foreign=await request('/graphql/v1',outsider,{query:`{ user_group_infoCollection(filter: {id: {eq: "${group.id}"}}) { edges { node { id } } } }`});
 assert.equal(foreign.code,200);assert(!foreign.body.errors,JSON.stringify(foreign.body.errors));assert.deepEqual(foreign.body.data.user_group_infoCollection.edges,[]);
});
test('public open form on a hidden occasion remains available',async()=>{
 const r=await request('/rest/v1/rpc/get_form_by_link',status.ANON_KEY,{form_link:'security-public-form'});
 assert.equal(r.code,200);assert(r.body && JSON.stringify(r.body).includes('Hidden public form'));
});
