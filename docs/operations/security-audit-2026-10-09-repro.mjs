// Diagnostic snapshot for the 2026-10-09 audit, not a passing security regression gate.
// It records the vulnerable baseline, then tries minimal corrections in a rolled-back transaction.
import pg from '../../web_client/node_modules/pg/lib/index.js';
import {execFileSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const repositoryRoot = new URL('../../', import.meta.url);
const ports = JSON.parse(execFileSync('docker', ['inspect', '--format', '{{json .NetworkSettings.Ports}}', 'supabase_db_festapp-security-doublecheck-20261009'], {encoding:'utf8'}));
assert(ports['5432/tcp']?.some(binding => binding.HostPort === '55552'), 'Run only against the task-owned disposable database on port 55552');
const db=new pg.Client({connectionString:'postgresql://postgres:postgres@127.0.0.1:55552/postgres?sslmode=disable'});
const results=[];
const q=(text,values=[])=>db.query(text,values);
const one=async(text,values=[]) => (await q(text,values)).rows[0];
async function as(role,user,fn){
 await q('SELECT set_config(\'request.jwt.claim.sub\',$1,true),set_config(\'request.jwt.claim.role\',$2,true),set_config(\'request.jwt.claims\',$3,true)',[user||'',role,JSON.stringify({role,...(user?{sub:user}:{})})]);
 await q(`SET LOCAL ROLE ${role}`);
 try {return await fn();} finally {await q('RESET ROLE').catch(()=>{});}
}
async function blocked(name,role,user,query,params,expected){
 await q('SAVEPOINT expected_block');
 let code;try{await as(role,user,()=>q(query,params));}catch(e){code=e.code;}
 await q('ROLLBACK TO SAVEPOINT expected_block');await q('RELEASE SAVEPOINT expected_block');check(name,code,expected);
}
function check(name,value,expected){assert.deepEqual(value,expected,name);results.push({name,value});}
await db.connect();
try{
 await q('BEGIN');
 const org=(await one('INSERT INTO public.organizations(title) VALUES($1) RETURNING id',['Security doublecheck'])).id;
 const unit=(await one('INSERT INTO public.units(title,organization) VALUES($1,$2) RETURNING id',['Fixture unit',org])).id;
 const hidden=(await one('INSERT INTO public.occasions_hidden(secret) VALUES($1) RETURNING id',['doublecheck-valid-secret'])).id;
 const occ=(await one("INSERT INTO public.occasions(title,organization,unit,occasion_hidden,link,is_open,features,start_time,end_time) VALUES($1,$2,$3,$4,$5,true,'[]',now()+interval '1 day',now()+interval '3 days') RETURNING id",['Fixture occasion',org,unit,hidden,'audit-'+randomUUID()])).id;
 const users={owner:randomUUID(),editor:randomUUID(),outsider:randomUUID(),fresh:randomUUID()};
 for(const [name,id] of Object.entries(users)){
  await q("INSERT INTO auth.users(id,instance_id,email,aud,role,created_at,updated_at,last_sign_in_at) VALUES($1,'00000000-0000-0000-0000-000000000000',$2,'authenticated','authenticated',now(),now(),now())",[id,`audit-${name}-${id}@test.local`]);
  await q('INSERT INTO public.user_info(id,name,organization,email_readonly) VALUES($1,$2,$3,$4)',[id,name,org,`audit-${name}-${id}@test.local`]);
 }
 await q('INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_order) VALUES($1,$2,false,false),($1,$3,true,true)',[occ,users.owner,users.editor]);
 const event=(await one("INSERT INTO public.events(title,occasion,start_time,end_time,max_participants) VALUES('Fixture workshop',$1,now()+interval '1 day',now()+interval '2 days',10) RETURNING id",[occ])).id;
 const ticket=(await one("INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES($1,'sent',$2) RETURNING id",[occ,'AUDIT-'+randomUUID()])).id;
 const symbol=(await one('SELECT ticket_symbol FROM eshop.tickets WHERE id=$1',[ticket])).ticket_symbol;
 const order=(await one("INSERT INTO eshop.orders(occasion,state,data,order_symbol,order_sequence) VALUES($1,'paid',$2,$3,1) RETURNING id",[occ,JSON.stringify({email:'fixture-only@test.local'}),(await one('SELECT public.generate_order_symbol() AS symbol')).symbol])).id;
 await q('INSERT INTO eshop.order_product_ticket("order",ticket) VALUES($1,$2)',[order,ticket]);
 await q('UPDATE public.occasion_users SET ticket=$1 WHERE occasion=$2 AND "user"=$3',[ticket,occ,users.owner]);
 async function rpc(name,args){return (await one(`SELECT public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) AS result`,args)).result;}
 check('scan_wrong_code_rejected',(await as('anon',null,()=>rpc('scan_ticket',[symbol,'wrong']))).code,401);
 check('scan_valid_code_works',(await as('anon',null,()=>rpc('scan_ticket',[symbol,'doublecheck-valid-secret']))).code,200);
 const nullScan=await as('anon',null,()=>rpc('scan_ticket',[symbol,null]));
 check('VULNERABILITY_scan_null_exposes_order',nullScan.code,200);
 check('VULNERABILITY_scan_null_has_order',String(nullScan.order.id),String(order));
 check('mark_wrong_code_rejected',(await as('anon',null,()=>rpc('update_ticket_to_used',[ticket,'wrong']))).code,401);
 check('VULNERABILITY_mark_null_accepted',(await as('anon',null,()=>rpc('update_ticket_to_used',[ticket,null]))).code,200);
 check('VULNERABILITY_mark_null_changes_state',(await one('SELECT state FROM eshop.tickets WHERE id=$1',[ticket])).state,'used');
 await q("UPDATE eshop.tickets SET state='sent' WHERE id=$1",[ticket]);
 check('mark_valid_code_works',(await as('anon',null,()=>rpc('update_ticket_to_used',[ticket,'doublecheck-valid-secret']))).code,200);
 check('VULNERABILITY_anonymous_signin',(await as('anon',null,()=>rpc('sign_user_to_event',[event,users.owner]))).code,200);
 check('VULNERABILITY_anonymous_signout',(await as('anon',null,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,200);
 check('owner_signin_works',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.owner]))).code,200);
 check('owner_signout_works',(await as('authenticated',users.owner,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,200);
 check('editor_signin_works',(await as('authenticated',users.editor,()=>rpc('sign_user_to_event',[event,users.owner]))).code,200);
 check('editor_signout_works',(await as('authenticated',users.editor,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,200);
 check('VULNERABILITY_anon_unit_membership',(await as('anon',null,()=>rpc('add_user_to_unit',[unit,users.outsider]))).code,200);
 check('VULNERABILITY_anon_unit_membership_persisted',(await one('SELECT count(*)::int AS n FROM public.unit_users WHERE unit=$1 AND "user"=$2',[unit,users.outsider])).n,1);
 const bank=(await one("INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Fixture bank','FIO',ARRAY['CZK']) RETURNING id")).id;
 await q('INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES($1,$2,true)',[bank,users.owner]);
 await q('SAVEPOINT bank_single');
 try {await as('anon',null,()=>q('SELECT * FROM public.get_bank_account_users($1::bigint)',[bank]));throw new Error('Expected ambiguous one-argument overload');}
 catch(e){await q('ROLLBACK TO SAVEPOINT bank_single');check('single_argument_bank_overload_is_ambiguous',e.code,'42725');}
 await q('RELEASE SAVEPOINT bank_single');
 check('VULNERABILITY_anon_bank_users_overload',(await as('anon',null,()=>q('SELECT * FROM public.get_bank_account_users($1::bigint,$2::bigint)',[bank,unit]))).rows.length,1);
 check('VULNERABILITY_anon_email_lookup',(await as('anon',null,()=>q('SELECT * FROM public.get_user_id_by_email($1)',[`audit-owner-${users.owner}@test.local`]))).rows[0].id,users.owner);
 check('VULNERABILITY_anon_last_signin',!!(await as('anon',null,()=>rpc('get_last_sign_in_at',[users.owner]))),true);
 await q('INSERT INTO public.event_users(event,"user") VALUES($1,$2)',[event,users.owner]);
 check('VULNERABILITY_anon_participation_read',(await as('anon',null,()=>q('SELECT event,"user" FROM public.event_users WHERE event=$1',[event]))).rows.length,1);
 await q('DELETE FROM public.event_users WHERE event=$1',[event]);
 check('FALSE_POSITIVE_direct_attendance_write',(await one("SELECT has_table_privilege('authenticated','public.event_users','INSERT') AS allowed")).allowed,false);
 check('FALSE_POSITIVE_profile_identity_write',(await one("SELECT has_column_privilege('authenticated','public.user_info','organization','UPDATE') OR has_column_privilege('authenticated','public.user_info','email_readonly','UPDATE') OR has_column_privilege('authenticated','public.user_info','email_delivery','UPDATE') AS allowed")).allowed,false);
 await blocked('direct_attendance_insert_is_denied','authenticated',users.owner,'INSERT INTO public.event_users(event,"user") VALUES($1,$2)',[event,users.owner],'42501');
 await blocked('direct_profile_identity_update_is_denied','authenticated',users.owner,'UPDATE public.user_info SET organization=$1 WHERE id=$2',[org,users.owner],'42501');
 await blocked('occasion_templates_are_transitively_guarded','anon',null,"SELECT public.get_entity_email_templates('occasion',$1)",[occ],'P0001');
 const unitTemplates=await as('anon',null,()=>rpc('get_entity_email_templates',['unit',unit]));
 check('VULNERABILITY_unit_templates_metadata_unguarded',String(unitTemplates.unit.id),String(unit));
 await blocked('live_legacy_late_membership_call_is_guarded','authenticated',users.outsider,'SELECT public.sign_user_to_event($1,$2)',[event,users.fresh],'42501');
 check('live_legacy_failed_call_leaves_no_membership',(await one('SELECT count(*)::int AS n FROM public.occasion_users WHERE occasion=$1 AND "user"=$2',[occ,users.fresh])).n,0);
 // Try the minimal SQL corrections only inside this rolled-back fixture transaction.
 for(const signature of ['scan_ticket(text,text)','update_ticket_to_used(bigint,text)']){
  const {def}=await one('SELECT pg_get_functiondef($1::regprocedure) AS def',[signature]);
  const candidate=def.replace('scanned_code != expected_scan_code','scanned_code IS DISTINCT FROM expected_scan_code').replace('scan_code != expected_scan_code','scan_code IS DISTINCT FROM expected_scan_code');
  assert.notEqual(candidate,def);
  await q(candidate);
 }
 for(const signature of ['sign_user_to_event(bigint,uuid)','sign_user_out_of_event(bigint,uuid)']){
  const {def}=await one('SELECT pg_get_functiondef($1::regprocedure) AS def',[signature]);
  const lines=def.split('\n');const first=lines.findIndex(s=>s.trim()==='IF auth.uid() <> usr THEN');let end=first;let depth=0;
  assert(first>=0);
  for(;end<lines.length;end++){if(/^\s*IF\s/.test(lines[end]))depth++;if(/^\s*END IF;/.test(lines[end]))depth--;if(depth===0)break;}
  const guard=lines.splice(first,end-first+1).join('\n').replace('auth.uid() <> usr','auth.uid() IS DISTINCT FROM usr');
  const begin=lines.findIndex(s=>s.trim().toLowerCase()==='begin');assert(begin>=0);
  lines.splice(begin+1,0,"  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('code',403); END IF;",guard);
  await q(lines.join('\n'));
 }
 check('candidate_scan_null_rejected',(await as('anon',null,()=>rpc('scan_ticket',[symbol,null]))).code,401);
 check('candidate_scan_valid_unchanged',(await as('anon',null,()=>rpc('scan_ticket',[symbol,'doublecheck-valid-secret']))).code,200);
 check('candidate_scan_wrong_rejected',(await as('anon',null,()=>rpc('scan_ticket',[symbol,'wrong']))).code,401);
 await q("UPDATE eshop.tickets SET state='sent' WHERE id=$1",[ticket]);
 check('candidate_mark_null_rejected',(await as('anon',null,()=>rpc('update_ticket_to_used',[ticket,null]))).code,401);
 check('candidate_mark_null_no_state_change',(await one('SELECT state FROM eshop.tickets WHERE id=$1',[ticket])).state,'sent');
 check('candidate_mark_valid_unchanged',(await as('anon',null,()=>rpc('update_ticket_to_used',[ticket,'doublecheck-valid-secret']))).code,200);
 check('candidate_anonymous_signin_rejected',(await as('anon',null,()=>rpc('sign_user_to_event',[event,users.owner]))).code,403);
 check('candidate_anonymous_signout_rejected',(await as('anon',null,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,403);
 check('candidate_wrong_actor_rejected',(await as('authenticated',users.outsider,()=>rpc('sign_user_to_event',[event,users.fresh]))).code,403);
 check('candidate_wrong_actor_no_membership',(await one('SELECT count(*)::int AS n FROM public.occasion_users WHERE occasion=$1 AND "user"=$2',[occ,users.fresh])).n,0);
 check('candidate_owner_signin_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.owner]))).code,200);
 check('candidate_duplicate_signin_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.owner]))).code,103);
 check('candidate_owner_signout_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,200);
 check('candidate_editor_signin_unchanged',(await as('authenticated',users.editor,()=>rpc('sign_user_to_event',[event,users.owner]))).code,200);
 check('candidate_editor_signout_unchanged',(await as('authenticated',users.editor,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,200);
 await q("UPDATE public.occasions SET features='[{\"code\":\"companions\",\"is_enabled\":true}]' WHERE id=$1",[occ]);
 await q('INSERT INTO public.occasion_users(occasion,"user") VALUES($1,$2)',[occ,users.fresh]);
 await q("INSERT INTO public.user_companions(occasion,\"user\",companion,origin,created_by) VALUES($1,$2,$3,'admin_assigned',$2)",[occ,users.owner,users.fresh]);
 check('candidate_companion_signin_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.fresh]))).code,200);
 check('candidate_companion_signout_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_out_of_event',[event,users.fresh]))).code,200);
 await q("UPDATE public.occasions SET features='[{\"code\":\"workshops\",\"is_enabled\":false}]' WHERE id=$1",[occ]);
 check('candidate_disabled_workshops_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.owner]))).code,108);
 await q("UPDATE public.occasions SET features='[]' WHERE id=$1",[occ]);
 await q('UPDATE public.events SET max_participants=0 WHERE id=$1',[event]);
 check('candidate_full_event_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.owner]))).code,101);
 await q('UPDATE public.events SET max_participants=10 WHERE id=$1',[event]);
 await q(readFileSync(new URL('database/tests/helpers/assertions.sql',repositoryRoot),'utf8'));
 for(const test of ['full_deposit_flow','on_site_surcharge_flow','overpayment_flow']){
  await q(readFileSync(new URL('database/tests/eshop/integration/'+test+'_test.sql',repositoryRoot),'utf8'));
  check('existing_integration_'+test,true,true);
 }
 await q('ROLLBACK');
 writeFileSync('/tmp/festapp-security-doublecheck-db-results.json',JSON.stringify(results,null,2)+'\n');
 console.log(JSON.stringify({checks:results.length,confirmedVulnerableBehaviors:results.filter(x=>x.name.startsWith('VULNERABILITY')).length,allAssertionsPassed:true,fixtureAndCandidateChangesRolledBack:true}));
}catch(e){await q('ROLLBACK');console.error(e.message);console.error('Last passed check:',results.at(-1));process.exitCode=1;}finally{await db.end();}
