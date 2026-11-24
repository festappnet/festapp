import { formatTicketCurrency } from './numberFormatting.ts';
import { getMinimalisticDateRange } from './ticketDate.ts';
import type { Template } from './ticketLayout.ts';
// BEGIN GENERATED SEATING LABELS
type SeatingLabels = Record<"table" | "group" | "couch" | "row" | "standingPlace" | "seat", string>;
const seatText: Record<string, SeatingLabels> = {
  "cs": {
    "table": "Stůl",
    "group": "Skupina",
    "couch": "Gauč",
    "row": "Řada",
    "standingPlace": "Místo na stání",
    "seat": "Místo"
  },
  "de": {
    "table": "Tisch",
    "group": "Gruppe",
    "couch": "Sofa",
    "row": "Reihe",
    "standingPlace": "Stehplatz",
    "seat": "Sitzplatz"
  },
  "en": {
    "table": "Table",
    "group": "Group",
    "couch": "Couch",
    "row": "Row",
    "standingPlace": "Standing place",
    "seat": "Seat"
  },
  "es": {
    "table": "Mesa",
    "group": "Grupo",
    "couch": "Sofá",
    "row": "Fila",
    "standingPlace": "Lugar de pie",
    "seat": "Asiento"
  },
  "pl": {
    "table": "Stół",
    "group": "Grupa",
    "couch": "Kanapa",
    "row": "Rząd",
    "standingPlace": "Miejsce stojące",
    "seat": "Miejsce"
  },
  "sk": {
    "table": "Stôl",
    "group": "Skupina",
    "couch": "Gauč",
    "row": "Rad",
    "standingPlace": "Miesto na státie",
    "seat": "Miesto"
  },
  "uk": {
    "table": "Стіл",
    "group": "Група",
    "couch": "Диван",
    "row": "Ряд",
    "standingPlace": "Стояче місце",
    "seat": "Місце"
  }
};

export function seatingLabels(locale: string) {
  return Object.hasOwn(seatText, locale) ? seatText[locale] : seatText.en;
}

export const walletSeatingLabels = {
  "table": "Stůl / Table",
  "group": "Skupina / Group",
  "couch": "Gauč / Couch",
  "row": "Řada / Row",
  "standingPlace": "Místo na stání / Standing place",
  "seat": "Místo / Seat"
};

function formatSeatingGroup(labels: SeatingLabels, kind: unknown, value: unknown): string | null {
  const name = typeof value === "string" ? value.trim() : "";
  const label = kind === "standing" ? labels.standingPlace
    : kind === "table" ? labels.table : kind === "couch" ? labels.couch
    : kind === "row" ? labels.row : /^\d+$/u.test(name) ? labels.group : null;
  if (!name) return label;
  if (!label) return name;
  const normalized = name.toLocaleLowerCase();
  const prefix = label.toLocaleLowerCase();
  if (normalized === prefix || normalized.startsWith(prefix + " ") ||
      normalized.startsWith(prefix + ":")) return name;
  return `${label} ${name}`;
}
// END GENERATED SEATING LABELS

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
export function indexProductCatalog(raw:any,occasionId:number,allowDraftIds=false):ProductCatalog {
  if(!raw||!Array.isArray(raw.product_types)||!Array.isArray(raw.products))throw new Error('ticket_catalog_invalid');
  const products=new Map<number,PreviewProduct>();
  const types=new Map<number,CatalogType>(raw.product_types.map((t:any)=> {
    if(!Number.isSafeInteger(t.id)||t.id===0||(!allowDraftIds&&t.id<0)||t.occasion!==occasionId)throw new Error('ticket_catalog_cross_occasion');
    return [t.id,{id:t.id,occasion:t.occasion,title:text(t.title)??text(t.forms?.[0]?.fieldTitle)??'Skupina produktů',admission:t.admission===true,offered:t.offered===true,referenced:t.referenced===true,forms:t.forms??[],hasVisibleProducts:false,example:null}];
  }));
  for(const p of [...raw.products].sort((a,b)=>(a.order??0)-(b.order??0)||a.id-b.id)) {
    const type=types.get(p.product_type);if(!type)throw new Error('ticket_catalog_product_type_missing');
    products.set(p.id,p);if(!p.is_hidden)type.hasVisibleProducts=true;
    const value=productValue(p);
    const currency=/^[A-Z]{3}$/.test(p.currency_code)?p.currency_code:null;
    const positivePrice=Number.isFinite(p.price)&&p.price>0;
    if(!p.is_hidden&&value&&(!type.example||(positivePrice&&!(type.example.price!=null&&type.example.price>0))))type.example={id:p.id,value,price:Number.isFinite(p.price)&&p.price>=0?p.price:null,currency_code:currency,currency_symbol:currency?new Intl.NumberFormat('cs-CZ',{style:'currency',currency,minimumFractionDigits:0,maximumFractionDigits:0}).formatToParts(0).find(part=>part.type==='currency')!.value:null};
  }
  return {types,products};
}
export function validateProductReferences(t:Template,c:ProductCatalog) {
  for(const e of t.elements)if(e.binding==='productType'&&!c.types.has(e.productTypeId!))throw new Error('ticket_product_type_missing:'+e.id);
}
/** One deterministic seating selection for PDF, native Wallet passes and email. */
export type TicketSeating = {
  table: string | null;
  seat: string | null;
  kind?: 'table' | 'couch' | 'row' | 'standing';
};

