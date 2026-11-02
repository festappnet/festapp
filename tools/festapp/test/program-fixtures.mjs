import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {setup as formSetup} from './form-fixtures.mjs';
import {programDescriptors,invokeProgramOperation} from '../src/operations/program.mjs';
export async function setup(t){
 assert(process.env.FESTAPP_MCP_TEST_DATABASE_URL,'A marker-verified disposable PostgreSQL is required');
 const {db,f}=await formSetup(t);
 await db.query("update organizations set data=data||'{\"IS_APP_SUPPORTED\":true}' where id=$1",[f.org]);
 await db.query("update occasions set features='[{\"code\":\"volunteers\",\"is_enabled\":true},{\"code\":\"services\",\"is_enabled\":true},{\"code\":\"counseling\",\"is_enabled\":true}]' where id=$1",[f.occasion]);
 const client={rpc:async(name,args)=>{await db.query('SAVEPOINT rpc');try{const keys=Object.keys(args);const data=(await db.query('select '+name+'('+keys.map((k,i)=>k+'=> $'+(i+1)).join(',')+') value',Object.entries(args).map(([key,value])=>key==='p_columns'?JSON.stringify(value):value))).rows[0].value;await db.query('RELEASE SAVEPOINT rpc');return{data,error:null};}catch(error){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return{data:null,error};}}};
 const owner={root:'/tmp/program-authoring',profile:{name:'fixture',tenantId:'fixture',organizationId:f.org},allowedOperations:programDescriptors.map(d=>d.id),delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),authorized:action=>action(client,{userId:f.actor})};
 await db.query('SET LOCAL ROLE authenticated');
 const invoke=(op,args={})=>invokeProgramOperation(owner,client,op,{occasionId:f.occasion,...args});
 const command=(op,args={})=>invoke(op,{commandId:randomUUID(),...args});
 return{db,f,client,owner,invoke,command};
}
