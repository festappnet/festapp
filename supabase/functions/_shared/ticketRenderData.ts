import { getMinimalisticDateRange } from './ticketDate.ts';
import type { Template } from './ticketLayout.ts';
import { formatCurrency } from './utilities.ts';
export type RenderData = Record<string,string|null>;
export interface PreviewProduct {
  id:number; product_type:number; title:string; short_title?:string|null;
  data?:{short_title?:string}|null; price:number; currency_code:string;
  order?:number|null; is_hidden?:boolean|null;
}
export interface CatalogType {id:number;occasion:number;title:string;offered:boolean;referenced:boolean;forms?:{title:string;fieldTitle:string;hidden:boolean}[];admission?:boolean;hasVisibleProducts?:boolean;example:{id:number;value:string;price:number|null;currency_code:string|null;currency_symbol:string|null}|null}
export interface ProductCatalog {types:Map<number,CatalogType>;products:Map<number,PreviewProduct>}
export const sampleSymbol='X3827K6M8R';
export const sampleQr='festapp-preview:'+sampleSymbol;
const text=(v:unknown):string|null=>typeof v==='string'&&v.trim()?v.trim().slice(0,2048):null;
export function productValue(p:PreviewProduct):string|null {return text(p.short_title)??text(p.data?.short_title)??text(p.title);}
export function formatProduct(label:string,value:string|null):string|null {return value?(label.trim()?label.trim()+': '+value:value):null;}
export function indexProductCatalog(raw:any,occasionId:number):ProductCatalog {
  if(!raw||!Array.isArray(raw.product_types)||!Array.isArray(raw.products))throw new Error('ticket_catalog_invalid');
  const products=new Map<number,PreviewProduct>();
  const types=new Map<number,CatalogType>(raw.product_types.map((t:any)=> {
    if(!Number.isSafeInteger(t.id)||t.id<=0||t.occasion!==occasionId)throw new Error('ticket_catalog_cross_occasion');
    return [t.id,{id:t.id,occasion:t.occasion,title:text(t.title)??text(t.forms?.[0]?.fieldTitle)??'Skupina produktů',admission:t.admission===true,offered:t.offered===true,referenced:t.referenced===true,forms:t.forms??[],hasVisibleProducts:false,example:null}];
  }));
  for(const p of [...raw.products].sort((a,b)=>(a.order??0)-(b.order??0)||a.id-b.id)) {
    const type=types.get(p.product_type);if(!type)throw new Error('ticket_catalog_product_type_missing');
    products.set(p.id,p);if(!p.is_hidden)type.hasVisibleProducts=true;
    const value=productValue(p);
    const currency=/^[A-Z]{3}$/.test(p.currency_code)?p.currency_code:null;
    if(!p.is_hidden&&value&&!type.example)type.example={id:p.id,value,price:Number.isFinite(p.price)&&p.price>=0?p.price:null,currency_code:currency,currency_symbol:currency?new Intl.NumberFormat('cs-CZ',{style:'currency',currency,minimumFractionDigits:0,maximumFractionDigits:0}).formatToParts(0).find(part=>part.type==='currency')!.value:null};
  }
  return {types,products};
}
export function validateProductReferences(t:Template,c:ProductCatalog) {
  for(const e of t.elements)if(e.binding==='productType'&&!c.types.has(e.productTypeId!))throw new Error('ticket_product_type_missing:'+e.id);
}
export function normalizeTicketData(ticket:any,occasion:any,order:any={},catalog?:ProductCatalog,template?:Template):RenderData {
  if(ticket.occasion!=null&&ticket.occasion!==occasion.id)throw new Error('ticket_cross_occasion');
  const opts=[...(ticket.order_product_ticket??[])].sort((a,b)=>Number(a.id)-Number(b.id));
  const matches=new Map<number,string|null>();
  for(const opt of opts) {
    if(opt.product==null) {if(ticket.state==='storno')continue;if(catalog)throw new Error('ticket_product_missing');continue;}
    if(!catalog)continue;
    const p=catalog.products.get(opt.product);
    if(!p)throw new Error('ticket_product_missing:'+opt.product);
    if(!matches.has(p.product_type))matches.set(p.product_type,productValue(p));
  }
  const spot=opts.find(o=>text(o.spot_group_title));
  let date='';
  if(occasion.start_time) {
    const start=new Date(occasion.start_time),end=new Date(occasion.end_time||occasion.start_time);
    if(Number.isFinite(start.getTime())&&Number.isFinite(end.getTime()))date=getMinimalisticDateRange(start,end);
  }
  const d:RenderData={qr:ticket.ticket_symbol,ticketSymbol:ticket.ticket_symbol,spotGroup:spot?`Stůl: ${text(spot.spot_group_title)}`:null,note:text(ticket.note)?`Poznámka: ${text(ticket.note)}`:null,price:ticket.price!=null?`Cena: ${formatCurrency(ticket.price,ticket.currency_code||'CZK')}`:null,occasionTitle:text(occasion.title),occasionDatePlace:text([date,occasion.data?.place_name].filter(Boolean).join(', ')),orderName:text([text(order.name),text(order.surname)].filter(Boolean).join(' ')),logo:null,footer:`Vstupenka je nepřenosná${occasion.data?.link?' • '+occasion.data.link:''}`};
  if(!template)return d;
  if(catalog)validateProductReferences(template,catalog);
  return Object.fromEntries(template.elements.map(e=>[e.id,e.binding==='productType'?formatProduct(e.label!,matches.get(e.productTypeId!)??null):d[e.binding]]));
}
export function sampleData(scenario='normal',occasion?:any,catalog?:ProductCatalog,template?:Template):RenderData {
  const d=normalizeTicketData({ticket_symbol:sampleSymbol,note:null,price:null,currency_code:'CZK',order_product_ticket:[]},occasion??{title:'Slavnostní večer',start_time:'2026-10-01T18:00:00Z',data:{place_name:'Kulturní dům'}},{name:'Jana',surname:'Nováková'});
  if(Number.isSafeInteger(occasion?.organization)&&Number.isSafeInteger(occasion?.id)) {
    const suffix=(id:number)=>String(id%100).padStart(2,'0').replaceAll('0','X');
    d.ticketSymbol=suffix(occasion.organization)+suffix(occasion.id)+'7K6M8R';
  }
  d.qr='festapp-preview:'+d.ticketSymbol;
  d.spotGroup='Stůl: 12';
  if(scenario==='long') {d.note='Poznámka: '+('Dlouhý český text s diakritikou a velmiDlouhýmSlovemBezMezer ').repeat(8);d.orderName='Kateřina Šťastná Nováková';}
  if(scenario==='missing'){d.note=null;d.spotGroup=null;d.orderName=null;}
  if(!template)return d;
  if(catalog)validateProductReferences(template,catalog);
  const selected=new Map<number,CatalogType['example']>();
  const baseline=[...(catalog?.types.values()??[])].filter(t=>t.admission&&t.example).sort((a,b)=>a.id-b.id)[0]?.example;
  if(baseline)selected.set(baseline.id,baseline);
  for(const e of template.elements)if(e.binding==='productType'&&scenario!=='missing') {
    const example=catalog?.types.get(e.productTypeId!)?.example;
    if(example)selected.set(example.id,example);
  }
  const examples=[...selected.values()].filter((e):e is NonNullable<CatalogType['example']>=>!!e);
  const currencies=new Set(examples.map(e=>e.currency_code));
  if(examples.length&&currencies.size===1&&examples.every(e=>e.price!=null&&e.currency_code!=null))d.price='Cena: '+formatCurrency(examples.reduce((sum,e)=>sum+Math.round(e.price!*100),0)/100,examples[0].currency_code!);
  return Object.fromEntries(template.elements.map(e=>[e.id,e.binding==='productType'?formatProduct(e.label!,scenario==='missing'?null:catalog?.types.get(e.productTypeId!)?.example?.value??null):d[e.binding]]));
}
