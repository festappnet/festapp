import { getMinimalisticDateRange } from './ticketDate.ts';
import type { Binding } from './ticketLayout.ts';
import { formatCurrency } from './utilities.ts';
export type RenderData = Record<Binding,string|null>;
export interface PreviewProduct {
  id: number;
  type: string;
  title: string;
  data?: { short_title?: string } | null;
  price: number;
  currency_code: string;
  is_hidden?: boolean | null;
}
// An illustrative code with the production ten-character shape. Never reuse a
// customer's admission credential in a preview's QR payload.
export const sampleSymbol='X3827K6M8R';
export const sampleQr='festapp-preview:'+sampleSymbol;
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
export function sampleData(scenario='normal',occasion?:any,products:PreviewProduct[]=[]):RenderData {
  const d=normalizeTicketData({ticket_symbol:sampleSymbol,note:null,price:370,currency_code:'CZK',order_product_ticket:[{id:1,spot_group_title:'12'},{id:2,product_type:'food',product_title:'Steak z panenky + štouch. brambory'}]},{title:'Slavnostní večer',start_time:'2026-10-01T18:00:00Z',data:{place_name:'Kulturní dům'}},{name:'Jana',surname:'Nováková'});
  const offered=products.filter(p=>!p.is_hidden && p.title?.trim() &&
    Number.isFinite(p.price) && p.price>=0 && /^[A-Z]{3}$/.test(p.currency_code))
    .sort((a,b)=>a.id-b.id);
  const admission=offered.find(p=>p.type==='spot')??offered.find(p=>p.type!=='food');
  const currency=admission?.currency_code??offered[0]?.currency_code;
  const food=offered.find(p=>p.type==='food' && p.currency_code===currency);
  const selected=[admission,food].filter((p):p is PreviewProduct=>p!==undefined);
  if(selected.length) {
    const real=normalizeTicketData({ticket_symbol:sampleSymbol,
      price:selected.reduce((sum,p)=>sum+Math.round(p.price*100),0)/100,
      currency_code:currency,
      order_product_ticket:food?[{id:food.id,product_type:'food',
        product_title:food.data?.short_title?.trim()||food.title}]:[]},{});
    d.food=real.food;
    d.price=real.price;
  }
  if(Number.isSafeInteger(occasion?.organization) && Number.isSafeInteger(occasion?.id)) {
    const suffix=(id:number)=>String(id%100).padStart(2,'0').replaceAll('0','X');
    d.ticketSymbol=suffix(occasion.organization)+suffix(occasion.id)+'7K6M8R';
  }
  d.qr='festapp-preview:'+d.ticketSymbol;
  if(scenario==='long') { d.note='Poznámka: '+('Dlouhý český text s diakritikou a velmiDlouhýmSlovemBezMezer ').repeat(8);d.occasionTitle='Slavnostní setkání přátel a příznivců kulturního života';d.orderName='Kateřina Šťastná Nováková'; }
  if(scenario==='missing') {d.food=null;d.note=null;d.spotGroup=null;d.orderName=null;}
  if(occasion) {
    const known=normalizeTicketData({ticket_symbol:sampleSymbol},occasion);
    for(const binding of ['occasionTitle','occasionDatePlace','footer'] as const)if(known[binding])d[binding]=known[binding];
  }
  return d;
}
