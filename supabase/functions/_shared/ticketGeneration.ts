import * as fontkit from 'npm:fontkit';
import { drawLayoutTicket } from './generateTicket.ts';
import { importTicketTemplate } from './ticketTemplateImport.ts';
import { validateLayout, pdfBox, type Template, type TicketLayout } from './ticketLayout.ts';
import { normalizeTicketData, type RenderData } from './ticketRenderData.ts';
import { type FontMetrics } from './ticketText.ts';
import { fetchPublicImage, UnsafeTargetError } from '../fetch-http-data/safeFetch.ts';
const fontFiles:Record<string,string>={futura:'font.ttf',robotoSlab:'roboto-slab.ttf',roboto:'roboto.ttf',russoOne:'russo-one.ttf'};
export const fontBytes=(name='futura')=>{
  if(!Object.hasOwn(fontFiles,name))throw new Error('Unknown ticket font');
  return Deno.readFile(new URL('./ticket-assets/'+fontFiles[name],import.meta.url));
};
export function fontMetrics(bytes:Uint8Array):FontMetrics {
  const f=fontkit.create(bytes);const advances:Record<string,number>={};
  for(const c of f.characterSet) advances[String.fromCodePoint(c)]=f.glyphForCodePoint(c).advanceWidth/f.unitsPerEm;
  return {advances,ascent:f.ascent/f.unitsPerEm,descent:f.descent/f.unitsPerEm};
}
export interface TicketFont {font:Uint8Array;metrics:FontMetrics}
export const ticketFonts={futura:'Futura PT',robotoSlab:'Roboto Slab',roboto:'Roboto',russoOne:'Russo One'};
export interface Resources { fonts?:Record<string,TicketFont>; font:Uint8Array; metrics:FontMetrics; background?:Uint8Array; missingBackground?:boolean; logo?:Uint8Array; productTypeMap?:any }
export async function loadLayoutResources(occasion:any,featureOverride?:any,options:{allowMissingBackground?:boolean}={},readImage=fetchPublicImage):Promise<Resources> {
  const feature=featureOverride??occasion.features?.find((f:any)=>f.code==='ticket');
  const type=feature?.ticket_type==='named'?'named':'wide';
  const template=feature?.layout?.templates?.[type];
  const namedFont=occasion.data?.font==='https://fonts.cdnfonts.com/s/15876/RussoOne-Regular.woff'?'russoOne':'roboto';
  if(!template && type==='named' && occasion.data?.font && !['https://fonts.cdnfonts.com/s/12165/Roboto-Regular.woff','https://fonts.cdnfonts.com/s/15876/RussoOne-Regular.woff'].includes(occasion.data.font))throw new Error('Ticket font requires import');
  const font=await fontBytes(template ? (template.font??'futura') : (type==='named'?namedFont:'robotoSlab'));
  const read=async(url:string)=> (await readImage(url)).bytes;
  const backgroundUrl=template?feature?.background:type==='named'?null:feature?.background;
  let backgroundBytes:Uint8Array|undefined;
  let missingBackground=false;
  if(backgroundUrl) {
    try { backgroundBytes=await read(backgroundUrl); }
    catch(error) {
      // Only the editor can recover from a confirmed deleted image. Downloads
      // and PDF previews must never silently produce a different ticket.
      if(options.allowMissingBackground && error instanceof UnsafeTargetError &&
          ['upstream_404','upstream_410'].includes(error.message)) missingBackground=true;
      else throw error;
    }
  }
  const fonts=Object.fromEntries(await Promise.all(Object.keys(ticketFonts).map(async name=>{const font=await fontBytes(name);return [name,{font,metrics:fontMetrics(font)}];})));
  return {font,metrics:fontMetrics(font),fonts,background:backgroundBytes,missingBackground,logo:occasion.data?.logo?await read(occasion.data.logo):undefined};
}
export function activeTemplate(occasion:any):Template|undefined {
  const f=occasion.features?.find((f:any)=>f.code==='ticket');
  if(f?.layout==null)return undefined;
  validateLayout(f.layout);
  return (f.layout as TicketLayout).templates[f.ticket_type==='named'?'named':'wide'];
}
export async function resolveTicketTemplate(occasion:any,resources:Resources):Promise<Template> {
  return activeTemplate(occasion) ?? await importTicketTemplate(occasion,resources);
}
export async function prepareTicketRenderer(occasion:any,_ticket:any,order:any={}, dependencies = {
  load: loadLayoutResources,
  products: async(id:number)=>{
    const { supabaseAdmin } = await import('./supabaseUtil.ts');
    const {data,error}=await supabaseAdmin.rpc('get_products_and_types',{p_occasion_id:id});if(error)throw new Error('Failed to load ticket products');return data;
  }
}) {
  const resources=await dependencies.load(occasion);
  const template=await resolveTicketTemplate(occasion,resources);
  const products=await dependencies.products(occasion.id);
  const types=new Map((products?.product_types??[]).map((p:any)=>[p.id,p.type]));
  resources.productTypeMap={};
  for(const product of products?.products??[]) {const type=String(types.get(product.product_type));(resources.productTypeMap[type]??={})[product.id]=product;}
  return async(t:any)=>generateTicketPdf(normalizeTicketData(t,occasion,order,resources.productTypeMap),resources,template);
}
export async function generateTicketPdf(data:RenderData,r:Resources,t:Template,type:'wide'|'named'=t.page.width===595.28?'wide':'named',sample=false) {
  const selected=r.fonts?.[t.font??'futura'];
  return await drawLayoutTicket(data,selected?{...r,...selected}:r,t,type,sample);
}
