import { getMinimalisticDateRange } from './ticketDate.ts';
import type { Binding } from './ticketLayout.ts';
import { formatCurrency } from './utilities.ts';
export type RenderData = Record<Binding,string|null>;
export const sampleSymbol='VZOR:NEPLATNY';
export function normalizeTicketData(ticket:any,occasion:any,order:any={},productTypeMap:any={}):RenderData {
  const opts=[...(ticket.order_product_ticket??[])].sort((a,b)=>Number(a.id)-Number(b.id));
  const text=(v:any)=>typeof v==='string' && v.trim()?v.trim().slice(0,2048):null;
  const food=opts.find(o=>productTypeMap.food?.[o.product] || o.product_type==='food');
  const fp=food && productTypeMap.food?.[food.product];
  const spot=opts.find(o=>text(o.spot_group_title));
  const foodTitle=text(fp?.short_title||fp?.data?.short_title||fp?.title||food?.short_title||food?.product_title);
  let date='';
  if(occasion.start_time) {
    const start=new Date(occasion.start_time),end=new Date(occasion.end_time||occasion.start_time);
    if(Number.isFinite(start.getTime())&&Number.isFinite(end.getTime())) date=getMinimalisticDateRange(start,end);
  }
  const name=[text(order.name),text(order.surname)].filter(Boolean).join(' ');
  return {qr:ticket.ticket_symbol,ticketSymbol:ticket.ticket_symbol,spotGroup:spot?`Stůl: ${text(spot.spot_group_title)}`:null,food:foodTitle?`Večeře: ${foodTitle}`:null,note:text(ticket.note)?`Poznámka: ${text(ticket.note)}`:null,price:ticket.price!=null?`Cena: ${formatCurrency(ticket.price,ticket.currency_code||'CZK')}`:null,occasionTitle:text(occasion.title),occasionDatePlace:text([date,occasion.data?.place_name].filter(Boolean).join(', ')),orderName:text(name),logo:null,footer:`Vstupenka je nepřenosná${occasion.data?.link?' • '+occasion.data.link:''}`};
}
export function sampleData(scenario='normal',occasion?:any):RenderData {
  const d=normalizeTicketData({ticket_symbol:sampleSymbol,note:'Příjemný večer',price:0,currency_code:'CZK',order_product_ticket:[{id:1,spot_group_title:'Stůl 12'},{id:2,product_type:'food',product_title:'Slavnostní večeře'}]},{title:'Slavnostní večer',start_time:'2026-10-01T18:00:00Z',data:{place_name:'Kulturní dům'}},{name:'Jana',surname:'Nováková'});
  if(scenario==='long') { d.note='Poznámka: '+('Dlouhý český text s diakritikou a velmiDlouhýmSlovemBezMezer ').repeat(8);d.occasionTitle='Slavnostní setkání přátel a příznivců kulturního života';d.orderName='Kateřina Šťastná Nováková'; }
  if(scenario==='missing') {d.food=null;d.note=null;d.spotGroup=null;d.orderName=null;}
  if(occasion) {
    const known=normalizeTicketData({ticket_symbol:sampleSymbol},occasion);
    for(const binding of ['occasionTitle','occasionDatePlace','footer'] as const)if(known[binding])d[binding]=known[binding];
  }
  return d;
}

