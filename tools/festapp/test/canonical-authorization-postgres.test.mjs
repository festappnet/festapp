import {readFile} from 'node:fs/promises';
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { connect, fixture } from '../../../automation/authorization/benchmark.mjs';
const options={skip:!process.env.FESTAPP_AUTHORIZATION_DATABASE_URL};
async function within(t,body) {
    const db=await connect(); await db.query('BEGIN');
    try {const f=await fixture(db,1); await body(db,f);} finally {await db.query('ROLLBACK');await db.end();}
}
async function identity(db,f,role='authenticated') {
    await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)",[f.actor,role]);
    await db.query('SET LOCAL ROLE '+role);
}
async function forbidden(db,sql,args) {
    await db.query('SAVEPOINT denied');
    await assert.rejects(db.query(sql,args),e=>e.code==='42501');
    await db.query('ROLLBACK TO SAVEPOINT denied');await db.query('RELEASE SAVEPOINT denied');
}

test('canonical truth table preserves server operation rights across 2048 role combinations',options,async t=>within(t,async(db,f)=>{
    await db.query('insert into organization_users(organization,"user",is_admin) values($1,$2,false)',[f.org,f.actor]);
    await db.query("update occasions set features='[{\"code\":\"reception\",\"is_enabled\":true}]' where id=$1",[f.occasion]);
    await db.query(await readFile(new URL('../../../database/tests/helpers/authorization_context_reference.sql',import.meta.url),'utf8'));
    for(let bits=0;bits<2048;bits++) {
        const b=Array.from({length:11},(_,i)=>Boolean(bits&(1<<i)));
        await db.query('RESET ROLE');
        await db.query('update occasion_users set is_editor=$1,is_editor_view=$2,is_editor_order=$3,is_editor_order_view=$4,is_manager=$5,is_receptionist=$8,is_approver=$9 where occasion=$6 and "user"=$7',[...b.slice(0,5),f.occasion,f.actor,b[9],b[10]]);
        await db.query('update unit_users set is_editor=$1,is_manager=$2,is_editor_view=$5 where unit=$3 and "user"=$4',[b[5],b[6],f.unit,f.actor,b[8]]);
        await db.query('update organization_users set is_admin=$1 where organization=$2 and "user"=$3',[b[7],f.org,f.actor]);
        await identity(db,f);
        const r=(await db.query(`select can_read_orders($1) read,can_write_orders($1) write,
          can_edit_occasion($1) edit,can_edit_ticket_layout($1) layout,
          can_read_occasion_client_commits($1) occasion_audit,can_read_unit_client_commits($2) unit_audit,can_read_organization_client_commits($3) organization_audit,
          can_read_unit_app_landing($2) landing_read,can_manage_unit_app_landing($2) landing_write,
          can_read_unit_abuse_policy($2) abuse_read,can_read_unit_legal_profile($2) legal_read,
          can_write_unit_icons($2) icons_write,can_copy_occasion_target($2) copy_occasion_target,can_read_client_activity($1) activity_log,
          can_materialize_public_occasion($1) publish,can_migrate_reviewed_legacy_blueprint($1) reviewed,
          can_create_occasion($2) AS "create",can_read_occasion_editor_data($1) occasion_editor_read,
          can_upload_blueprint_background($1,NULL) background_occasion,can_upload_blueprint_background(NULL,$2) background_unit,
          can_read_information_editor_bundle($1) information,can_read_map_editor_bundle($1) map,
          can_delete_orders($1) AS "delete",
          can_author_forms($1) forms_author,can_read_form_catalog($1) forms_catalog,
          can_copy_form_source($1) copy_source,can_copy_form_target($1) copy_target,
          can_write_news($1) news,can_write_information($1) information_write,
          can_read_legacy_unit_occasion_catalog($2) legacy_unit_occasion_catalog,can_read_unit_occasion_catalog($2) unit_occasion_catalog,can_read_occasion_directory($1) directory_read,can_read_unit_information($2) unit_information_read,can_write_unit_information($2) unit_information_write,
          get_can_use_reception($1) reception,
          can_write_schedule($1) schedule,can_read_schedule_editor($1) schedule_read,
          can_read_schedule_participants($1) schedule_participants,can_read_schedule_feedback($1) feedback,
          can_write_speakers($1) speakers,can_read_speakers_editor($1) speakers_read,
          can_write_service_items($1) services,can_manage_occasion_participants($1) participants,get_can_manage_occasion_users($1) users_manage,
          can_read_participant_contacts($1) contacts,can_import_group_assignments($1) group_import,
          can_write_blueprints($1) blueprints,can_copy_inventory_target($1) inventory,
          can_write_activity_plan($1) activities,can_read_activity_editor($1) activities_read,can_send_custom_email($1) custom_mail`,[f.occasion,f.unit,f.org])).rows[0];
        assert.deepEqual(r,{read:b[3],write:b[2],edit:b[5],layout:b[5],
          occasion_audit:b[4]||b[7],unit_audit:b[6],organization_audit:b[7],
          landing_read:b[7]||b[8]||b[5]||b[6],landing_write:b[7],abuse_read:b[5]||b[6],legal_read:b[6]||b[7],icons_write:b[5],copy_occasion_target:b[6],activity_log:b[4]||b[6]||b[7],
          publish:b[0]||b[5]||b[7],reviewed:b[0]||b[4],
          create:b[5]||b[6],occasion_editor_read:b[1]||b[4]||b[7],background_occasion:b[0]||b[4],background_unit:b[5]||b[6],information:b[1],map:b[0]||b[1],delete:b[5]||b[6]||b[7],
          forms_author:b[0]||b[5],forms_catalog:b[1]||b[3],copy_source:b[1]||b[8],copy_target:b[0],
          news:b[0],information_write:b[0],directory_read:b[1]||b[3],unit_occasion_catalog:b.slice(0,7).some(Boolean)||b[8],legacy_unit_occasion_catalog:b[5]||b[6]||b[8],unit_information_read:b[8],unit_information_write:b[5],
          reception:b[9]||b[4]||b[7],schedule:b[0],schedule_read:b[1],schedule_participants:b[0]||b[1]||b[7],feedback:b[1]||b[7],
          speakers:b[0],speakers_read:b[1],services:b[4],participants:b[4]||b[7],users_manage:b[4]||b[7]||b[5],contacts:b[0]||b[4]||b[10],
          group_import:b[0]||b[4]||b[5]||b[7],blueprints:b[0]||b[4],inventory:b[2]||b[6],activities:b[0],activities_read:b[0]||b[1],custom_mail:b[0]||b[2]},`roles ${bits}`);
        const c=(await db.query('select get_app_config_v218($1::jsonb) c',
          [JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})])).rows[0].c;
        assert.equal(c.code,200);
        assert.equal(c.capabilities['occasions.editor.read'],r.occasion_editor_read);
        assert.equal(c.capabilities['organization.settings.write'],b[7]);
        assert.equal(c.capabilities['blueprints.write'],r.background_occasion);
        const original=(await db.query('select authorization_context_before_for_test($1::jsonb) c',
          [JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})])).rows[0].c;
        const {capabilities,bank_capabilities,...currentEnvelope}=c;
        // The approved Stripe checkout migration adds this feature projection;
        // keep the historical reference exact and assert the addition separately.
        const {stripe_preview_enabled,...unitEnvelope}=currentEnvelope.unit;
        assert.equal(stripe_preview_enabled,false,`fixture Stripe feature default, roles ${bits}`);
        assert.deepEqual({...currentEnvelope,unit:unitEnvelope},original,`unchanged context envelope, roles ${bits}`);
        for(const [key,expected] of Object.entries({
          'orders.read':r.read,'orders.write':r.write,'orders.delete':r.delete,
          'ticket_layouts.read':r.layout,'ticket_layouts.write':r.layout,
          'occasions.create':r.create,'occasions.write':r.edit,
          'information.editor.read':r.information,'map.editor.read':r.map,
          'forms.create':r.forms_author,'forms.delete':r.forms_author,'forms.catalog.read':r.forms_catalog,
          'forms.copy.source':r.copy_source,'forms.copy.target':r.copy_target,
          'news.write':r.news,'information.write':r.information_write,
          'unit_information.read':r.unit_information_read,'unit_information.write':r.unit_information_write,
          'navigation.schedule_entry_check':b[10],
          'scanner.settings.write':b[0]||b[2],'reception.use':r.reception,
          'schedule.write':r.schedule,'schedule.editor.read':r.schedule_read,
          'schedule.participants.read':r.schedule_participants,'schedule.feedback.read':r.feedback,
          'speakers.write':r.speakers,'speakers.editor.read':r.speakers_read,'services.write':r.services,
          'participants.write':r.participants,'participants.contacts.read':r.contacts,'groups.assignments.write':r.group_import,
          'blueprints.write':r.blueprints,'inventory.copy.target':r.inventory,'activities.write':r.activities,'activities.editor.read':r.activities_read,'emails.custom.send':r.custom_mail,
        })) assert.equal(c.capabilities[key],expected,`projection ${key}, roles ${bits}`);
    }
}));

