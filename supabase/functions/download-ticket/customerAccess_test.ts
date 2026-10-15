import { assertEquals } from 'jsr:@std/assert@1';
import { authorizeCustomerTicket } from './customerAccess.ts';
const token = 'a'.repeat(64);
const request = { token, orderId: 1, ticketId: 7 };
const overview = () => ({ code: 200, root: { hasTickets: true }, orders: [{ state: 'sent', tickets: [{ id: 7, rawState: 'sent' }] }] });
Deno.test('customer download requires a well-formed capability before any read', async () => {
 for (const input of [{ticketId:7}, {...request,token:'bad'}, {...request,orderId:0}, {...request,ticketId:-1}, {...request,ticketId:1.5}]) {
  assertEquals(await authorizeCustomerTicket(input, () => { throw new Error('Unexpected read'); }), false);
 }
});
Deno.test('customer download uses the exact root token and requires ownership and issued state', async () => {
 assertEquals(await authorizeCustomerTicket(request, async (t,id) => { assertEquals(t,token);assertEquals(id,1);return {data:overview(),error:null}; }),true);
 for (const state of ['paid','sent','used']) {
  const data=overview();data.orders[0].tickets[0].rawState=state;
  assertEquals(await authorizeCustomerTicket(request,async()=>({data,error:null})),true);
 }
 for (const mutate of [
  (d:any)=>d.code=403,
  (d:any)=>d.root.hasTickets=false,
  (d:any)=>d.orders[0].state='storno',
  (d:any)=>d.orders[0].state='ordered',
  (d:any)=>d.orders[0].tickets[0].id=8,
  (d:any)=>d.orders[0].tickets[0].rawState='ordered',
  (d:any)=>d.orders[0].tickets[0].rawState='storno',
  (d:any)=>d.orders[0].tickets[0].rawState='waitlisted',
 ]) {
  const data=overview();mutate(data);
  assertEquals(await authorizeCustomerTicket(request,async()=>({data,error:null})),false);
 }
 assertEquals(await authorizeCustomerTicket(request,async()=>({data:overview(),error:{message:'denied'}})),false);
});
