import { documentLimits, boundDocumentOutput } from '../_shared/documentLimits.ts';
import { AuthError } from '../_shared/authError.ts';
import QRCode from 'npm:qrcode';
import { Buffer } from 'node:buffer';
import { PDFDocument } from 'npm:pdf-lib';
import { parseLayout, preset, TicketType } from '../_shared/ticketLayout.ts';
import {ticketGallery, galleryBackgrounds, galleryBackground} from '../_shared/ticketGallery.ts';
import { sampleData, indexProductCatalog, type ProductCatalog, validateProductReferences } from '../_shared/ticketRenderData.ts';
import { loadLayoutResources, generateTicketPdf, resolveTicketTemplate } from '../_shared/ticketGeneration.ts';
import {TicketFontError,type TicketFont} from '../_shared/ticketFonts.ts';
const fontReply=(f:TicketFont)=>({id:f.id,family:f.family,weight:f.weight,font:Buffer.from(f.bytes).toString('base64'),metrics:f.metrics});
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Cache-Control':'no-store'};
export interface PreviewDependencies {
  authorize(header:string,occasionId:number,bytes:number):Promise<false|{abuseLimits:Record<string,number>}>;
  draft?(header:string,id:string,revision:number,bytes:number):Promise<any>;
  occasion(id:number):Promise<any>;
  products(id:number):Promise<ProductCatalog>;
  font?:(id:string)=>Promise<TicketFont>;
  layout?:(value:unknown)=>ReturnType<typeof parseLayout>|Promise<ReturnType<typeof parseLayout>>;
  resources:typeof loadLayoutResources;
}
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
export async function handlePreview(req:Request,deps:PreviewDependencies):Promise<Response>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(req.method!=='POST')return reply(405,{error:'Method not allowed'});
  const auth=req.headers.get('Authorization');
  if(!auth||!/^Bearer \S+$/i.test(auth))return reply(401,{error:'Unauthorized'});
  try{
    // Read the body with a hard byte bound, including chunked requests.
    const reader=req.body?.getReader();let raw='',count=0;const decoder=new TextDecoder();
    if(reader)while(true){const {done,value}=await reader.read();if(done)break;count+=value.length;if(count>40000){await reader.cancel();return reply(413,{error:'Request too large'});}raw+=decoder.decode(value,{stream:true});}
    raw+=decoder.decode();const body=JSON.parse(raw);
    const {occasionId,mode,type,scenario='normal'}=body;
    const isDraft=typeof body.draftId==='string' && /^[0-9a-f-]{36}$/.test(body.draftId) && Number.isSafeInteger(body.draftRevision) && body.draftRevision>0 && occasionId===undefined;
    if((!isDraft&&(!Number.isSafeInteger(occasionId)||occasionId<1))||!['resolve','pdf','font','catalog'].includes(mode)||(!['font','catalog'].includes(mode)&&!['wide','named'].includes(type))||!['normal','long','missing'].includes(scenario)||'requestSecret' in body || 'ticketId' in body) return reply(400,{error:'Invalid preview request'});
    const draft=isDraft && deps.draft ? await deps.draft(auth,body.draftId,body.draftRevision,count) : null;
    const admission=isDraft ? draft : await deps.authorize(auth,occasionId,count);
    if(!admission)return reply(403,{error:'Forbidden'});
    const limits=documentLimits(admission);
    const boundedReply=(status:number,body:unknown)=>{
      if(new TextEncoder().encode(JSON.stringify(body)).byteLength>limits.outputBytes)throw new AuthError('Preview output too large',429);
      return reply(status,body);
    };
    if(mode==='font'){if(body.fontProtocol!==2||typeof body.fontId!=='string'||!deps.font)return reply(400,{error:'Invalid font request'});return boundedReply(200,fontReply(await deps.font(body.fontId)));}
    const occasion=isDraft ? {id:0,organization:draft.organization,title:draft.data.title,start_time:draft.data.start,end_time:draft.data.end,data:{},features:[draft.data.ticketDraft ?? {code:'ticket'}]} : await deps.occasion(occasionId);
    let products:ProductCatalog;let catalogError=false;
    try {
      if(isDraft) {
        const types=(draft.data.formDraft?.fields??[]).map((f:any)=>f.product_type_data??f.product_type).filter((t:any)=>t&&typeof t==='object');
        products=indexProductCatalog({product_types:types.map((t:any)=>({...t,occasion:0,admission:t.type==='spot',offered:true,referenced:true})),products:types.flatMap((t:any)=>(t.products??[]).map((p:any)=>({...p,product_type:t.id})))},0);
      } else products=await deps.products(occasionId);
    } catch(error){if(mode!=='resolve')throw error;catalogError=true;products={types:new Map(),products:new Map()};}
    if(mode==='catalog')return boundedReply(200,{catalog:[...products.types.values()]});
    const feature={...(occasion.features?.find((f:any)=>f.code==='ticket')??{}),ticket_type:type};
    if(body.borrowResourcesOnly===true&&mode==='resolve'){delete feature.layout;feature.background=null;products={types:new Map(),products:new Map()};}
    // Keep an unchanged persisted source; new client-supplied sources must be
    // uploaded image objects. All image reads still pass public-DNS/SSRF checks.
    const requestedBackground=typeof body.background==='string' && body.background.trim()===''?null:body.background;
    if(requestedBackground!==undefined&&requestedBackground!==null){
      const url=new URL(requestedBackground);
      if(requestedBackground!==feature.background && (url.protocol!=='https:'||url.hostname!=='img.festapp.net'||url.username||url.password||url.port)) return reply(400,{error:'Unapproved image source'});
      feature.background=url.href;
    }
    if(requestedBackground===null)feature.background=null;

    const layout=body.layout===undefined?(feature.layout===undefined?undefined:await (deps.layout??parseLayout)(feature.layout)):await (deps.layout??parseLayout)(body.layout);
    if(body.fontProtocol!==2)return reply(400,{error:'ticket_font_protocol_unsupported'});
    if(layout)feature.layout=layout;
    if(layout&&!catalogError)for(const template of Object.values(layout.templates))validateProductReferences(template,products);
    const resources=await deps.resources(occasion,feature,{allowMissingBackground:mode==='resolve'});
    let template=layout?.templates[type as TicketType];
    let width=1600,height=900;
    if(resources.background){const doc=await PDFDocument.create();let img;try{img=await doc.embedPng(resources.background);}catch{img=await doc.embedJpg(resources.background);}width=img.width;height=img.height;}
    const choices=ticketGallery();
    const initial=await resolveTicketTemplate({...occasion,features:[feature]},resources);

    if(/^[0-9A-Fa-f]{6}$/.test(feature.darkColor??'')) {
      const colored=[...Object.entries(choices).filter(([key])=>['classic','compact','event'].includes(key)).map(([,t])=>t),...(type==='wide'?[initial]:[])];
      for(const t of colored)for(const e of t.elements)if(e.binding!=='qr')e.style.color=feature.darkColor;
    }
    template??=initial;
    const data=sampleData(scenario,occasion,catalogError?undefined:products,template);
    const qr=QRCode.create(data[template.elements.find(e=>e.binding==='qr')!.id]!,{errorCorrectionLevel:'M'}).modules;
    const presetArtwork:Record<string,{background:string|null;image:string|null}>={};
    if(mode==='resolve')for(const [key,url] of Object.entries(galleryBackgrounds))presetArtwork[key]={background:url,image:url?Buffer.from((await galleryBackground(url))!).toString('base64'):null};
    if(mode==='resolve') return boundedReply(200,{catalogError,catalog:[...products.types.values()],missingBackground:resources.missingBackground===true,fonts:resources.fonts?Object.fromEntries(Object.entries(resources.fonts).map(([id,f])=>[id,fontReply(f)])):undefined,template,preset:initial,presets:choices,presetArtwork,presetBackgrounds:{portrait:null,portrait_compact:null,portrait_event:null},backgroundUrl:feature.background??null,data,qrMatrix:{size:qr.size,data:Array.from(qr.data)},scenarios:Object.fromEntries(['normal','long','missing'].map(s=>[s,sampleData(s,occasion,products)])),background:resources.background?Buffer.from(resources.background).toString('base64'):null,logo:resources.logo?Buffer.from(resources.logo).toString('base64'):null,metrics:resources.metrics,font:Buffer.from(resources.font).toString('base64')});
    const result=await generateTicketPdf(data,resources,template,type,true);
    boundDocumentOutput(result.bytes,1,limits);
    return boundedReply(200,{file:Buffer.from(result.bytes).toString('base64'),warnings:result.warnings});
  }catch(error) {if(error && typeof error==='object' && 'status' in error && error.status===429)return reply(429,{error:'temporarily_limited'});if(error instanceof TicketFontError)return reply(400,{error:error.code});return reply(400,{error:'Ticket preview rejected. Check layout and image resources.'});}
}
