import {assertEquals} from 'jsr:@std/assert';
import {prepareFakturoidTicketOrder} from './fakturoidPreparation.ts';
Deno.test('discounted invoice unknown outcome retries the same leased order without abort or new invoice',async()=>{
  const calls:string[]=[];let attempt=0;let gatewayCalls=0;
  const order={id:12,data:{discount:{code:'SAVE',base:100,discount:10,net:90,currency:'CZK'}},payment_info:{amount:90,currency_code:'CZK',variable_symbol:'123456',account_number:'test',account_number_human_readable:'test'}};
  const client={rpc:(name:string,_params:Record<string,unknown>)=>{
    calls.push(name);
    const data=name==='get_external_services' ? [{type:'FAKTUROID',data:{}}] : name==='get_fakturoid_ticket_order_state_v1' ? 'preparing_payment' : name==='claim_replacement_invoice_preparation' ? {status:'claimed',token:'lease',allowCreate:attempt++===0} : name==='complete_replacement_invoice_preparation' ? '123456' : null;
    return Promise.resolve({data,error:null});
  }};
  const gateway={preparePayment:async(args:{allowCreate?:boolean;beforeCreate?:()=>Promise<void>;order:unknown})=>{
    gatewayCalls++;assertEquals(args.order,order);
    if(gatewayCalls===1){assertEquals(args.allowCreate,true);await args.beforeCreate?.();throw Error('transport outcome unknown');}
    assertEquals(args.allowCreate,false);return '123456';
  }};
  assertEquals(await prepareFakturoidTicketOrder({client,gateway,order,commandId:'same-command',unitName:'Event',replacement:false,durable:true}),{ok:false,retrySameCommand:true,reason:'PAYMENT_PREPARATION_PENDING_RETRY_SAME_COMMAND'});
  assertEquals(calls.includes('abort_fakturoid_ticket_order_v1'),false);
  assertEquals(await prepareFakturoidTicketOrder({client,gateway,order,commandId:'same-command',unitName:'Event',replacement:false,durable:true}),{ok:true});
  assertEquals(calls.filter(n=>n==='mark_replacement_invoice_dispatch').length,1);
  assertEquals(calls.filter(n=>n==='complete_replacement_invoice_preparation').length,1);
});
