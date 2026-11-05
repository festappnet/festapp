import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {setup} from './form-fixtures.mjs';

test('hidden members stay out of editor and notification projections and survive a visible-only group save',async t=>{
 const {db,f}=await setup(t);
 const hidden=randomUUID(),email='hidden-'+hidden+'@example.invalid';
 await db.query('insert into auth.users(id,email) values($1,$2)',[hidden,email]);
 await db.query("insert into user_info(id,organization,email_readonly,name) values($1,$2,$3,'Hidden member')",[hidden,f.org,email]);
 await db.query('insert into organization_users(organization,"user",is_admin,is_hidden) values($1,$2,true,true)',[f.org,hidden]);
 await db.query('insert into occasion_users(occasion,"user") values($1,$2)',[f.occasion,hidden]);
 const group=Number((await db.query("insert into user_group_info(occasion,title) values($1,'Visibility group') returning id",[f.occasion])).rows[0].id);
 await db.query('insert into user_groups("group","user",is_admin) values($1,$2,true),($1,$3,false)',[group,f.actor,hidden]);
 const visible=(await db.query('select organization_member_visible_internal($1,$2) member,occasion_member_visible_internal($3,$2) occasion,notification_center_subject_visible_internal($1,\'occasion_joined\',$4) notification',[f.org,hidden,f.occasion,{userId:hidden}])).rows[0];
 assert.deepEqual(visible,{member:false,occasion:false,notification:false});
 for(const role of ['anon','authenticated','service_role'])for(const signature of ['organization_member_visible_internal(bigint,uuid)','occasion_member_visible_internal(bigint,uuid)','notification_center_subject_visible_internal(bigint,text,jsonb)'])
  assert.equal((await db.query('select has_function_privilege($1,$2,\'execute\') allowed',[role,'public.'+signature])).rows[0].allowed,false);
 await db.query('SET LOCAL ROLE authenticated');
 const before=(await db.query('select get_user_group_editor_bundle_v1($1,$2) value',[f.occasion,group])).rows[0].value;
 assert.deepEqual(before.participants.map(p=>p.userId),[f.actor]);
 const result=(await db.query('select save_user_group_client_sync_v1($1,$2,$3,$4) value',[f.occasion,randomUUID(),before.aggregate_version,{id:group,title:'Renamed visible group',description:null,type:null,placeId:null,participants:[{user_id:f.actor,is_admin:true}]}])).rows[0].value;
 assert.equal(result.code,200,JSON.stringify(result));
 const after=(await db.query('select get_user_group_editor_bundle_v1($1,$2) value',[f.occasion,group])).rows[0].value;
 assert.deepEqual(after.participants.map(p=>p.userId),[f.actor]);
 await db.query('RESET ROLE');
 assert.equal(Number((await db.query('select count(*) n from user_groups where "group"=$1 and "user"=$2',[group,hidden])).rows[0].n),1);
});
