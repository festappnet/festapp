import * as fontkit from 'npm:fontkit';
import { generateTicketImage,fetchTicketResources } from './generateTicket.ts';
import { generateNamedTicketImage,fetchNamedTicketResources } from './generateNamedTicket.ts';
import { validateLayout, pdfBox, type Template, type TicketLayout } from './ticketLayout.ts';
import { normalizeTicketData, type RenderData } from './ticketRenderData.ts';
import { type FontMetrics } from './ticketText.ts';
import { supabaseAdmin } from './supabaseUtil.ts';
import { fetchPublicImage } from '../fetch-http-data/safeFetch.ts';
export const fontBytes=()=>Deno.readFile(new URL('./ticket-assets/font.ttf',import.meta.url));
export function fontMetrics(bytes:Uint8Array):FontMetrics {
  const f=fontkit.create(bytes);const advances:Record<string,number>={};
  for(const c of f.characterSet) advances[String.fromCodePoint(c)]=f.glyphForCodePoint(c).advanceWidth/f.unitsPerEm;
  return {advances,ascent:f.ascent/f.unitsPerEm,descent:f.descent/f.unitsPerEm};
}
export interface Resources { font:Uint8Array; metrics:FontMetrics; background?:Uint8Array; logo?:Uint8Array; productTypeMap?:any }
export async function loadLayoutResources(occasion:any,featureOverride?:any):Promise<Resources> {
  const feature=featureOverride??occasion.features?.find((f:any)=>f.code==='ticket');
  const font=await fontBytes();
  const read=async(url:string)=> (await fetchPublicImage(url)).bytes;
  const background=feature?.ticket_type==='named'?undefined:feature?.background;
  const backgroundBytes=feature?.ticket_type==='named'?undefined:background?await read(background):undefined;
  return {font,metrics:fontMetrics(font),background:backgroundBytes,logo:occasion.data?.logo?await read(occasion.data.logo):undefined};
}
export function activeTemplate(occasion:any):Template|undefined {
  const f=occasion.features?.find((f:any)=>f.code==='ticket');
  if(f?.layout==null)return undefined;
  validateLayout(f.layout);
  return (f.layout as TicketLayout).templates[f.ticket_type==='named'?'named':'wide'];
}
export async function prepareTicketRenderer(occasion:any,ticket:any,order:any={}, dependencies = {
  load: loadLayoutResources, wide: fetchTicketResources, named: fetchNamedTicketResources,
  products: async(id:number)=>{ const {data,error}=await supabaseAdmin.rpc('get_products_and_types',{p_occasion_id:id});if(error)throw new Error('Failed to load ticket products');return data; }
}) {
  const template=activeTemplate(occasion);
  if(template) {
    const resources=await dependencies.load(occasion);
    const products = await dependencies.products(occasion.id);
    const types=new Map((products?.product_types??[]).map((p:any)=>[p.id,p.type]));
    resources.productTypeMap={};
    for(const product of products?.products??[]) {const type=String(types.get(product.product_type));(resources.productTypeMap[type]??={})[product.id]=product;}
    return async(t:any)=>generateTicketPdf(normalizeTicketData(t,occasion,order,resources.productTypeMap),resources,template);
  }
  const named=occasion.features?.find((f:any)=>f.code==='ticket')?.ticket_type==='named';
  const resources=named?await dependencies.named(ticket):await dependencies.wide(ticket);
  return async(t:any)=>({bytes:named?await generateNamedTicketImage(t,resources as any,order,'cs'):await generateTicketImage(t,resources as any),warnings:[] as string[]});
}
export async function generateTicketPdf(data:RenderData,r:Resources,t:Template,type:'wide'|'named'=t.page.width===595.28?'wide':'named',sample=false) {
  const custom={data,resources:r,template:t,type,sample,warnings:[] as string[]};
  const ticket={ticket_symbol:data.ticketSymbol};
  const bytes=type==='named'
    ? await generateNamedTicketImage(ticket,r as any,{},'cs',custom)
    : await generateTicketImage(ticket,r as any,custom);
  return {bytes,warnings:custom.warnings};
}
