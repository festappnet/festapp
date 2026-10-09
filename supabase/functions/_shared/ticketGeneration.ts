import { drawLayoutTicket, prepareTicketBackground, type PreparedTicketBackground } from './generateTicket.ts';
import { importTicketTemplate } from './ticketTemplateImport.ts';
import { validateLayout, pdfBox, type Template, type TicketLayout } from './ticketLayout.ts';
import { normalizeTicketData, type RenderData } from './ticketRenderData.ts';
import { type FontMetrics } from './ticketText.ts';
import { fetchPublicImage, UnsafeTargetError } from '../fetch-http-data/safeFetch.ts';
import {futuraId,legacyFontIds,legacyNamedFontId,type TicketFont} from './ticketFonts.ts';
import {resolveTicketFont,parseRegisteredTicketLayout} from './ticketFontStorage.ts';
import {effectiveFontId,layoutFontIds} from './ticketLayout.ts';
export interface Resources { fonts?:Record<string,TicketFont>;registeredIds?:ReadonlySet<string>;font:Uint8Array;metrics:FontMetrics;background?:Uint8Array;preparedBackground?:PreparedTicketBackground;missingBackground?:boolean;logo?:Uint8Array;productTypeMap?:any }
export async function loadLayoutResources(occasion:any,featureOverride?:any,options:{allowMissingBackground?:boolean;legacyFontProtocol?:boolean}={},readImage=fetchPublicImage):Promise<Resources> {
  const feature=featureOverride??occasion.features?.find((f:any)=>f.code==='ticket');
  const type=feature?.ticket_type==='named'?'named':'wide';
  const template=feature?.layout?.templates?.[type];
  const defaultId=template?effectiveFontId(template):type==='named'?legacyNamedFontId(occasion.data?.font):feature?.background?legacyFontIds.robotoSlab:futuraId;
  const ids=new Set<string>([defaultId]);
  if(options.legacyFontProtocol)for(const id of Object.values(legacyFontIds))ids.add(id);
  if(options.allowMissingBackground)ids.add(futuraId); // concurrently rendered preset gallery
  for(const e of template?.elements??[])if(e.visible&&!['qr','logo'].includes(e.binding))ids.add(effectiveFontId(template,e));
  const fonts:Record<string,TicketFont>={};await Promise.all([...ids].map(async id=>{fonts[id]=await resolveTicketFont(id);}));
  const selected=fonts[defaultId];const font=selected.bytes;
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
  return {registeredIds:layoutFontIds(feature?.layout),font,metrics:selected.metrics,fonts,background:backgroundBytes,missingBackground,logo:occasion.data?.logo?await read(occasion.data.logo):undefined};
}
export function activeTemplate(occasion:any,registeredIds?:ReadonlySet<string>):Template|undefined {
  const f=occasion.features?.find((f:any)=>f.code==='ticket');
  if(f?.layout==null)return undefined;
  validateLayout(f.layout,registeredIds);
  return (f.layout as TicketLayout).templates[f.ticket_type==='named'?'named':'wide'];
}
export async function resolveTicketTemplate(occasion:any,resources:Resources):Promise<Template> {
  return activeTemplate(occasion,resources.registeredIds) ?? await importTicketTemplate(occasion,resources);
}
export async function prepareTicketRenderer(occasion:any,_ticket:any,order:any={}, dependencies = {
  load: loadLayoutResources,
  products: async(id:number)=>{
    const { supabaseAdmin } = await import('./supabaseUtil.ts');
    const {data,error}=await supabaseAdmin.rpc('get_products_and_types',{p_occasion_id:id});if(error)throw new Error('Failed to load ticket products');return data;
  }
}) {
  const layout=occasion.features?.find((f:any)=>f.code==='ticket')?.layout;
  if(layout)await parseRegisteredTicketLayout(layout);
  const resources={...await dependencies.load(occasion)};
  if(resources.background)resources.preparedBackground=await prepareTicketBackground(resources.background);
  const template=await resolveTicketTemplate(occasion,resources);
  const products=await dependencies.products(occasion.id);
  const types=new Map((products?.product_types??[]).map((p:any)=>[p.id,p.type]));
  resources.productTypeMap={};
  for(const product of products?.products??[]) {const type=String(types.get(product.product_type));(resources.productTypeMap[type]??={})[product.id]=product;}
  return async(t:any)=>generateTicketPdf(normalizeTicketData(t,occasion,order,resources.productTypeMap),resources,template);
}
export async function generateTicketPdf(data:RenderData,r:Resources,t:Template,type:'wide'|'named'=t.page.width===595.28?'wide':'named',sample=false) {
  return await drawLayoutTicket(data,r,t,type,sample);
}