export function ticketSeating(ticket: any): TicketSeating {
  const selected = [...(ticket.order_product_ticket ?? [])]
    .sort((a,b) => Number(a.id ?? 0) - Number(b.id ?? 0))
    .find(p => p.is_standing === true || text(p.spot_group_title) || text(p.spot_title) ||
      ['table', 'couch', 'row'].includes(p.spot_group_kind));
  if (selected?.is_standing === true) {
    return { table: text(selected.standing_area_title), seat: null, kind: 'standing' };
  }
  const kind = selected?.spot_group_kind;
  return {
    table: text(selected?.spot_group_title), seat: text(selected?.spot_title),
    ...(['table', 'couch', 'row'].includes(kind) ? { kind } : {}),
  };
}

export function seatingGroupText(seating: TicketSeating, locale: string): string | null {
  return formatSeatingGroup(seatingLabels(locale), seating.kind, seating.table);
}

export function walletSeatingGroup(seating: TicketSeating): { label: string; value: string } | null {
  const key = seating.kind === 'standing' ? 'standingPlace' : seating.kind ?? 'group';
  const label = walletSeatingLabels[key];
  if (!seating.table) {
    return seating.kind ? { label: 'Místo / Location', value: label } : null;
  }
  for (const locale of ['cs', 'en']) {
    const prefix = seatingLabels(locale)[key];
    const value = seating.table;
    if (value.toLocaleLowerCase() === prefix.toLocaleLowerCase()) {
      return { label: 'Místo / Location', value: label };
    }
    if (value.toLocaleLowerCase().startsWith(prefix.toLocaleLowerCase() + ' ') ||
        value.toLocaleLowerCase().startsWith(prefix.toLocaleLowerCase() + ':')) {
      const remainder = value.slice(prefix.length).replace(/^:?\s*/u, '');
      return remainder ? { label, value: remainder } : { label: 'Místo / Location', value: label };
    }
  }
  return { label, value: seating.table };
}

