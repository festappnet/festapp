import pg from 'pg';
import assert from 'node:assert/strict';
import {randomUUID,randomInt} from 'node:crypto';
export const app='9c099206-ce3d-43de-bd9d-deb96bb4f51e';
export const terms={reference:'synthetic-partner-terms',serviceFeeOnly:true,grossTicketValueExcluded:true,externalTicketCheckoutApproved:true,
 partnerBillingApproved:true,refundTreatmentConfirmed:true,attributionPolicyReference:'synthetic-attribution',refundPolicyReference:'synthetic-refunds',refundConversion:'original-charge'};
export async function connectSourceFixture(){
 const url=new URL(process.env.WIX_BILLING_TEST_DATABASE_URL);assert.ok(['127.0.0.1','localhost'].includes(url.hostname));
 const db=new pg.Client({connectionString:url.href});await db.connect();
 assert.equal((await db.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton')).rows[0]?.project,'festapp-wix-billing-20261028');
 const rpc=async(name,args,client=db)=>{
  assert.match(name,/^[a-z_]+$/);const entries=Object.entries(args);
  return (await client.query(`SELECT public.${name}(${entries.map(([key],i)=>`${key}=>$${i+1}`).join(',')}) AS value`,entries.map(([,v])=>v))).rows[0].value;
 };
 const identity=randomUUID(),agreement=randomUUID(),instance=randomUUID(),reference=`synthetic-contract-${identity}`;
 const org=(await db.query("INSERT INTO public.organizations(title,data) VALUES('Synthetic integrity tests','{}') RETURNING id")).rows[0].id;
 const unit=(await db.query("INSERT INTO public.units(title,organization) VALUES('Synthetic integrity customer',$1) RETURNING id",[org])).rows[0].id;
 const occasion=(await db.query("INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) VALUES('Synthetic integrity',$1,$2,$3,now(),now()+interval '1 day') RETURNING id",[org,unit,identity])).rows[0].id;
 const form=(await db.query("INSERT INTO public.forms(occasion,link,is_open,data) VALUES($1,$2,true,'{}') RETURNING id",[occasion,identity])).rows[0].id;
 const letters='ACEFGHIJKLMNPQRUVWXY',symbol=Array.from({length:5},()=>`${randomInt(1,10)}${letters[randomInt(letters.length)]}`).join('');
 const order=(await db.query("INSERT INTO eshop.orders(occasion,form,created_at,price,currency_code,order_sequence,order_symbol) VALUES($1,$2,'2026-09-30T12:00:00Z',100000,'CZK',1,$3) RETURNING id",[occasion,form,symbol])).rows[0].id;
 await db.query("INSERT INTO eshop.order_checkout_origins(order_id,form_id,channel,instance_id,site_id,verified_at) VALUES($1,$2,'wix',$3,$4,now())",[order,form,instance,randomUUID()]);
 await rpc('register_service_fee_agreement',{p_id:agreement,p_unit:unit,p_reference:reference,p_rate_bps:500,p_from:'2026-01-01T00:00:00Z',p_until:null});
 await rpc('register_service_fee_acquisition',{p_unit:unit,p_channel:'wix',p_acquired_at:'2026-01-01T00:00:00Z',p_evidence:'synthetic-acquisition'});
 const source={id:randomUUID(),agreementId:agreement,kind:'charge',sourceReference:`synthetic-payment-${identity}`,invoiceReference:'synthetic-invoice',
  paymentEvidenceReference:'synthetic-paid-invoice',allocationEvidenceReference:'synthetic-exact-allocation',settledAt:'2026-10-01T12:00:00.000Z',
  serviceAt:'2026-10-01T12:00:00.000Z',currency:'CZK',amountBasis:'settled-service-fee-excluding-tax',feeMinor:'3',taxMinor:'0',
  allocations:[{id:randomUUID(),orderId:order,feeMinor:'3',agreedExpensesMinor:'0',partnerTermsReference:terms.reference,wixShareBps:5000,
   fx:{usdMinorNumerator:'1',sourceMinorDenominator:'2',reference:'synthetic-fx'}}]};
 return{db,rpc,url,org,unit,agreement,source,instance,reference,
  input:async period=>{const exported=await rpc('export_wix_service_fee_receipts',{p_organization:org,p_partner_terms:terms.reference});assert.equal(exported.schemaVersion,2);return{schemaVersion:2,period,agreement:terms,receipts:exported.receipts};},
  refund:(date)=>({...source,id:randomUUID(),kind:'refund',originalSettlementId:source.id,sourceReference:`synthetic-refund-${randomUUID()}`,settledAt:date,feeMinor:'1',
   allocations:[{id:randomUUID(),orderId:order,originalAllocationId:source.allocations[0].id,feeMinor:'1',agreedExpensesMinor:'0'}]}),
  async close(){
   await db.query('ROLLBACK');
   await db.query('DELETE FROM public.wix_billing_attempts a USING public.wix_billing_deliveries d WHERE a.app_id=d.app_id AND a.receipt_id=d.receipt_id AND a.kind=d.kind AND d.payload#>>\'{basis,organizerAgreementReference}\'=$1',[reference]);
   await db.query("DELETE FROM public.wix_billing_deliveries WHERE payload#>>'{basis,organizerAgreementReference}'=$1",[reference]);
   await db.query('DELETE FROM public.service_fee_allocations WHERE settlement_id IN(SELECT id FROM public.service_fee_settlements WHERE agreement_id=$1)',[agreement]);
   await db.query('DELETE FROM public.service_fee_settlements WHERE agreement_id=$1',[agreement]);
   await db.query('DELETE FROM public.service_fee_customer_acquisitions WHERE unit_id=$1',[unit]);await db.query('DELETE FROM public.service_fee_agreements WHERE unit_id=$1',[unit]);
   await db.query('DELETE FROM eshop.orders WHERE id=$1',[order]);await db.query('DELETE FROM public.forms WHERE id=$1',[form]);
   await db.query('DELETE FROM public.occasions WHERE id=$1',[occasion]);await db.query('DELETE FROM public.units WHERE id=$1',[unit]);await db.query('DELETE FROM public.organizations WHERE id=$1',[org]);
   await db.query('UPDATE public.wix_billing_activation SET enabled=false WHERE app_id=$1',[app]);await db.end();
  }};
}
