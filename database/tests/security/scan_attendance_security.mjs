// Run only with the disposable security remediation database.
import pg from '../../../web_client/node_modules/pg/lib/index.js';
import {execFileSync} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const ports = JSON.parse(execFileSync('docker', ['inspect', '--format', '{{json .NetworkSettings.Ports}}', 'supabase_db_festapp-security-remediation-20261009'], {encoding:'utf8'}));
assert(ports['5432/tcp']?.some(binding => binding.HostPort === '55562'), 'Run only against the task-owned disposable database on port 55562');
const db=new pg.Client({connectionString:'postgresql://postgres:postgres@127.0.0.1:55562/postgres?sslmode=disable'});
const results=[];
const q=(text,values=[])=>db.query(text,values);
const one=async(text,values=[]) => (await q(text,values)).rows[0];
async function as(role,user,fn){
 await q('SELECT set_config(\'request.jwt.claim.sub\',$1,true),set_config(\'request.jwt.claim.role\',$2,true),set_config(\'request.jwt.claims\',$3,true)',[user||'',role,JSON.stringify({role,...(user?{sub:user}:{})})]);
 await q(`SET LOCAL ROLE ${role}`);
 try {return await fn();} finally {await q('RESET ROLE').catch(()=>{});}
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
 check('scan_null_rejected',(await as('anon',null,()=>rpc('scan_ticket',[symbol,null]))).code,401);
 check('scan_valid_unchanged',(await as('anon',null,()=>rpc('scan_ticket',[symbol,'doublecheck-valid-secret']))).code,200);
 check('scan_wrong_rejected',(await as('anon',null,()=>rpc('scan_ticket',[symbol,'wrong']))).code,401);
 await q("UPDATE eshop.tickets SET state='sent' WHERE id=$1",[ticket]);
 check('mark_null_rejected',(await as('anon',null,()=>rpc('update_ticket_to_used',[ticket,null]))).code,401);
 check('mark_null_no_state_change',(await one('SELECT state FROM eshop.tickets WHERE id=$1',[ticket])).state,'sent');
 check('mark_valid_unchanged',(await as('anon',null,()=>rpc('update_ticket_to_used',[ticket,'doublecheck-valid-secret']))).code,200);
 check('anonymous_signin_rejected',(await as('anon',null,()=>rpc('sign_user_to_event',[event,users.owner]))).code,403);
 check('anonymous_signout_rejected',(await as('anon',null,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,403);
 check('wrong_actor_rejected',(await as('authenticated',users.outsider,()=>rpc('sign_user_to_event',[event,users.fresh]))).code,403);
 check('wrong_actor_no_membership',(await one('SELECT count(*)::int AS n FROM public.occasion_users WHERE occasion=$1 AND "user"=$2',[occ,users.fresh])).n,0);
 check('owner_signin_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.owner]))).code,200);
 check('anonymous_signout_cannot_remove_existing',(await as('anon',null,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,403);
 check('wrong_actor_signout_rejected',(await as('authenticated',users.outsider,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,403);
 check('denied_signout_preserves_attendance',(await one('SELECT count(*)::int AS n FROM public.event_users WHERE event=$1 AND "user"=$2',[event,users.owner])).n,1);
 check('duplicate_signin_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.owner]))).code,103);
 check('owner_signout_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,200);
 check('editor_signin_unchanged',(await as('authenticated',users.editor,()=>rpc('sign_user_to_event',[event,users.owner]))).code,200);
 check('editor_signout_unchanged',(await as('authenticated',users.editor,()=>rpc('sign_user_out_of_event',[event,users.owner]))).code,200);
 await q("UPDATE public.occasions SET features='[{\"code\":\"companions\",\"is_enabled\":true}]' WHERE id=$1",[occ]);
 await q('INSERT INTO public.occasion_users(occasion,"user") VALUES($1,$2)',[occ,users.fresh]);
 await q("INSERT INTO public.user_companions(occasion,\"user\",companion,origin,created_by) VALUES($1,$2,$3,'admin_assigned',$2)",[occ,users.owner,users.fresh]);
 check('companion_signin_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.fresh]))).code,200);
 check('companion_signout_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_out_of_event',[event,users.fresh]))).code,200);
 await q("UPDATE public.occasions SET features='[{\"code\":\"workshops\",\"is_enabled\":false}]' WHERE id=$1",[occ]);
 check('disabled_workshops_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.owner]))).code,108);
 await q("UPDATE public.occasions SET features='[]' WHERE id=$1",[occ]);
 await q('UPDATE public.events SET max_participants=0 WHERE id=$1',[event]);
 check('full_event_unchanged',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.owner]))).code,101);
 await q('UPDATE public.events SET max_participants=10 WHERE id=$1',[event]);

 check('disabled_companions_rejected',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,users.fresh]))).code,403);
 check('open_occasion_self_signup',(await as('authenticated',users.outsider,()=>rpc('sign_user_to_event',[event,users.outsider]))).code,200);
 check('open_occasion_creates_own_membership',(await one('SELECT count(*)::int AS n FROM public.occasion_users WHERE occasion=$1 AND "user"=$2',[occ,users.outsider])).n,1);
 check('null_subject_rejected',(await as('authenticated',users.owner,()=>rpc('sign_user_to_event',[event,null]))).code,403);
 await q("UPDATE eshop.tickets SET state='sent' WHERE id=$1",[ticket]);
 await q('UPDATE public.occasions_hidden SET secret=NULL WHERE id=$1',[hidden]);
 check('missing_secret_scan_rejected',(await as('anon',null,()=>rpc('scan_ticket',[symbol,null]))).code,400);
 check('missing_secret_mark_rejected',(await as('anon',null,()=>rpc('update_ticket_to_used',[ticket,null]))).code,400);
 await q('ROLLBACK');
 console.log(JSON.stringify({scanAttendanceChecks:results.length,allAssertionsPassed:true,rolledBack:true}));
}catch(e){await q('ROLLBACK');console.error(e);console.error('Last passed check:',results.at(-1));process.exitCode=1;}finally{await db.end();}
