import {assert, assertEquals, assertStringIncludes} from "https://deno.land/std@0.224.0/assert/mod.ts";
Deno.env.set("SUPABASE_URL","https://local-payment-test.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY","local-test-only");
const {supabaseAdmin} = await import("./supabaseUtil.ts");
const {paymentRegistry} = await import("./payments/runtime.ts");
const {renderQueuedEmail} = await import("./emailRenderer.ts");
const {getTicketOrderConfirmationTemplate} = await import("../send-email/getTicketOrderConfirmationTemplate.ts");
import type {PaymentMethodBinding, HostedPaymentDependencies} from "./payments/contracts.ts";

// Exercise production handlers, completion and inherited wrapper; the only fake
// boundary is the already-authorized SQL/provider source. Any HTTP is forbidden.
Deno.test("production payment emails honor method, current collection and inherited wrappers", async () => {
 const originalRpc=supabaseAdmin.rpc, originalResolve=paymentRegistry.resolve, originalHas=paymentRegistry.has;
 const originalFetch=globalThis.fetch; let sourceOpens=0, attachmentHooks=0;
 let method="bank", status="open", allowed=false, currency="CZK", price=100, paid=0;
 const occasion={id:3,organization:1,unit:2,title:"Podzimní ples",features:[]};
 const bank={account_number:"2000145399/0800",account_number_human_readable:"2000145399/0800",iban:"CZ6508000000192000145399",creditor_name:"Pořadatel plesu"};
 const details=()=>{
  const payment_info={payment_method:method,amount:price,paid,returned:0,currency_code:currency,variable_symbol:12345,creditor_reference:'RF18539007547034',deadline:"2026-12-01T18:00:00Z",...bank,account_number:currency==='EUR'?bank.iban:bank.account_number,
   collectionAction:{method,purpose:"collect_payment",allowed},providerPayment:{method,status}};
  return {order:{id:4,order_symbol:"1A2C3E4F5G",price,currency_code:currency,data:{email:"current@example.invalid",tickets:[]},occasion,payment_info},
   occasion,payment_info,bank_account:{...bank,account_number:currency==='EUR'?bank.iban:bank.account_number},latest_history_id:9,order_changes:{version:1,hasChanges:false},form_data:{},reference_history:[],reply_to:"poradatel@example.invalid"};
 };
 const rpc=async(name:string)=>{
  let data:unknown;
  if(name==="get_order_details_for_email")data={code:200,data:details()};
  else if(name==="generate_request_secret")data="test-secret";
  else if(name==="check_request_secret")data=true;
  else if(name==="is_demo_occasion")data=false;
  else if(name==="get_order_email_overview_source_v1")data=null;
  else if(name==="get_latest_order_history")data={price,currency_code:currency};
  else if(name==="get_external_services"){attachmentHooks++;data=[];}
  else if(name==="get_email_template_and_wrapper")data={template:{id:1,subject:"{{occasionTitle}}",html:"<p>{{balanceReasoning}}</p>{{paymentAction}}{{fullOrder}}"},wrapper:{html:"<main>{{content}}{{paymentAction}}</main>"}};
  else throw Error("Unexpected SQL call: "+name);
  return {data,error:null};
 };
 supabaseAdmin.rpc=rpc as unknown as typeof supabaseAdmin.rpc;
 paymentRegistry.has=((id:unknown)=>typeof id==="string"&&["bank","cash","stripe","barion","orchard"].includes(id)) as typeof paymentRegistry.has;
 paymentRegistry.resolve=(id:unknown):PaymentMethodBinding=>{
  if(id==="bank"||id==="cash")return originalResolve.call(paymentRegistry,id);
  const connector={id:String(id),displayName:String(id)==="orchard"?"Orchard":"Gateway "+id};
  const hosted={connector,order:{readSource:async()=>({payment:{method,status},payBaseUrl:"https://tickets.example/pay"})},
   openSource:async()=>{sourceOpens++;return {payToken:"a".repeat(64)};},routes:{payPath:"/pay"},allowedOrigins:["https://tickets.example"]} as unknown as HostedPaymentDependencies;
  return {connector,hostedCheckout:hosted} as PaymentMethodBinding;
 };
 globalThis.fetch=()=>Promise.reject(Error("Unexpected external request"));
 try {
  for(method of ["bank","cash","stripe","barion","orchard","unknown"]) {
   for(status of ["open","paid","partially_refunded","refunded","disputed","expired","action_required"]) {
    allowed=false; paid=status==="paid"?100:0;
    const before=attachmentHooks;
    for(const kind of ["order_confirmation","order_update","order_payment_notice","order_storno"]) {
     const result=await renderQueuedEmail({message_id:"message",message_kind:kind,code:kind==="order_confirmation"?"TICKET_ORDER_CONFIRMATION":kind==="order_update"?"TICKET_ORDER_UPDATE":kind==="order_storno"?"TICKET_ORDER_STORNO":"TICKET_ORDER_PAYMENT_DONE",
      data:{lang:"cs",command_id:"command",ticket_order:{order:details().order}},recipient:"snapshot@example.invalid",organization:1,unit:2,occasion:3,order_id:4,lease_token:"lease",attempt_id:"attempt",prepared:null});
     assertEquals(result.prepared.to,"snapshot@example.invalid");
     assertEquals(result.prepared.attachments.length,0,method+"/"+status+"/"+kind);
     assert(!result.prepared.html.includes(bank.account_number),method+" must not leak stale bank data");
     assert(!result.prepared.html.includes("#pay="));
    }
    assertEquals(attachmentHooks,before,"disabled/non-bank paths never consult external attachment or invoice hooks");
   }
  }
  assertEquals(sourceOpens,0,"closed collection never opens a private pay token");
  for(method of ["stripe","barion","orchard"]) {
   status="open";allowed=true;price=100;paid=0;
   const result=await renderQueuedEmail({message_id:"message",message_kind:"order_confirmation",code:"TICKET_ORDER_CONFIRMATION",data:{lang:"cs",ticket_order:{order:details().order}},recipient:"snapshot@example.invalid",organization:1,unit:2,occasion:3,order_id:4,lease_token:"lease",attempt_id:"attempt",prepared:null});
   assertEquals((result.prepared.html.match(/#pay=/g)||[]).length,1,"one CTA across legacy balance, body and wrapper");
   assertStringIncludes(result.prepared.html,method==="orchard"?"Orchard":"Gateway "+method);
   assertEquals(result.prepared.attachments.length,0);
  }
  method="bank";status="open";allowed=true;price=100;paid=20;
  for(currency of ["CZK","EUR","USD"]) {
   for(const [kind,code] of [["order_confirmation","TICKET_ORDER_CONFIRMATION"],["order_update","TICKET_ORDER_UPDATE"],["order_payment_notice","TICKET_ORDER_PAYMENT_DONE"],["order_reminder","TICKET_ORDER_REMINDER"]]) {
    const result=await renderQueuedEmail({message_id:"message",message_kind:kind,code,data:{lang:"cs",ticket_order:{order:details().order}},recipient:"snapshot@example.invalid",organization:1,unit:2,occasion:3,order_id:4,lease_token:"lease",attempt_id:"attempt",prepared:null});
    assertEquals(result.prepared.attachments.length,currency==="USD"?0:1,kind+"/"+currency);
    assert(!result.prepared.html.includes("#pay="));
   }
  }
  for(currency of ["CZK","EUR"]) {
   method="bank";status="open";allowed=false;price=0;paid=0;
   const rendered=await getTicketOrderConfirmationTemplate({data:{lang:"cs",ticket_order:{order:details().order}}});
   assertEquals(rendered.attachments.length,0);
   assert(!JSON.stringify(rendered.subs).includes(bank.account_number));
  }
 } finally {supabaseAdmin.rpc=originalRpc;paymentRegistry.resolve=originalResolve;paymentRegistry.has=originalHas;globalThis.fetch=originalFetch;}
});
