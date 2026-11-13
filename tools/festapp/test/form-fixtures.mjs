import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from '../../../automation/authorization/benchmark.mjs';
import {openDisposableDatabase,assertSchema} from './postgres.mjs';
import {Operations} from '../src/operations/catalog.mjs';
const connection=process.env.FESTAPP_MCP_TEST_DATABASE_URL;
const options={skip:!connection};
export async function enableFixtureBankPayments(db,f,{cash=false}={}) {
 await db.query("insert into eshop.payment_method_policy_scopes(organization_id,preferred_method) values($1,'bank')",[f.org]);
 await db.query("insert into eshop.organization_payment_method_policies(organization_id,method,enabled) values($1,'bank',true),($1,'cash',$2)",[f.org,cash]);
}
async function setup(t){const db=await openDisposableDatabase(connection);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});const f=await fixture(db,2);await enableFixtureBankPayments(db,f,{cash:true});await db.query("update public.units set data=coalesce(data,'{}')||jsonb_build_object('measurement_privacy_url','https://organizer.example/privacy') where id=$1",[f.unit]);return{db,f};}
function executor(db,f){const calls=[];const client={rpc:async(name,args)=>{await db.query('SAVEPOINT rpc');try{const names=Object.keys(args),values=Object.values(args);const data=(await db.query('select '+name+'('+names.map((n,i)=>n+'=> $'+(i+1)).join(',')+') value',values)).rows[0].value;await db.query('RELEASE SAVEPOINT rpc');calls.push({name,bytes:Buffer.byteLength(JSON.stringify(data))});return{data,error:null};}catch(error){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return{data:null,error};}}};
 const owner={profile:{name:'fixture',tenantId:'fixture',organizationId:f.org},root:'/tmp/form-authoring',allowedOperations:['forms.list','forms.inspect','forms.paymentOptions','forms.publicLink','forms.setPublicLink','forms.previewOrder','forms.createOrder','waitlist.proposal','waitlist.detail','waitlist.send','waitlist.cancel','waitlist.withdraw','forms.create','forms.save','forms.duplicate','forms.delete'],delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),authorized:action=>action(client,{userId:f.actor})};return{ops:new Operations(owner),calls};}
async function create(db,f,title='Synthetic form'){const result=(await db.query("select manage_form($1,$2,$3,'create',$4,$5) value",[f.occasion,f.org,f.unit,{title},randomUUID()])).rows[0].value;assert.equal(result.code,200,JSON.stringify(result));return result.data;}
function formPatch(state,patch={}){return{id:state.form.id,expected_aggregate_version:state.form.aggregate_version,expected_product_versions:state.productVersions,expected_product_type_versions:state.productTypeVersions,...patch};}
async function save(db,f,payload,commandId=randomUUID()){return(await db.query("select manage_form($1,$2,$3,'save',$4,$5) value",[f.occasion,f.org,f.unit,payload,commandId])).rows[0].value;}
async function denied(db,sql,args,code='42501'){await db.query('SAVEPOINT denied');await assert.rejects(db.query(sql,args),e=>e.code===code);await db.query('ROLLBACK TO SAVEPOINT denied');await db.query('RELEASE SAVEPOINT denied');}


export {connection,options,assertSchema,setup,executor,create,formPatch,save,denied};