export function ticketShowsSeat(feature:any):boolean {
 const type=feature?.ticket_type==='named'?'named':'wide';
 return feature?.layout?.templates?.[type]?.spotGroupAppearance?.showSeat===true;
}
export function normalizeTicketData(ticket:any,occasion:any,order:any={},catalog?:ProductCatalog,template?:Template):RenderData {
  if(ticket.occasion!=null&&ticket.occasion!==occasion.id)throw new Error('ticket_cross_occasion');
  const locale = ['cs','en','de','pl','sk','uk'].includes(occasion.locale) ? occasion.locale : 'cs';
  const en = locale === 'en';
  const opts=[...(ticket.order_product_ticket??[])].sort((a,b)=>Number(a.id)-Number(b.id));
  const matches=new Map<number,string|null>();
  for(const opt of opts) {
    if(opt.product==null) {if(ticket.state==='storno')continue;if(catalog)throw new Error('ticket_product_missing');continue;}
    if(!catalog)continue;
    const p=catalog.products.get(opt.product);
    if(!p)throw new Error('ticket_product_missing:'+opt.product);
    if(!matches.has(p.product_type))matches.set(p.product_type,productValue(p));
  }
  const seating=ticketSeating(ticket);
  const labels=seatingLabels(locale);
  let timeZone=occasion.data?.timezone||'Europe/Prague';
  try { new Intl.DateTimeFormat(locale,{timeZone}); } catch { timeZone='Europe/Prague'; }
  let date='';
  if(occasion.start_time) {
    const start=new Date(occasion.start_time),end=new Date(occasion.end_time||occasion.start_time);
    if(Number.isFinite(start.getTime())&&Number.isFinite(end.getTime()))date=getMinimalisticDateRange(start,end,locale,timeZone);
  }
  let startTime:string|null=null;
  if(occasion.start_time && Number.isFinite(new Date(occasion.start_time).getTime())) {
    const options:Intl.DateTimeFormatOptions={hour:'2-digit',minute:'2-digit',hourCycle:'h23',timeZone};
    try {startTime=new Intl.DateTimeFormat(locale,options).format(new Date(occasion.start_time));}
    catch {startTime=new Intl.DateTimeFormat(locale,{...options,timeZone:'Europe/Prague'}).format(new Date(occasion.start_time));}
  }
  const d:RenderData={qr:ticket.ticket_symbol,ticketSymbol:ticket.ticket_symbol,spotGroup:seatingGroupText(seating,locale),note:text(ticket.note)?`${en ? 'Note' : 'Poznámka'}: ${text(ticket.note)}`:null,price:ticket.price!=null?`${en ? 'Price' : 'Cena'}: ${formatTicketCurrency(ticket.price,ticket.currency_code||'CZK',locale)}`:null,occasionTitle:text(occasion.title),occasionStartTime:startTime,occasionPlace:text(occasion.data?.place_name),occasionDatePlace:text([date,occasion.data?.place_name].filter(Boolean).join(', ')),orderName:text([text(order.name),text(order.surname)].filter(Boolean).join(' ')),logo:null,footer:`${occasion.demo_read_only===true?(en?'DEMO - NOT VALID FOR ADMISSION • ':'UKÁZKA - NEPLATÍ PRO VSTUP • '):''}${en?'This ticket is non-transferable':'Vstupenka je nepřenosná'}${occasion.data?.link?' • '+occasion.data.link:''}`};
  d.spotGroupWithSeat=seating.seat?[d.spotGroup,`${labels.seat}: ${seating.seat}`].filter(Boolean).join(', '):d.spotGroup;
  if(!template)return d;
  if(catalog)validateProductReferences(template,catalog);
  return Object.fromEntries(template.elements.map(e=>[e.id,e.binding==='text'?e.text!:e.binding==='productType'?formatProduct(e.label!,matches.get(e.productTypeId!)??null):e.binding==='spotGroup'&&template.spotGroupAppearance?.showSeat?d.spotGroupWithSeat:d[e.binding]]));
}
export function sampleData(scenario='normal',occasion?:any,catalog?:ProductCatalog,template?:Template):RenderData {
  const d=normalizeTicketData({ticket_symbol:sampleSymbol,note:null,price:null,currency_code:'CZK',order_product_ticket:[]},occasion??{title:'Slavnostní večer',start_time:'2026-10-01T18:00:00Z',data:{place_name:'Kulturní dům'}},{name:'Jana',surname:'Nováková'});
  if(Number.isSafeInteger(occasion?.organization)&&Number.isSafeInteger(occasion?.id)) {
    const suffix=(id:number)=>String(id%100).padStart(2,'0').replaceAll('0','X');
    d.ticketSymbol=suffix(occasion.organization)+suffix(occasion.id)+'7K6M8R';
  }
  d.qr='festapp-preview:'+d.ticketSymbol;
  const en = occasion?.locale === 'en';
  const labels=seatingLabels(occasion?.locale || 'cs');
  d.spotGroup=seatingGroupText({kind:'table',table:'12',seat:null},occasion?.locale || 'cs');
  d.spotGroupWithSeat=`${d.spotGroup}, ${labels.seat}: 3`;
  if(en) { d.orderName='Alex Morgan'; if(!occasion?.title)d.occasionTitle='Evening under the stars'; }
  if(scenario==='long') {d.note=en?'Note: '+('A long guest note with anExtraLongWordWithoutSpaces ').repeat(8):'Poznámka: '+('Dlouhý český text s diakritikou a velmiDlouhýmSlovemBezMezer ').repeat(8);d.orderName=en?'Alexandra Morgan Taylor':'Kateřina Šťastná Nováková';}
  if(scenario==='missing'){d.note=null;d.spotGroup=null;d.spotGroupWithSeat=null;d.orderName=null;}
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
  if(examples.length&&currencies.size===1&&examples.every(e=>e.price!=null&&e.currency_code!=null))d.price=(en?'Price: ':'Cena: ')+formatTicketCurrency(examples.reduce((sum,e)=>sum+Math.round(e.price!*100),0)/100,examples[0].currency_code!,en?'en':'cs-CZ');
  return Object.fromEntries(template.elements.map(e=>[e.id,e.binding==='text'?e.text!:e.binding==='productType'?formatProduct(e.label!,scenario==='missing'?null:catalog?.types.get(e.productTypeId!)?.example?.value??null):e.binding==='spotGroup'&&template.spotGroupAppearance?.showSeat?d.spotGroupWithSeat:d[e.binding]]));
}
