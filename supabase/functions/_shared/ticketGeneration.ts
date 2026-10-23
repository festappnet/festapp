import { drawLayoutTicket, prepareTicketBackground, type PreparedTicketBackground } from './generateTicket.ts';
import { defaultTicketTemplate } from './ticketLayout.ts';
import { validateLayout, pdfBox, type Template, type TicketLayout } from './ticketLayout.ts';
import { normalizeTicketData, type RenderData, type ProductCatalog, indexProductCatalog, validateProductReferences } from './ticketRenderData.ts';
import { type FontMetrics } from './ticketText.ts';
import { fetchPublicImage, UnsafeTargetError } from '../fetch-http-data/safeFetch.ts';
import {futuraId,type TicketFont} from './ticketFonts.ts';
import {resolveTicketFont,parseRegisteredTicketLayout} from './ticketFontStorage.ts';
import {effectiveFontId,layoutFontIds} from './ticketLayout.ts';
import {galleryBackground, galleryFontIds} from './ticketGallery.ts';
export interface Resources { fonts?:Record<string,TicketFont>;registeredIds?:ReadonlySet<string>;font:Uint8Array;metrics:FontMetrics;background?:Uint8Array;preparedBackground?:PreparedTicketBackground;missingBackground?:boolean;logo?:Uint8Array;catalog?:ProductCatalog }
export async function loadLayoutResources(occasion:any,featureOverride?:any,options:{allowMissingBackground?:boolean}={},readImage=fetchPublicImage):Promise<Resources> {
  const feature=featureOverride??occasion.features?.find((f:any)=>f.code==='ticket');
  const type=feature?.ticket_type==='named'?'named':'wide';
  const template=feature?.layout?.templates?.[type];
  const defaultId=template?effectiveFontId(template):futuraId;
  const ids=new Set<string>([defaultId]);
  if(options.allowMissingBackground)ids.add(futuraId); // concurrently rendered preset gallery
  if(options.allowMissingBackground)for(const id of galleryFontIds)ids.add(id);
  for(const e of template?.elements??[])if(e.visible&&!['qr','logo'].includes(e.binding))ids.add(effectiveFontId(template,e));
  const fonts:Record<string,TicketFont>={};await Promise.all([...ids].map(async id=>{fonts[id]=await resolveTicketFont(id);}));
  const selected=fonts[defaultId];const font=selected.bytes;
  const read=async(url:string)=> (await readImage(url)).bytes;
  const backgroundUrl=template?feature?.background:type==='named'?null:feature?.background;
  let backgroundBytes:Uint8Array|undefined;
  let missingBackground=false;
  if(backgroundUrl) {
    try { backgroundBytes=await galleryBackground(backgroundUrl)??await read(backgroundUrl); }
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
  const active=activeTemplate(occasion,resources.registeredIds);
  if(active)return active;
  const feature=occasion.features?.find((f:any)=>f.code==='ticket');
  if(!feature?.layout&&feature?.background)throw new Error('ticket_layout_migration_required');
  return defaultTicketTemplate(feature?.ticket_type==='named'?'named':'wide');
}
export async function prepareTicketRenderer(occasion:any,_ticket:any,order:any={}, dependencies = {
  load: loadLayoutResources,
  products: async(id:number)=>{
    const { supabaseAdmin } = await import('./supabaseUtil.ts');
    const {data,error}=await supabaseAdmin.rpc('get_products_and_types',{p_occasion_id:id});if(error)throw new Error('Failed to load ticket products');return data;
  }
}) {
  if(_ticket?.batch_id) {
    const {storedBatchTicketPdf}=await import('./ticketBatchStorage.ts');
    return async(t:any)=> {
      const bytes=await storedBatchTicketPdf(t.id);
      if(!bytes)throw new Error('batch_document_missing');
      return {bytes};
    };
  }
  const feature=occasion.features?.find((f:any)=>f.code==='ticket');
  if(feature?.is_enabled===false)throw new Error('Admission tickets are disabled for this occasion');
  const layout=feature?.layout;
  if(layout)await parseRegisteredTicketLayout(layout);
  return prepareTicketRendererFromResources(occasion,order,await dependencies.load(occasion),await dependencies.products(occasion.id));
}
/** Immutable batch documents and ordinary checkout share this renderer. */
export async function prepareTicketRendererFromResources(occasion:any,order:any,loaded:Resources,products:any) {
  const resources={...loaded};
  if(resources.background)resources.preparedBackground=await prepareTicketBackground(resources.background);
  const template=await resolveTicketTemplate(occasion,resources);
  resources.catalog=indexProductCatalog(products,occasion.id);
  validateProductReferences(template,resources.catalog);
  return async(t:any)=>{
    if(t.state==='waitlisted')throw new Error('Waiting tickets cannot be issued for admission');
    return generateTicketPdf(normalizeTicketData(t,occasion,order,resources.catalog,template),resources,template);
  };
}
export async function generateTicketPdf(data:RenderData,r:Resources,t:Template,type:'wide'|'named'=t.page.width===595.28?'wide':'named',sample=false) {
  return await drawLayoutTicket(data,r,t,type,sample);
}
