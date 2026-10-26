import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { connect, fixture } from '../../../automation/authorization/benchmark.mjs';
import { DelegatedOwner } from '../src/remote/delegation.mjs';
import { verifySelection } from '../src/operations/access.mjs';
import { createOccasion } from '../src/operations/occasion-create.mjs';
import { READ_SCOPE, CREATE_SCOPE } from '../src/remote/config.mjs';

test('tree consent keeps real SQL reads, future creation, moves and revoked rights inside selected organizers',
    {skip:!process.env.FESTAPP_AUTHORIZATION_DATABASE_URL}, async t => {
    const db=await connect();await db.query('BEGIN');
    t.after(async()=>{await db.query('ROLLBACK');await db.end();});
    const f=await fixture(db,1);
    const second=Number((await db.query("insert into units(title,organization) values('Second tree organizer',$1) returning id",[f.org])).rows[0].id);
    const excluded=Number((await db.query("insert into units(title,organization) values('Excluded tree organizer',$1) returning id",[f.org])).rows[0].id);
    await db.query('insert into unit_users(unit,"user",is_editor,is_manager,is_editor_view) values($1,$3,true,true,true),($2,$3,true,true,true)',[second,excluded,f.actor]);
    const extra=(await db.query("insert into occasions(title,link,organization,unit,start_time,end_time) values('Selected individually',gen_random_uuid()::text,$1,$2,now(),now()+interval '1 day') returning id",[f.org,excluded])).rows[0];
    const individual=Number(extra.id);
    await db.query('SET LOCAL ROLE authenticated');
    const client={rpc:async(name,args)=>{
        await db.query('SAVEPOINT rpc');
        try {
            const sql=name==='get_operator_access_v1'?'select get_operator_access_v1($1,$2,$3) value'
                :name==='get_delegated_ticket_layout_for_authoring_v1'?'select get_delegated_ticket_layout_for_authoring_v1($1,$2,$3) value'
                :'select create_delegated_occasion_client_sync_v1($1,$2::jsonb) value';
            const values=name==='get_operator_access_v1'?[args.p_organization,args.p_unit,args.p_occasion]
                :name==='get_delegated_ticket_layout_for_authoring_v1'?[args.p_occasion,args.p_organization,args.p_unit]
                :[args.p_command_id,JSON.stringify(args.p_config)];
            const data=(await db.query(sql,values)).rows[0].value;
            await db.query('RELEASE SAVEPOINT rpc');return {data,error:null};
        } catch(error){await db.query('ROLLBACK TO SAVEPOINT rpc');return {data:null,error:{code:error.code,status:error.code==='42501'?403:400}};}
    }};
    const profile={organizationId:f.org,binding:'tree-postgres'};
    const available=(await client.rpc('get_operator_access_v1',{p_organization:f.org,p_unit:null,p_occasion:null})).data;
    const access=verifySelection({type:'selection',units:[{unitId:f.unit,canCreateOccasions:true},{unitId:second,canCreateOccasions:true}],occasionIds:[individual]},available,true);
    const config={profile,clients:[{id:'tree-client'}],resource:'https://fixture.test/mcp'};
    const grant={id:'tree-grant',userId:f.actor,clientId:'tree-client',profileBinding:profile.binding,binding:'tree-session',access,expiresAt:Date.now()+60000};
    const owner=new DelegatedOwner(config,{get:()=>grant,backendStore:{}},{grantId:grant.id,accountId:f.actor,clientId:'tree-client',aud:config.resource,scope:READ_SCOPE+' '+CREATE_SCOPE,exp:Date.now()/1000+60});
    const create=async unitId=>{
        owner.authorizeOperation('occasions.create',{unitId});
        return createOccasion(client,profile,{commandId:randomUUID(),unitId,title:'Tree future occasion',start:'2027-01-01T18:00:00Z',end:'2027-01-02T02:00:00Z',description:''},{delegated:true});
    };
    const created=await create(second);
    assert((await owner.listAccess(client)).occasions.some(o=>o.id===created.occasionId));
    assert.deepEqual(await owner.delegatedContext(client,created.occasionId),{organizationId:f.org,unitId:second});
    assert.deepEqual(await owner.delegatedContext(client,individual),{organizationId:f.org,unitId:null});
    await assert.rejects(create(excluded),/FORBIDDEN/);
    const scope=await owner.delegatedContext(client,f.occasion);
    await db.query('RESET ROLE');await db.query('update occasions set unit=$1 where id=$2',[excluded,f.occasion]);await db.query('SET LOCAL ROLE authenticated');
    const raced=await client.rpc('get_delegated_ticket_layout_for_authoring_v1',{p_occasion:f.occasion,p_organization:scope.organizationId,p_unit:scope.unitId});
    assert(raced.error,'SQL rejects moving an occasion after resolving its organizer');
    await assert.rejects(owner.delegatedContext(client,f.occasion),/FORBIDDEN/);
    await db.query('RESET ROLE');await db.query('update unit_users set is_editor=false,is_manager=false,is_editor_view=false where unit=$1 and "user"=$2',[second,f.actor]);await db.query('SET LOCAL ROLE authenticated');
    await assert.rejects(create(second),/FORBIDDEN/);
    assert(!(await owner.listAccess(client)).occasions.some(o=>o.id===created.occasionId));
});