test('projection travels with context; demo, anon, missing and foreign resources fail closed',options,async t=>within(t,async(db,f)=>{
    await identity(db,f);
    const context=(await db.query('select get_app_config_v218($1::jsonb) c',[JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})])).rows[0].c;
    assert.equal(context.code,200);assert.equal(context.capabilities['orders.write'],true);
    assert.equal(context.capabilities['ticket_layouts.read'],true);
    await forbidden(db,'select get_context_capabilities_v1($1,NULL,NULL,false,false,false,false,false,false,false)',[f.occasion]);
    const fenced=(await db.query(`select bool_and(NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
       AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
       AND NOT has_function_privilege('service_role',p.oid,'EXECUTE')) safe
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='public' and (p.proname IN ('order_read_rule','order_write_rule','occasion_create_rule','occasion_edit_rule','order_delete_rule','ticket_layout_rule','map_editor_read_rule','occasion_users_write_rule','unit_users_read_rule','participant_manage_rule','administration_navigation_rule','form_authoring_rule','form_catalog_read_rule','form_copy_source_rule','scanner_settings_rule','reception_enabled','reception_use_rule','schedule_participants_read_rule','schedule_feedback_read_rule','participant_contacts_read_rule','group_assignments_write_rule','blueprint_write_rule','inventory_copy_target_rule')
         OR p.proname IN ('active_membership','readable_membership','insert_form_for_occasion_internal_v1','create_initial_occasion_form_internal_v1','demo_unit_ids_internal','bank_context_capabilities'))`)).rows[0].safe;
    assert.equal(fenced,true,'fact-based policies and private constructors cannot be supplied by an external caller');
    assert.equal((await db.query("select to_regprocedure('public.delete_order(bigint)') absent")).rows[0].absent,null,'unversioned physical order deletion bypass is retired');
    for (const signature of ["get_bank_sync_connections_for_unit(bigint)", "update_user(uuid,bigint,jsonb)", "delete_form_ws_obsolete_v1(bigint)", "storno_ticket(bigint)", "storno_ticket_221(bigint)", "copy_product_type_with_products(bigint)", "duplicate_form_ws(bigint)", "update_ticket_products_ws(bigint,bigint[])", "update_order_data_to_sent(bigint)"]) {
        assert.equal((await db.query('select to_regprocedure($1) absent',['public.'+signature])).rows[0].absent,null,signature+' retired');
    }
    assert.equal((await db.query("select count(*)::integer n from pg_proc where pronamespace='public'::regnamespace AND proname IN ('set_claim','delete_claim','get_claims','get_claim','get_my_claim','get_my_claims','is_claims_admin')")).rows[0].n,0,'obsolete token-claim permission engine is absent');
    const pure=(await db.query(`select bool_and(p.provolatile='i' AND NOT p.prosecdef
       AND p.prorettype='boolean'::regtype AND p.prosrc !~* '(^|[^a-z_])(FROM|JOIN|EXECUTE|INSERT|UPDATE|DELETE)([^a-z_]|$)') safe
       FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
       AND p.proname IN ('active_membership','readable_membership','order_read_rule','order_write_rule','occasion_create_rule','occasion_edit_rule','order_delete_rule','ticket_layout_rule','map_editor_read_rule','occasion_users_write_rule','unit_users_read_rule','participant_manage_rule','administration_navigation_rule','form_authoring_rule','form_catalog_read_rule','form_copy_source_rule','scanner_settings_rule','reception_enabled','reception_use_rule','schedule_participants_read_rule','schedule_feedback_read_rule','participant_contacts_read_rule','group_assignments_write_rule','blueprint_write_rule','inventory_copy_target_rule')`)).rows[0].safe;
    assert.equal(pure,true,'inlinable rules are immutable invoker-only boolean expressions');
    await forbidden(db,'select get_delegated_ticket_layout_for_authoring_v1($1,$2,$3)',[f.occasion,f.org+999999,f.unit]);
    await forbidden(db,'select get_delegated_ticket_layout_for_authoring_v1($1,$2,$3)',[f.occasion,f.org,f.unit+999999]);
    await forbidden(db,'select get_delegated_ticket_layout_for_authoring_v1($1,$2,$3)',[999999999,f.org,f.unit]);
    assert.equal((await db.query('select can_write_orders($1) allowed',[999999999])).rows[0].allowed,false);

    await db.query('RESET ROLE');
    const foreign=Number((await db.query("insert into organizations(title,data) values('Foreign authorization tenant','{}') returning id")).rows[0].id);
    const foreignUnit=Number((await db.query("insert into units(title,organization) values('Foreign organizer',$1) returning id",[foreign])).rows[0].id);
    const foreignOccasion=Number((await db.query("insert into occasions(title,link,organization,unit,start_time,end_time) values('Foreign default',gen_random_uuid()::text,$1,$2,now(),now()+interval '1 day') returning id",[foreign,foreignUnit])).rows[0].id);
    await db.query("update organizations set data=jsonb_build_object('DEFAULT_OCCASION',$1::bigint) where id=$2",[foreignOccasion,f.org]);
    await identity(db,f);
    const invalidDefault=(await db.query('select get_app_config_v218($1::jsonb) c',[JSON.stringify({organization:f.org,platform:{platform:'web'}})])).rows[0].c;
    assert.equal(invalidDefault.code,404,'a stored default cannot bind a foreign tenant resource');
    const demo=(await db.query('RESET ROLE; select occasion,organization from demo_occasions order by occasion limit 1'))[1].rows[0];
    assert(demo,'versioned demo seed is present');
    await db.query('update demo_occasions set is_listed=true where occasion=$1',[demo.occasion]);
    await db.query('update user_info set organization=$1 where id=$2',[demo.organization,f.actor]);
    await identity(db,f);
    assert.deepEqual((await db.query('select can_read_orders($1) read,can_write_orders($1) write,can_edit_ticket_layout($1) layout',[demo.occasion])).rows[0],{read:true,write:false,layout:false});
    assert.equal((await db.query('select can_read_map_editor_bundle($1) = (get_is_editor_view_on_occasion($1) OR get_is_editor_on_occasion($1)) same',[demo.occasion])).rows[0].same,true);
    await db.query('RESET ROLE');await db.query("select set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','anon',true)");
    await db.query('SET LOCAL ROLE anon');
    assert.deepEqual((await db.query('select can_read_orders($1) read,can_write_orders($1) write',[f.occasion])).rows[0],{read:false,write:false});
    await db.query('select id from public.places where occasion=$1',[f.occasion]); // actual anon RLS, no helper EXECUTE failure
}));

test('editor alone creates and replays through the shared application and delegated boundary',options,async t=>within(t,async(db,f)=>{
    const args=[randomUUID(),JSON.stringify({unit:f.unit,organization:f.org,title:'Authorization replay',is_hidden:true,is_open:false,start_time:'2027-01-01T18:00:00Z',end_time:'2027-01-02T02:00:00Z'})];
    await identity(db,f);
    const created=(await db.query('select create_delegated_occasion_client_sync_v1($1,$2::jsonb) value',args)).rows[0].value;
    assert.equal(created.status,'applied');
    const replay=(await db.query('select create_delegated_occasion_client_sync_v1($1,$2::jsonb) value',args)).rows[0].value;
    assert.equal(replay.data.occasionId,created.data.occasionId);
    await db.query('RESET ROLE');await db.query('update unit_users set is_manager=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
    await identity(db,f);
    const delegatedReplay=(await db.query('select create_delegated_occasion_client_sync_v1($1,$2::jsonb) value',args)).rows[0].value;
    assert.equal(delegatedReplay.data.occasionId,created.data.occasionId);
    const editorCreated=(await db.query('select create_occasion_client_sync_v1($1,$2::jsonb) value',[randomUUID(),args[1]])).rows[0].value;
    assert.equal(editorCreated.status,'applied');
    await db.query('RESET ROLE');await db.query('update unit_users set is_editor=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
    await identity(db,f);
    await forbidden(db,'select create_occasion_client_sync_v1($1,$2::jsonb)',args);
    await forbidden(db,'select get_delegated_ticket_layout_for_authoring_v1($1,$2,$3)',[f.occasion,f.org,f.unit]);
    await db.query('RESET ROLE');await db.query('update unit_users set is_manager=true where unit=$1 and "user"=$2',[f.unit,f.actor]);
    await identity(db,f);
    const managerCreated=(await db.query('select create_delegated_occasion_client_sync_v1($1,$2::jsonb) value',[randomUUID(),args[1]])).rows[0].value;
    assert.equal(managerCreated.status,'applied');
    assert.equal((await db.query('select can_edit_occasion($1) allowed',[managerCreated.data.occasionId])).rows[0].allowed,false);
    const managerDeleted=(await db.query('select delete_occasion_client_sync_v1($1,$2) value',[managerCreated.data.occasionId,randomUUID()])).rows[0].value;
    assert.equal(managerDeleted.status,'applied','manager alone may delete without also being an editor');
}));

test('concurrent move outside consent is rechecked after the resource lock, as authenticated',options,async t=>{
    const admin=await connect(),mover=await connect(),reader=await connect();
    t.after(async()=>{for(const db of [admin,mover,reader]) {await db.query('ROLLBACK');await db.end();}});
    await admin.query('BEGIN');const f=await fixture(admin,1);
    const other=Number((await admin.query("insert into units(title,organization) values('Outside consent',$1) returning id",[f.org])).rows[0].id);
    await admin.query('COMMIT');
    await mover.query('BEGIN');await mover.query('update occasions set unit=$1 where id=$2',[other,f.occasion]);
    await reader.query('BEGIN');await identity(reader,f);
    const pid=reader.processID;
    const pending=reader.query('select get_delegated_ticket_layout_for_authoring_v1($1,$2,$3)',[f.occasion,f.org,f.unit]);
    // Attach rejection handling before allowing the mover to release the lock.
    const rejected=assert.rejects(pending,e=>e.code==='42501');
    let blocked=false;
    for(let i=0;i<50;i++) {
        const r=(await admin.query('select wait_event_type from pg_stat_activity where pid=$1',[pid])).rows[0];
        if(r?.wait_event_type==='Lock'){blocked=true;break;}
        await new Promise(r=>setTimeout(r,20));
    }
    assert(blocked,'reader must actually wait on the concurrently moved row');
    await mover.query('COMMIT');await rejected;
});

test('group resource projection and mutation share scoped rights and revoke before replay',options,async t=>within(t,async(db,f)=>{
    await db.query('update occasion_users set is_editor=false,is_editor_view=false,is_manager=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await db.query('update unit_users set is_editor=false,is_manager=false,is_editor_view=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
    const privatePlace=Number((await db.query(`insert into places(occasion,title,type,is_hidden,coordinates) values($1,'Owned private location','group',true,'{"latLng":{"lat":0,"lng":0}}') returning id`,[f.occasion])).rows[0].id);
    const otherPlace=Number((await db.query(`insert into places(occasion,title,type,is_hidden,coordinates) values($1,'Other private location','group',true,'{"latLng":{"lat":0,"lng":0}}') returning id`,[f.occasion])).rows[0].id);
    const group=Number((await db.query("insert into user_group_info(occasion,title,place) values($1,'Owned group',$2) returning id",[f.occasion,privatePlace])).rows[0].id);
    await db.query('insert into user_groups("group","user",is_admin) values($1,$2,true)',[group,f.actor]);
    await identity(db,f);
    const rights=async()=> (await db.query('select can_write_group($1,$2) write,can_read_group_editor($1,$2) read,can_move_map_place($1,$3) move,can_move_map_place($1,$4) other',[f.occasion,group,privatePlace,otherPlace])).rows[0];
    assert.deepEqual(await rights(),{write:true,read:true,move:true,other:false});
    const context=async()=> (await db.query('select get_app_config_v218($1::jsonb) c',[JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})])).rows[0].c;
    const c=await context();
    assert.equal(c.groups[group].capabilities['groups.write'],true);
    assert.equal(c.groups[group].capabilities['map.place.move'],true);
    assert.equal(c.capabilities['map.places.write'],false);
    assert.equal((await db.query('select can_add_group_members($1,$2) allowed',[f.occasion,group])).rows[0].allowed,true);
    assert.equal((await db.query('select can_add_group_members($1,$2) allowed',[f.occasion+999999,group])).rows[0].allowed,false);
    const memberArgs=[f.occasion,group,[f.actor],randomUUID()];
    const memberResult=(await db.query('select add_user_group_members_client_sync_v1($1,$2,$3,$4) r',memberArgs)).rows[0].r;
    assert.equal(memberResult.status,'unchanged');
    await forbidden(db,'select get_user_groups_for_context_internal_v1($1,true,true,true)',[f.occasion]);
    const args=[f.occasion,privatePlace,randomUUID(),0,1,2];
    const moved=(await db.query('select move_place_client_sync_v1($1,$2,$3,$4,$5,$6) result',args)).rows[0].result;
    assert.equal(moved.status,'applied');
    assert.equal((await db.query('select save_place_location($1,$2,$3) result',[privatePlace,1.5,2.5])).rows[0].result.code,200);
    assert.equal((await db.query('select save_place_location($1,$2,$3) result',[otherPlace,1.5,2.5])).rows[0].result.code,403);
    await db.query('RESET ROLE');
    await db.query('update user_groups set is_admin=false where "group"=$1 and "user"=$2',[group,f.actor]);
    await identity(db,f);
    assert.deepEqual(await rights(),{write:false,read:false,move:false,other:false});
    assert.equal((await db.query('select can_read_group_members($1) allowed',[group])).rows[0].allowed,true,'ordinary member keeps member read without group-admin edit rights');
    assert.equal(Number((await db.query('select get_user_group_info_with_users($1) result',[group])).rows[0].result.id),group);
    assert.equal((await context()).groups[group].capabilities['map.place.move'],false);
    await forbidden(db,'select move_place_client_sync_v1($1,$2,$3,$4,$5,$6)',args);
    await forbidden(db,'select add_user_group_members_client_sync_v1($1,$2,$3,$4)',memberArgs);
}));

test('trusted custom-mail enqueue checks live actor rights and scope before dedupe replay',options,async t=>within(t,async(db,f)=>{
    await db.query('update occasion_users set is_editor=true,is_editor_order=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    const context=JSON.stringify({organization:f.org,occasion:f.occasion,unit:f.unit,actor_id:'00000000-0000-4000-8000-000000000099'});
    const args=[f.actor,'custom',context,'recipient@example.invalid',JSON.stringify({sealed:'task-owned-fixture'}),'authorization-'+randomUUID(),'c'.repeat(64),'AUTHORIZATION_FIXTURE',null];
    const sql='select enqueue_custom_email_for_actor_v1($1,$2,$3::jsonb,$4,$5::jsonb,$6,$7,$8,$9) result';
    await identity(db,f);
    await forbidden(db,sql,args);
    await forbidden(db,'select can_send_custom_email_as_actor_internal_v1($1,$2)',[f.actor,f.occasion]);
    await identity(db,f,'service_role');
    const queued=(await db.query(sql,args)).rows[0].result;
    assert(queued.message_id);
    assert.equal((await db.query(sql,args)).rows[0].result.message_id,queued.message_id);
    await db.query('RESET ROLE');
    assert.equal((await db.query('select producer_actor from email_messages where message_id=$1',[queued.message_id])).rows[0].producer_actor,f.actor,'trusted actor replaces caller context metadata');
    await db.query('update occasion_users set is_editor=false,is_editor_order=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await identity(db,f,'service_role');
    await forbidden(db,sql,args);
    for(let bits=0;bits<8;bits++) {
        await db.query('RESET ROLE');
        const b=Array.from({length:3},(_,i)=>Boolean(bits&(1<<i)));
        await db.query('update occasion_users set is_editor=$1,is_editor_view=$2,is_manager=$3 where occasion=$4 and "user"=$5',[...b,f.occasion,f.actor]);
        await identity(db,f,'service_role');
        const recipient=(await db.query('select get_sign_in_recipient_context_v1($1,$2) result',[f.actor,f.occasion])).rows[0].result;
        assert.equal(recipient.capabilities['emails.team_access_notice'],b.some(Boolean));
    }
    await db.query('RESET ROLE');
    await db.query('update occasion_users set is_editor=true where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await identity(db,f,'service_role');
    const foreignArgs=[...args];foreignArgs[2]=JSON.stringify({organization:f.org+1,unit:f.unit,occasion:f.occasion});
    await forbidden(db,sql,foreignArgs);
}));

test('service order operations share live actor policy without exposing arbitrary-actor helpers',options,async t=>within(t,async(db,f)=>{
    for(const role of ['anon','authenticated','service_role']) {
        await identity(db,f,role);
        await forbidden(db,'select order_editor_membership_as_actor_internal($1,$2)',[f.actor,f.occasion]);
        await forbidden(db,'select can_write_orders_as_actor_internal($1,$2)',[f.actor,f.occasion]);
    }
    await db.query('RESET ROLE');
    assert.equal((await db.query('select can_write_orders_as_actor_internal($1,$2) allowed',[f.actor,f.occasion])).rows[0].allowed,true);
    assert.equal((await db.query('select can_write_orders_as_actor_internal($1,$2) allowed',[randomUUID(),f.occasion])).rows[0].allowed,false);
    await db.query('update occasion_users set is_editor_order=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    assert.equal((await db.query('select can_write_orders_as_actor_internal($1,$2) allowed',[f.actor,f.occasion])).rows[0].allowed,false);
    assert.equal((await db.query('select order_editor_membership_as_actor_internal($1,$2) allowed',[f.actor,f.occasion])).rows[0].allowed,false);
}));

test('app links enqueue binds live participant-management rights before replay',options,async t=>within(t,async(db,f)=>{
    const context=JSON.stringify({organization:f.org,occasion:f.occasion,unit:f.unit,recipient_user:f.actor});
    const args=[f.actor,'app_links',context,'recipient@example.invalid',JSON.stringify({sealed:'task-owned-fixture'}),'authorization-'+randomUUID(),'d'.repeat(64),'APP_LINKS',null];
    const sql='select enqueue_participant_notice_for_actor_v1($1,$2,$3::jsonb,$4,$5::jsonb,$6,$7,$8,$9) result';
    await identity(db,f);
    await forbidden(db,sql,args);
    await forbidden(db,'select can_manage_occasion_users_as_actor_internal_v1($1,$2)',[f.actor,f.occasion]);
    await identity(db,f,'service_role');
    const queued=(await db.query(sql,args)).rows[0].result;
    assert(queued.message_id);
    assert.equal((await db.query(sql,args)).rows[0].result.message_id,queued.message_id);
    const teamArgs=[...args];teamArgs[1]='custom';teamArgs[7]='TEAM_ACCESS_NOTICE';teamArgs[5]='authorization-'+randomUUID();
    assert((await db.query(sql,teamArgs)).rows[0].result.message_id,'team notices share the same live sender policy');
    const invalidKind=[...args];invalidKind[1]=null;
    await forbidden(db,sql,invalidKind);
    await db.query('RESET ROLE');
    assert.equal((await db.query('select producer_actor from email_messages where message_id=$1',[queued.message_id])).rows[0].producer_actor,f.actor);
    await db.query('update occasion_users set is_manager=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await db.query('update unit_users set is_editor=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
    await identity(db,f,'service_role');
    await forbidden(db,sql,args);
    await db.query('RESET ROLE');
    await db.query('update occasion_users set is_manager=true where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await identity(db,f,'service_role');
    const foreign=[...args];foreign[2]=JSON.stringify({organization:f.org+1,occasion:f.occasion,unit:f.unit,recipient_user:f.actor});
    await forbidden(db,sql,foreign);
    const unknownRecipient=[...args];unknownRecipient[2]=JSON.stringify({organization:f.org,occasion:f.occasion,unit:f.unit,recipient_user:randomUUID()});
    await forbidden(db,sql,unknownRecipient);
}));

test('bank management requires both live unit and bank administration, including revocation and demo fences',options,async t=>within(t,async(db,f)=>{
    const bank=Number((await db.query("insert into eshop.bank_accounts(account_number,title,type) values($1,'Authorization bank','FIO') returning id",['authz-'+randomUUID()])).rows[0].id);
    await db.query('insert into eshop.bank_account_users(bank_account,"user",is_admin,is_support) values($1,$2,true,false)',[bank,f.actor]);
    await db.query('insert into eshop.unit_bank_accounts(bank_account,unit,priority) values($1,$2,0)',[bank,f.unit]);
    const context=async()=> (await db.query('select get_app_config_v218($1::jsonb) c',[JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})])).rows[0].c;
    for (const manager of [false,true]) for (const admin of [false,true]) {
        await db.query('RESET ROLE');
        await db.query('update unit_users set is_manager=$3,is_editor=false where unit=$1 and "user"=$2',[f.unit,f.actor,manager]);
        await db.query('update eshop.bank_account_users set is_admin=$3 where bank_account=$1 and "user"=$2',[bank,f.actor,admin]);
        await identity(db,f);
        const c=await context();
        assert.equal(c.bank_capabilities[bank]?.['bank_accounts.write'] ?? false,manager && admin);
        assert.equal(c.capabilities['bank_accounts.unit.manage'],manager);
        if (manager) {
            assert.equal((await db.query('select id from get_bank_accounts_for_unit_management($1)',[f.unit])).rows.some(row=>Number(row.id)===bank),true,'unit manager can read the linked card without inventing account administration');
        } else {
            await forbidden(db,'select * from get_bank_accounts_for_unit_management($1)',[f.unit]);
        }

        assert.equal((await db.query('select can_manage_bank_account($1) allowed',[bank])).rows[0].allowed,manager && admin);
        if (manager && admin) {
            await db.query('select get_bank_sync_connection($1)',[bank]);
            await db.query('select update_bank_account($1,$2,$3)',[bank,bank+'/2010','Allowed details']);
        } else {
            for (const [sql,args] of [
                ['select get_bank_sync_connection($1)',[bank]],
                ['select update_bank_account_user($1,$2,true,false)',[bank,'nobody@example.invalid']],
                ['select update_bank_account($1,$2,$3)',[bank,bank+'/2010','Denied details']],
                ['select begin_bank_sync_operation($1,$2,$3,$4)',[randomUUID(),bank,'sync','a'.repeat(64)]],
            ]) {
                await db.query('SAVEPOINT bank_denied');
                await assert.rejects(db.query(sql,args),e=>e.code==='42501');
                await db.query('ROLLBACK TO SAVEPOINT bank_denied');
            }
        }
    }
    const operationId=randomUUID();
    await db.query('select begin_bank_sync_operation($1,$2,$3,$4)',[operationId,bank,'sync','a'.repeat(64)]);
    // Revocation of the linked unit role is effective without changing bank membership.
    await db.query('RESET ROLE');
    await db.query('update unit_users set is_manager=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
    await identity(db,f);
    assert.equal((await context()).bank_capabilities[bank]['bank_sync.manage'],false);
    await forbidden(db,'select get_bank_sync_connection($1)',[bank]);
    await forbidden(db,'select begin_bank_sync_operation($1,$2,$3,$4)',[operationId,bank,'sync','a'.repeat(64)]);
    await db.query('RESET ROLE');
    await db.query('update eshop.bank_account_users set is_admin=false where bank_account=$1 and "user"=$2',[bank,f.actor]);
    const demo=Number((await db.query('select bank_account from demo_occasions where bank_account IS NOT NULL limit 1')).rows[0].bank_account);
    await db.query('insert into eshop.bank_account_users(bank_account,"user",is_admin,is_support) values($1,$2,true,false)',[demo,f.actor]);
    await identity(db,f);
    assert.equal((await context()).bank_capabilities[bank],undefined,'revocation removes the resource projection');
    assert.equal((await context()).bank_capabilities[demo]['bank_accounts.users.write'],false);
    assert.equal((await db.query('select can_manage_bank_account($1) allowed',[bank])).rows[0].allowed,false);
    await db.query('SAVEPOINT readonly_bank');
    await assert.rejects(db.query('select update_bank_account_user($1,$2,false,false)',[demo,'someone@example.invalid']),e=>e.message.includes('Only bank account admins'));
    await db.query('ROLLBACK TO SAVEPOINT readonly_bank');
}));


test('bank linking requires target-unit manager and account admin without authorizing an unrelated unit',options,async t=>within(t,async(db,f)=>{
    const bank=Number((await db.query("insert into eshop.bank_accounts(account_number,title,type) values($1,'Unlinked authorization bank','FIO') returning id",['authz-'+randomUUID()])).rows[0].id);
    await db.query('insert into eshop.bank_account_users(bank_account,"user",is_admin) values($1,$2,true)',[bank,f.actor]);
    await identity(db,f);
    assert.equal((await db.query('select can_manage_bank_account($1) allowed',[bank])).rows[0].allowed,false,'management of an unrelated unit is insufficient');
    // Linking establishes the actual resource scope; it needs no previous link.
    await db.query('select link_bank_account_to_unit($1,$2,0)',[bank,f.unit]);
    assert.equal((await db.query('select can_manage_bank_account($1) allowed',[bank])).rows[0].allowed,true);
    await db.query('RESET ROLE');
    await db.query('update eshop.bank_account_users set is_admin=false where bank_account=$1 and "user"=$2',[bank,f.actor]);
    await identity(db,f);
    await db.query('select link_bank_account_to_unit($1,$2,NULL,true)',[bank,f.unit]);
    await db.query('SAVEPOINT cannot_relink');
    await assert.rejects(db.query('select link_bank_account_to_unit($1,$2,0)',[bank,f.unit]),e=>e.message.includes('not an admin'));
    await db.query('ROLLBACK TO SAVEPOINT cannot_relink');
    await db.query('RESET ROLE');
    await db.query('update eshop.bank_account_users set is_admin=true where bank_account=$1 and "user"=$2',[bank,f.actor]);
    await db.query('update unit_users set is_manager=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
    await identity(db,f);
    await db.query('SAVEPOINT cannot_link_without_unit');
    await assert.rejects(db.query('select link_bank_account_to_unit($1,$2,0)',[bank,f.unit]),e=>e.message.includes('manager'));
    await db.query('ROLLBACK TO SAVEPOINT cannot_link_without_unit');
    await forbidden(db,'select update_bank_account(NULL,$1,$2)',[bank+'/2010','No unit supplied']);
    await db.query('RESET ROLE');
    const demoUnit=Number((await db.query('select o.unit from demo_occasions d join occasions o on o.id=d.occasion where o.unit IS NOT NULL limit 1')).rows[0].unit);
    await db.query('insert into unit_users(unit,"user",is_manager) values($1,$2,true)',[demoUnit,f.actor]);
    await db.query('insert into eshop.unit_bank_accounts(unit,bank_account,priority) values($1,$2,0)',[demoUnit,bank]);
    await identity(db,f);
    assert.equal((await db.query('select can_manage_bank_account($1) allowed',[bank])).rows[0].allowed,false,'demo unit membership never authorizes a live account');
    const c=(await db.query('select get_app_config_v218($1::jsonb) c',[JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})])).rows[0].c;
    assert.equal(c.bank_capabilities[bank]['bank_sync.manage'],false);

}));


test('demo unit facts are private and change with the live registry',options,async t=>within(t,async(db,f)=>{
    const bank=Number((await db.query("insert into eshop.bank_accounts(account_number,title,type) values($1,'Demo facts bank','FIO') returning id",['authz-'+randomUUID()])).rows[0].id);
    await identity(db,f);
    await forbidden(db,'select * from demo_unit_ids_internal()',[]);
    assert.equal((await db.query('select is_demo_unit($1) demo,can_create_occasion($1) allowed',[f.unit])).rows[0].allowed,true);
    await db.query('RESET ROLE');
    await db.query("insert into demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,sort_order,description,reference_at) values($1,$2,'ball',$3,$4,0,'Synthetic authorization registry',now())",[f.occasion,f.org,randomUUID(),bank]);
    await identity(db,f);
    assert.deepEqual((await db.query('select is_demo_unit($1) demo,can_create_occasion($1) allowed',[f.unit])).rows[0],{demo:true,allowed:false});
    assert.deepEqual((await db.query('select can_write_blueprints($1) regular,can_migrate_reviewed_legacy_blueprint($1) reviewed',[f.occasion])).rows[0],{regular:false,reviewed:true},'reviewed offline demo migration is a distinct retained exception');
    await db.query('RESET ROLE');
    const blueprint=Number((await db.query("insert into eshop.blueprints(occasion,organization,title) values($1,$2,'Review authorization fixture') returning id",[f.occasion,f.org])).rows[0].id);
    const reviewedBlueprint=JSON.stringify({id:blueprint,expected_layout_revision:0});
    // Authorized review reaches document validation; it does not fail the role gate.
    await db.query('SAVEPOINT authorized_review');
    await assert.rejects(db.query('select save_blueprint_layout_impl_internal($1,true)',[reviewedBlueprint]),error=>error.code==='23514');
    await db.query('ROLLBACK TO SAVEPOINT authorized_review');await db.query('RELEASE SAVEPOINT authorized_review');
    await identity(db,f);
    const reviewedArgs=[randomUUID(),'blueprint.layout.reviewed_migration',f.occasion,f.actor,'a'.repeat(64),true];
    await forbidden(db,'select begin_client_mutation_reviewed_impl_internal($1,$2,$3,$4,$5,$6)',reviewedArgs);
    await db.query('RESET ROLE');
    assert.equal((await db.query('select begin_client_mutation_reviewed_impl_internal($1,$2,$3,$4,$5,$6) r',reviewedArgs)).rows[0].r.disposition,'claimed');
    await db.query('RESET ROLE');
    await db.query('update occasion_users set is_editor=false,is_manager=false where occasion=$1 and \"user\"=$2',[f.occasion,f.actor]);
    await identity(db,f);
    assert.equal((await db.query('select can_migrate_reviewed_legacy_blueprint($1) allowed',[f.occasion])).rows[0].allowed,false);
    await db.query('RESET ROLE');
    await forbidden(db,'select begin_client_mutation_reviewed_impl_internal($1,$2,$3,$4,$5,$6)',reviewedArgs);
    await forbidden(db,'select save_blueprint_layout_impl_internal($1,true)',[reviewedBlueprint]);
    await db.query('RESET ROLE');
    await db.query('delete from demo_occasions where occasion=$1',[f.occasion]);
    await identity(db,f);
    assert.deepEqual((await db.query('select is_demo_unit($1) demo,can_create_occasion($1) allowed',[f.unit])).rows[0],{demo:false,allowed:true});
}));

test('private sync binds membership, tenant and hidden-occasion access on every request',options,async t=>within(t,async(db,f)=>{
    await db.query('update occasion_users set is_editor=false,is_editor_view=false,is_manager=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    const known=JSON.stringify(Object.fromEntries(['private_program','private_profile','private_inventory','private_activity','private_news','private_feedback'].map(k=>[k,0])));
    const read=async(organization=f.org)=>(await db.query('select get_private_client_sync_v1($1::jsonb,$2::jsonb) result',[JSON.stringify({organizationId:organization,occasionId:f.occasion}),known])).rows[0].result;
    await identity(db,f);
    assert.equal((await read()).code,200,'ordinary member retains private personal sync');
    assert.equal((await read(f.org+1)).code,403);
    await db.query('RESET ROLE');
    await db.query('update occasions set is_hidden=true where id=$1',[f.occasion]);
    await identity(db,f);
    assert.equal((await read()).code,403,'unit management does not replace hidden occasion viewer membership');
    await db.query('RESET ROLE');
    await db.query('update occasion_users set is_editor_view=true where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await identity(db,f);
    assert.equal((await read()).code,200);
    await db.query('RESET ROLE');
    await db.query('delete from occasion_users where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await identity(db,f);
    assert.equal((await read()).code,403,'membership revocation cannot reuse the previous private response');
}));

test('unit-access deletion and audit reads preserve their distinct resource scopes and deny revoked replay',options,async t=>within(t,async(db,f)=>{
    assert.equal((await db.query("select has_function_privilege('service_role','public.delete_unit_user_internal_v1(uuid,bigint)','EXECUTE') allowed")).rows[0].allowed,false);
    const alias='audit-target-'+randomUUID();
    await db.query('select create_user_for_test($1,$2)',[alias,alias+'@example.invalid']);
    const target=(await db.query('select get_user_id($1) id',[alias])).rows[0].id;
    await db.query('insert into unit_users(unit,"user",is_manager,is_editor,is_editor_view) values($1,$2,true,true,true)',[f.unit,target]);
    await db.query('insert into occasion_users(occasion,"user",is_manager,is_editor,is_editor_view) values($1,$2,true,true,true)',[f.occasion,target]);
    const place=(await db.query('select id from places where occasion=$1 order by id limit 1',[f.occasion])).rows[0].id;
    const command=randomUUID();
    await identity(db,f);
    const deletion=(await db.query('select delete_unit_user_client_sync_v1($1,$2,$3) result',[target,f.unit,command])).rows[0].result;
    assert.equal(deletion.status,'applied');
    const movement=(await db.query('select move_place_client_sync_v1($1,$2,$3,0,1,2) result',[f.occasion,place,randomUUID()])).rows[0].result;
    assert.equal(movement.status,'applied');
    const unitCommit=deletion.mutation.commitId,occasionCommit=movement.mutation.commitId;
    assert.ok(unitCommit);assert.ok(occasionCommit);
    await db.query('RESET ROLE');
    assert.equal((await db.query('select count(*)::int n from unit_users where unit=$1 and "user"=$2',[f.unit,target])).rows[0].n,0);
    assert.deepEqual((await db.query('select is_editor,is_manager,is_editor_view from occasion_users where occasion=$1 and "user"=$2',[f.occasion,target])).rows[0],{is_editor:false,is_manager:false,is_editor_view:false});
    await db.query('update unit_users set is_manager=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
    await identity(db,f);
    const list=async()=>(await db.query('select get_client_commits_v1($1) result',[f.occasion])).rows[0].result;
    const detail=async(id)=>(await db.query('select get_client_commit_v1($1) result',[id])).rows[0].result;
    const occasionList=await list();assert.equal(occasionList.code,200);
    assert.equal(occasionList.data.some(c=>c.commitId===occasionCommit),true);
    assert.equal(occasionList.data.some(c=>c.commitId===unitCommit),false,'occasion management cannot expose a unit-only commit');
    assert.equal((await detail(occasionCommit)).code,200);
    assert.equal((await detail(unitCommit)).code,403);
    await db.query('RESET ROLE');
    await db.query('update occasion_users set is_manager=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await identity(db,f);
    assert.equal((await list()).code,403);
    assert.equal((await detail(occasionCommit)).code,403);
    await forbidden(db,'select delete_unit_user_client_sync_v1($1,$2,$3)',[target,f.unit,command]);
    await db.query('RESET ROLE');
    await db.query('update unit_users set is_manager=true where unit=$1 and "user"=$2',[f.unit,f.actor]);
    await identity(db,f);
    assert.equal((await list()).data.some(c=>c.commitId===unitCommit),true);
    assert.equal((await detail(unitCommit)).code,200,'unit manager retains the unit-only audit scope');
}));


test('order deletion rechecks the actual unit after waiting on a concurrent occasion move',options,async t=>{
    const admin=await connect(),mover=await connect(),writer=await connect();
    t.after(async()=>{for(const db of [admin,mover,writer]) {await db.query('ROLLBACK');await db.end();}});
    await admin.query('BEGIN');const f=await fixture(admin,1);
    const other=Number((await admin.query("insert into units(title,organization) values('Outside order authorization',$1) returning id",[f.org])).rows[0].id);
    const payment=(await admin.query("insert into eshop.payment_info(variable_symbol,amount,paid,currency_code) values($1,100,0,'CZK') returning id",[f.occasion])).rows[0].id;
    const order=(await admin.query("insert into eshop.orders(order_sequence,order_symbol,occasion,payment_info,state,price,currency_code) values(next_order_sequence($1),generate_order_symbol(),$1,$2,'storno',100,'CZK') returning id",[f.occasion,payment])).rows[0].id;
    await admin.query('COMMIT');
    await mover.query('BEGIN');await mover.query('update occasions set unit=$1 where id=$2',[other,f.occasion]);
    await writer.query('BEGIN');await identity(writer,f);
    const pending=writer.query('select delete_order_client_sync_v1($1,$2)',[order,randomUUID()]);
    const rejected=assert.rejects(pending,e=>e.code==='42501');
    let blocked=false;
    for(let i=0;i<50;i++) {
        const r=(await admin.query('select wait_event_type from pg_stat_activity where pid=$1',[writer.processID])).rows[0];
        if(r?.wait_event_type==='Lock'){blocked=true;break;}
        await new Promise(r=>setTimeout(r,20));
    }
    assert(blocked,'deletion must actually wait on the concurrently moved resource');
    await mover.query('COMMIT');await rejected;
    await writer.query('ROLLBACK');
    assert.equal((await admin.query('select count(*)::integer n from eshop.orders where id=$1',[order])).rows[0].n,1,'denied mutation keeps the order');
});


test('setup finalization and its replay accept either creation role independently',options,async t=>within(t,async(db,f)=>{
    for(const manager of [false,true]) {
        await db.query('RESET ROLE');
        await db.query('update unit_users set is_manager=$1,is_editor=NOT $1 where unit=$2 and "user"=$3',[manager,f.unit,f.actor]);
        await identity(db,f);
        const draftId=randomUUID(),command=randomUUID();
        const draft=(await db.query('select create_occasion_setup_draft($1,$2) d',[draftId,f.unit])).rows[0].d;
        const payload={...draft.data,title:'Single creation role setup',start:'2090-08-01T18:00:00Z',end:'2090-08-02T02:00:00Z',reviewConfirmed:true,formEnabled:true,blueprintMode:'Bez plánku',blueprintObjects:[]};
        payload.formDraft.fields[2].product_type_data.products[0].price=0;
        const saved=(await db.query('select save_occasion_setup_draft($1,$2,$3::jsonb,5) d',[draftId,draft.revision,JSON.stringify(payload)])).rows[0].d;
        const args=[draftId,saved.revision,command];
        const created=(await db.query('select finalize_occasion_setup_draft($1,$2,$3) d',args)).rows[0].d;
        assert.equal(created.code,200);
        assert.ok(created.data.occasionId);
        assert.deepEqual((await db.query('select finalize_occasion_setup_draft($1,$2,$3) d',args)).rows[0].d,created);
        await db.query('RESET ROLE');
        assert.equal(Number((await db.query('select count(*) n from forms where occasion=$1',[created.data.occasionId])).rows[0].n),1);
        await db.query('update unit_users set is_manager=false,is_editor=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
        await identity(db,f);
        await forbidden(db,'select finalize_occasion_setup_draft($1,$2,$3)',args);
    }
}));


test('gallery deletion uses the same media operation for editors and rechecks revoked roles atomically',options,async t=>within(t,async(db,f)=>{
    const occasionLink='https://img.festapp.net/images/authz/'+randomUUID()+'.png';
    const unitLink='https://img.festapp.net/images/authz/'+randomUUID()+'.png';
    for(const [editor,orderEditor,unitEditor,allowed] of [[true,false,false,true],[false,true,false,true],[false,false,true,true],[false,false,false,false]]) {
        await db.query('RESET ROLE');
        await db.query('update occasion_users set is_editor=$1,is_editor_order=$2 where occasion=$3 and "user"=$4',[editor,orderEditor,f.occasion,f.actor]);
        await db.query('update unit_users set is_editor=$1 where unit=$2 and "user"=$3',[unitEditor,f.unit,f.actor]);
        await db.query('insert into images(link,occasion) values($1,$2)',[occasionLink,f.occasion]);
        await db.query('insert into images(link,unit) values($1,$2)',[unitLink,f.unit]);
        await identity(db,f);
        const rights=(await db.query('select can_upload_occasion_media($1) occasion,can_upload_unit_media($2) unit',[f.occasion,f.unit])).rows[0];
        assert.deepEqual(rights,{occasion:editor||orderEditor,unit:unitEditor});
        if(allowed) {
            const permitted=unitEditor?unitLink:occasionLink,denied=unitEditor?occasionLink:unitLink;
            await forbidden(db,'select remove_image_records($1)',[[permitted,denied]]);
            await db.query('select remove_image_records($1)',[[permitted]]);
            await db.query('RESET ROLE');
            assert.equal(Number((await db.query('select count(*) n from images where link=$1',[permitted])).rows[0].n),0);
            assert.equal(Number((await db.query('select count(*) n from images where link=$1',[denied])).rows[0].n),1,'mixed-scope denial never deletes the permitted subset');
        } else {
            await forbidden(db,'select remove_image_records($1)',[[occasionLink,unitLink]]);
            await db.query('RESET ROLE');
            assert.equal(Number((await db.query('select count(*) n from images where link=ANY($1)',[[occasionLink,unitLink]])).rows[0].n),2);
        }
        await db.query('delete from images where link=ANY($1)',[[occasionLink,unitLink]]);
    }
}));


test('RLS cutover preserves every policy command, executor and permissiveness',options,async t=>within(t,async(db)=>{
    const before=JSON.parse(await readFile(new URL('../../../database/fixtures/authorization/pre-cutover-policies.json',import.meta.url),'utf8'));
    const key=p=>[p.schemaname,p.tablename,p.policyname].join('/');
    const metadata=p=>({schemaname:p.schemaname,tablename:p.tablename,policyname:p.policyname,cmd:p.cmd,permissive:p.permissive,roles:p.roles});
    const current=(await db.query("select to_jsonb(p)-'qual'-'with_check' metadata from pg_policies p where schemaname in ('public','eshop','storage')")).rows.map(r=>r.metadata);
    assert.deepEqual(current.sort((a,b)=>key(a).localeCompare(key(b))),before.policies.map(metadata).sort((a,b)=>key(a).localeCompare(key(b))));
}));

test('historical template delete retains its narrower role while delegating the only writer',options,async t=>within(t,async(db,f)=>{
    const code='AUTHZ_LEGACY_DELETE';
    await db.query('update occasion_users set is_editor=false,is_editor_order=true where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await db.query("insert into email_templates(occasion,code,subject,html) values($1,$2,'Authorization fixture','Task-owned template')",[f.occasion,code]);
    await identity(db,f);
    await db.query('SAVEPOINT legacy_denied');
    await assert.rejects(db.query('select delete_occasion_email_template($1,$2)',[f.occasion,code]),e=>e.message==='User is not an editor for this occasion');
    await db.query('ROLLBACK TO SAVEPOINT legacy_denied');await db.query('RELEASE SAVEPOINT legacy_denied');
    await db.query('select delete_entity_email_template($1,$2,$3)',['occasion',f.occasion,code]);
    await db.query('RESET ROLE');
    assert.equal(Number((await db.query('select count(*) n from email_templates where occasion=$1 and code=$2',[f.occasion,code])).rows[0].n),0);
    await db.query('update occasion_users set is_editor=true,is_editor_order=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
    await db.query("insert into email_templates(occasion,code,subject,html) values($1,$2,'Authorization fixture','Task-owned template')",[f.occasion,code]);
    await identity(db,f);await db.query('select delete_occasion_email_template($1,$2)',[f.occasion,code]);
    await db.query('RESET ROLE');
    assert.equal(Number((await db.query('select count(*) n from email_templates where occasion=$1 and code=$2',[f.occasion,code])).rows[0].n),0);
}));


test('full ACL comparison preserves tables and all unrelated function grants',options,async t=>within(t,async(db)=>{
    const before=JSON.parse(await readFile(new URL('../../../database/fixtures/authorization/pre-cutover-acl.json',import.meta.url),'utf8'));
    const query=await readFile(new URL('../../../automation/authorization/catalog.sql',import.meta.url),'utf8');
    const responses=await db.query(query),after=responses.at(-1).rows[0].jsonb_build_object;
    const sorted=rows=>(rows??[]).map(r=>JSON.stringify(r)).sort();
    for(const field of ['schemaGrants','defaultGrants','roles','roleMemberships']) {
        assert.deepEqual(sorted(after[field]),sorted(before[field]),field+' remains unchanged');
    }
    const removedDirectDelete=g=>g.table_schema==='public'&&['images','log_notifications'].includes(g.table_name)
        &&['anon','authenticated'].includes(g.grantee)&&g.privilege_type==='DELETE';
    assert.equal(before.tableGrants.filter(removedDirectDelete).length,4);
    // Approved additive Stripe schema (20261022160000/170000) explicitly owns
    // these tables as postgres and revokes all API-role access. Do not replace
    // the historical snapshot or ignore arbitrary new tables/column grants.
    const stripeTables=['stripe_admission_decisions','stripe_capabilities','stripe_checkout_attempts',
        'stripe_connection_audit','stripe_connection_flows','stripe_connections','stripe_disconnect_intents',
        'stripe_disputes','stripe_event_inbox','stripe_payment_link_sources','stripe_payment_movements',
        'stripe_runtime_policy','stripe_unit_features'];
    // 2350 adds exactly one private, lease-fenced replacement-invoice journal.
    const approvedPrivateTables=[...stripeTables,'replacement_invoice_preparations'];
    const ownerTables=before.tableGrants.filter(g=>g.table_schema==='eshop'&&g.table_name==='payment_info'&&g.grantee==='postgres');
    const ownerColumns=before.columnGrants.filter(g=>g.table_schema==='eshop'&&g.table_name==='payment_info'&&g.column_name==='id'&&g.grantee==='postgres');
    assert.equal(ownerTables.length,7);assert.equal(ownerColumns.length,4);
    const expectedTables=approvedPrivateTables.flatMap(table_name=>ownerTables.map(g=>({...g,table_name})));
    assert.deepEqual(sorted(after.tableGrants),sorted([...before.tableGrants.filter(g=>!removedDirectDelete(g)),...expectedTables]),
        'Only the four legacy DELETE grants are removed; approved private tables remain postgres-only');
    const privateColumns=(await db.query("select table_name,column_name from information_schema.columns where table_schema='eshop' and table_name=any($1)",[approvedPrivateTables])).rows;
    assert.deepEqual([...new Set(privateColumns.map(c=>c.table_name))].sort(),[...approvedPrivateTables].sort());
    const expectedColumns=privateColumns.flatMap(({table_name,column_name})=>ownerColumns.map(g=>({...g,table_name,column_name})));
    // The two additive payment_info columns inherit its unchanged table ACL.
    // API access to any other new column or any approved private-table column still fails.
    const paymentColumnTemplate=before.columnGrants.filter(g=>g.table_schema==='eshop'&&g.table_name==='payment_info'&&g.column_name==='id');
    for(const column_name of ['payment_method','stripe_connection_id'])expectedColumns.push(...paymentColumnTemplate.map(g=>({...g,column_name})));
    assert.deepEqual(sorted(after.columnGrants),sorted([...before.columnGrants,...expectedColumns]),
        'Every old column grant remains exact; additions match the reviewed Stripe ownership/inheritance');
    const old=new Map(before.functions.map(f=>[f.signature,f]));
    const configuration=JSON.parse(await readFile(new URL('../../../automation/canonical-source-contract.json',import.meta.url),'utf8'));
    const retired=new Set(configuration.retiredSignatures.map(s=>s.replace(/^public\./,'')));
    for(const s of ['set_claim(uuid,text,jsonb)','delete_claim(uuid,text)','get_claims(uuid)','get_claim(uuid,text)','get_my_claims()','get_my_claim(text)','is_claims_admin()']) retired.add(s);
    const present=new Set(after.functions.map(f=>f.signature));
    for(const f of before.functions) if(!present.has(f.signature)) assert(retired.has(f.signature),'Unreviewed removed function: '+f.signature);

    // Six fixture-created routines now execute under their verified production
    // owner. Live catalog metadata confirms postgres owns/grants these exact
    // signatures, without the disposable bootstrap's implicit supabase_admin
    // owner grant. Compare every API principal/privilege exactly after only
    // this declared owner transfer; never rebaseline unrelated functions.
    const productionOwners=new Set(['lock_spot_assignment_scope_internal_v1(bigint[],bigint[])',
        'preview_blueprint_swap(bigint,bigint)','release_blueprint_holds_client_sync_v1(bigint[],uuid)',
        'save_blueprint_layout_impl_internal(jsonb,boolean)','save_blueprint_layout_internal_v1(jsonb)',
        'storno_tickets_bulk_internal_v1(bigint[],boolean)']);
    const comparableFunctions=after.functions.map(f=>{
        if(!productionOwners.has(f.signature))return f;
        assert.equal(f.owner,'postgres',f.signature+' matches verified production owner');
        const original=old.get(f.signature);
        const transferred=original.grants.filter(g=>g.grantee!=='supabase_admin')
            .map(g=>({...g,grantor:g.grantor==='supabase_admin'?'postgres':g.grantor}));
        assert.deepEqual(sorted(f.grants),sorted(transferred),f.signature+' only transfers the fixture owner, preserving API grants exactly');
        return {...f,grants:original.grants};
    });
    const changes=comparableFunctions.filter(f=>old.has(f.signature)&&JSON.stringify(f.grants)!==JSON.stringify(old.get(f.signature).grants));
    assert.deepEqual(changes.map(f=>f.signature).sort(),[
        'delete_unit_user_internal_v1(uuid,bigint)',
        'get_occasion_seo_data(text)',
        'get_unit_edit_data(bigint)',
        'update_bank_account(bigint,text,text,text,text[],text,bigint,text)',
        'update_bank_account_user(bigint,text,boolean,boolean)',
    ]);
    // Approved scope tightening: unit dashboard 20261021230000 and public SEO
    // 20261022225500 remove ambient grants, without adding any new principal.
    for(const [signature,removed] of [['get_occasion_seo_data(text)',['PUBLIC']],['get_unit_edit_data(bigint)',['PUBLIC','anon']]])
        assert.deepEqual(sorted(changes.find(f=>f.signature===signature).grants),sorted(old.get(signature).grants.filter(g=>!removed.includes(g.grantee))),signature+' has only its reviewed revocations');
    const grants=sig=>changes.find(f=>f.signature===sig).grants.map(g=>g.grantee).sort();
    assert.deepEqual(grants('delete_unit_user_internal_v1(uuid,bigint)'),['postgres']);
    assert.deepEqual(grants('update_bank_account(bigint,text,text,text,text[],text,bigint,text)'),['authenticated','postgres','service_role','supabase_admin']);
    assert.deepEqual(grants('update_bank_account_user(bigint,text,boolean,boolean)'),['authenticated','postgres','service_role']);
}));


test('API roles have no effective direct table-write bypass around canonical commands',options,async t=>within(t,async(db,f)=>{
    for(const role of ['anon','authenticated']) {
        const reachable=(await db.query(`select c.oid::regclass::text relation,privilege
          from pg_class c join pg_namespace n on n.oid=c.relnamespace
          cross join unnest(array['INSERT','UPDATE','DELETE']) privilege
          where n.nspname in ('public','eshop','storage') and c.relkind in ('r','p','v')
          and (has_table_privilege($1,c.oid,privilege) or case when privilege='DELETE' then false else
            exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
              and has_column_privilege($1,c.oid,a.attnum,privilege)) end)
          and (not c.relrowsecurity or exists(select 1 from pg_policy p where p.polrelid=c.oid
            and p.polpermissive and p.polcmd in ('*',(case privilege when 'INSERT' then 'a' when 'UPDATE' then 'w' else 'd' end)::"char")
            and exists(select 1 from unnest(p.polroles) permitted where case when permitted=0 then true else pg_has_role($1,permitted,'MEMBER') end)))`,[role])).rows;
        assert.deepEqual(reachable,[],role+' cannot bypass RPC ownership, scope and receipt invariants');
        await identity(db,f,role);
        await forbidden(db,'delete from public.images where occasion=$1',[f.occasion]);
        await forbidden(db,'delete from public.log_notifications where occasion=$1',[f.occasion]);
        await db.query('RESET ROLE');
    }
}));

test('every fact-based authorization expression is private and immutable',options,async t=>within(t,async(db)=>{
    const source=await readFile(new URL('../../../database/functions/user_permissions/operation_rules.sql',import.meta.url),'utf8');
    const names=[...source.matchAll(/CREATE OR REPLACE FUNCTION public\.([a-z0-9_]+)/g)].map(m=>m[1]);
    names.push('bank_account_write_rule');
    const rows=(await db.query(`select p.proname,p.provolatile,p.prosecdef,p.prosrc,
        p.prorettype='boolean'::regtype boolean_result,
        has_function_privilege('anon',p.oid,'EXECUTE') anon,
        has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated,
        has_function_privilege('service_role',p.oid,'EXECUTE') service
        from pg_proc p where p.pronamespace='public'::regnamespace and p.proname=ANY($1)`,[names])).rows;
    assert.equal(rows.length,names.length);
    for(const p of rows) {
        assert.equal(p.provolatile,'i',p.proname);
        assert.equal(p.prosecdef,false,p.proname);
        assert.equal(p.boolean_result,true,p.proname);
        assert.equal(p.anon||p.authenticated||p.service,false,p.proname+' cannot accept caller-invented role facts');
        assert.doesNotMatch(p.prosrc,/(^|[^a-z_])(FROM|JOIN|EXECUTE|INSERT|UPDATE|DELETE)([^a-z_]|$)|auth\.uid/i,p.proname);
    }
}));


test('organization administration projection remains scoped in unit-only context',options,async t=>within(t,async(db,f)=>{
    await db.query('insert into organization_users(organization,"user",is_admin) values($1,$2,true)',[f.org,f.actor]);
    await identity(db,f);
    const get=async()=> (await db.query('select get_app_config_v218($1::jsonb) c',[JSON.stringify({organization:f.org,unit_id:f.unit,platform:{platform:'web'}})])).rows[0].c;
    const c=await get();
    assert.equal(c.is_admin,false,'existing occasion-admin envelope is preserved');
    assert.equal(c.capabilities['organization.settings.write'],true,'tenant settings have a distinct live scope');
    await forbidden(db,'select organization_context_capabilities(true)',[]);
    await db.query('RESET ROLE');
    await db.query('update organization_users set is_admin=false where organization=$1 and "user"=$2',[f.org,f.actor]);
    await identity(db,f);
    assert.equal((await get()).capabilities['organization.settings.write'],false);
}));


test('legacy bank transaction pull lists only actual scoped accounts with both live roles',options,async t=>within(t,async(db,f)=>{
    const bank=Number((await db.query("insert into eshop.bank_accounts(account_number,title,type) values($1,'Pull authority','FIO') returning id",['authz-'+randomUUID()])).rows[0].id);
    await db.query('insert into eshop.bank_account_users(bank_account,"user",is_admin) values($1,$2,true)',[bank,f.actor]);
    await db.query('insert into eshop.unit_bank_accounts(bank_account,unit,priority) values($1,$2,0)',[bank,f.unit]);
    const connection=(await db.query(`insert into eshop.bank_sync_connections(instance_id,consumer_app_id,remote_bank_account_id,
        bank_account_id,physical_account,provider,mode,state,manifest_sha256,legacy_blocked_at)
        values($1,'festapp','777',$2,$3,'FIO','api','connected',$4,now()) returning id`,['authz-'+randomUUID(),bank,'authz-'+randomUUID(),'a'.repeat(64)])).rows[0].id;
    for(const manager of [false,true]) for(const admin of [false,true]) {
        await db.query('RESET ROLE');
        await db.query('update unit_users set is_manager=$3 where unit=$1 and "user"=$2',[f.unit,f.actor,manager]);
        await db.query('update eshop.bank_account_users set is_admin=$3 where bank_account=$1 and "user"=$2',[bank,f.actor,admin]);
        await identity(db,f);
        if(!manager) await forbidden(db,'select * from get_bank_sync_connections_for_occasion($1)',[f.link]);
        else {
            const rows=(await db.query('select * from get_bank_sync_connections_for_occasion($1)',[f.link])).rows;
            assert.deepEqual(rows,admin?[{connection_id:connection,remote_bank_account_id:'777'}]:[]);
        }
    }
    await db.query('RESET ROLE');
    const demo=(await db.query('select occasion,bank_account from demo_occasions order by occasion limit 1')).rows[0];
    await db.query('update demo_occasions set bank_account=$1 where occasion=$2',[bank,demo.occasion]);
    await identity(db,f);
    assert.deepEqual((await db.query('select * from get_bank_sync_connections_for_occasion($1)',[f.link])).rows,[],'demo bank remains read-only even when linked to a normal managed unit');
    await db.query('RESET ROLE');
    await db.query('update demo_occasions set bank_account=$1 where occasion=$2',[demo.bank_account,demo.occasion]);
    await db.query('delete from eshop.unit_bank_accounts where bank_account=$1 and unit=$2',[bank,f.unit]);
    await identity(db,f);
    assert.deepEqual((await db.query('select * from get_bank_sync_connections_for_occasion($1)',[f.link])).rows,[],'a stale account-admin grant does not preserve the removed unit link');
    await forbidden(db,'select * from get_bank_sync_connections_for_occasion($1)',['missing-'+randomUUID()]);
    await identity(db,f,'service_role');
    await forbidden(db,'select * from get_bank_sync_connections_for_occasion($1)',[f.link]);
}));


test('crew navigation preserves actual crew assignment independently of editor oversight',options,async t=>within(t,async(db,f)=>{
    for(let bits=0;bits<8;bits++) {
        const crew=Boolean(bits&1),editor=Boolean(bits&2),approver=Boolean(bits&4);
        await db.query('RESET ROLE');
        await db.query('update occasion_users set is_cleaning_crew=$1,is_editor=$2,is_approver=$3 where occasion=$4 and "user"=$5',[crew,editor,approver,f.occasion,f.actor]);
        await identity(db,f);
        const c=(await db.query('select get_app_config_v218($1::jsonb) c',[JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})])).rows[0].c;
        assert.equal(c.capabilities['navigation.cleaning_crew'],crew);
        assert.equal(c.capabilities['navigation.schedule_entry_check'],approver);
    }
}));
