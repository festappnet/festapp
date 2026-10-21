import {prepareLayoutTextResources} from '../_shared/layoutTextResources.ts';
import { documentLimits, boundDocumentOutput } from '../_shared/documentLimits.ts';
import { AuthError } from '../_shared/authError.ts';
import QRCode from 'npm:qrcode';
import { Buffer } from 'node:buffer';
import { PDFDocument } from 'npm:pdf-lib';
import { parseLayout, preset, ticketPresets, TicketType } from '../_shared/ticketLayout.ts';
import { sampleData, type ProductCatalog, validateProductReferences } from '../_shared/ticketRenderData.ts';
import { loadLayoutResources, generateTicketPdf, resolveTicketTemplate } from '../_shared/ticketGeneration.ts';
import {TicketFontError,type TicketFont} from '../_shared/ticketFonts.ts';
const fontReply=(f:TicketFont)=>({id:f.id,family:f.family,weight:f.weight,font:Buffer.from(f.bytes).toString('base64'),metrics:f.metrics});
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Cache-Control':'no-store'};
export interface PreviewDependencies {
  authorize(header:string,occasionId:number,bytes:number,readOnly?:boolean,resourceMode?:'font'|'layout-text'):Promise<false|{abuseLimits:Record<string,number>}>;
  authorizeSetupDraft?:(header:string,draftId:string,bytes:number)=>Promise<false|{abuseLimits:Record<string,number>}>;
  occasion(id:number):Promise<any>;
  products(id:number):Promise<ProductCatalog>;
  font?:(id:string)=>Promise<TicketFont>;
  registerLayoutTextResources?:(scope:{occasionId?:number;setupDraftId?:string},resources:Awaited<ReturnType<typeof prepareLayoutTextResources>>)=>Promise<void>;
  layout?:(value:unknown)=>ReturnType<typeof parseLayout>|Promise<ReturnType<typeof parseLayout>>;
  resources:typeof loadLayoutResources;
}
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}});
// Draft text is independent of the authorized occasion and cannot select assets.
function validPreviewOccasion(value:any):boolean {
  const record=(v:any)=>v!==null&&typeof v==='object'&&!Array.isArray(v);
  const text=(v:any)=>v===null||(typeof v==='string'&&Array.from(v).length<=500);
  const date=(v:any)=>v===null||(typeof v==='string'&&v.length<=35&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(v)&&Number.isFinite(Date.parse(v)));
  return record(value)&&Object.keys(value).every(k=>['title','start_time','end_time','data'].includes(k))&&
    typeof value.title==='string'&&text(value.title)&&
    ['start_time','end_time'].every(k=>!(k in value)||date(value[k]))&&
    (!('data' in value)||(record(value.data)&&Object.keys(value.data).every(k=>k==='place_name')&&(!('place_name' in value.data)||text(value.data.place_name))));
}
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
    const {occasionId,setupDraftId,mode,type,scenario='normal'}=body;
    const setup=setupDraftId!==undefined;
    const validContext=setup
      ? typeof setupDraftId==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(setupDraftId)&&occasionId===undefined&&(mode==='layout-text'||mode==='font')&&!('layout' in body)&&!('background' in body)&&!('borrowResourcesOnly' in body)
      : Number.isSafeInteger(occasionId)&&occasionId>0;
    if(!validContext||!['resolve','pdf','font','catalog','layout-text'].includes(mode)||(!['font','catalog','layout-text'].includes(mode)&&!['wide','named'].includes(type))||!['normal','long','missing'].includes(scenario)||'requestSecret' in body || 'ticketId' in body) return reply(400,{error:'Invalid preview request'});
    const readOnly=body.readOnly===true;
    if ('previewOccasion' in body && (readOnly || !['resolve','pdf'].includes(mode) || !validPreviewOccasion(body.previewOccasion))) return reply(400,{error:'Invalid draft preview context'});
    if(readOnly&&(mode!=='resolve'||'layout' in body||'background' in body||'borrowResourcesOnly' in body))return reply(400,{error:'Saved preview does not accept edits'});
    const admission=setup
      ? await deps.authorizeSetupDraft?.(auth,setupDraftId,count)??false
      : await deps.authorize(auth,occasionId,count,readOnly,
          mode==='font'||mode==='layout-text'?mode:undefined);
    if(!admission)return reply(403,{error:'Forbidden'});
    const limits=documentLimits(admission);
    const boundedReply=(status:number,body:unknown)=>{
      if(new TextEncoder().encode(JSON.stringify(body)).byteLength>limits.outputBytes)throw new AuthError('Preview output too large',429);
      return reply(status,body);
    };
    if(mode==='layout-text'){
      if(body.resourceProtocol!==2||!deps.font||!deps.registerLayoutTextResources||Object.keys(body).some(k=>!['occasionId','setupDraftId','mode','resourceProtocol','batch'].includes(k)))return reply(400,{error:'layout_text_request'});
      const resources=await prepareLayoutTextResources(body.batch,deps.font);
      const response=boundedReply(200,resources);
      await deps.registerLayoutTextResources(setup?{setupDraftId}:{occasionId},resources);
      return response;
    }
    if(mode==='font'){
      if(body.fontProtocol!==2||typeof body.fontId!=='string'||!deps.font||'outline' in body||'characters' in body)return reply(400,{error:'Invalid font request'});
      const font=await deps.font(body.fontId);
      return boundedReply(200,fontReply(font));
    }
    const occasion=await deps.occasion(occasionId);
    if(readOnly&&type!==(occasion.features?.find((f:any)=>f.code==='ticket')?.ticket_type==='named'?'named':'wide'))return reply(400,{error:'Saved ticket type mismatch'});
    let products:ProductCatalog;let catalogError=false;
    try {products=await deps.products(occasionId);} catch(error){if(mode!=='resolve'||readOnly)throw error;catalogError=true;products={types:new Map(),products:new Map()};}
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
    const resources=await deps.resources(occasion,feature,{allowMissingBackground:mode==='resolve'&&!readOnly});
    let template=layout?.templates[type as TicketType];
    let width=1600,height=900;
    if(resources.background){const doc=await PDFDocument.create();let img;try{img=await doc.embedPng(resources.background);}catch{img=await doc.embedJpg(resources.background);}width=img.width;height=img.height;}
    const choices=ticketPresets();
    const initial=await resolveTicketTemplate({...occasion,features:[feature]},resources);

    if(/^[0-9A-Fa-f]{6}$/.test(feature.darkColor??'')) {
      const colored=[...Object.entries(choices).filter(([key])=>!key.startsWith('portrait')).map(([,t])=>t),...(type==='wide'&&!layout&&resources.background?[initial]:[])];
      for(const t of colored)for(const e of t.elements)if(e.binding!=='qr')e.style.color=feature.darkColor;
    }
    template??=initial;
    const previewOccasion=body.previewOccasion===undefined?occasion:{
      ...occasion,
      title:body.previewOccasion.title,
      start_time:body.previewOccasion.start_time??null,
      end_time:body.previewOccasion.end_time??null,
      data:{...occasion.data,place_name:body.previewOccasion.data?.place_name??null},
    };
    const data=sampleData(scenario,previewOccasion,catalogError?undefined:products,template);
    const qr=QRCode.create(data[template.elements.find(e=>e.binding==='qr')!.id]!,{errorCorrectionLevel:'M'}).modules;
    if(mode==='resolve') return boundedReply(200,{catalogError,catalog:[...products.types.values()],missingBackground:resources.missingBackground===true,fonts:resources.fonts?Object.fromEntries(Object.entries(resources.fonts).map(([id,f])=>[id,fontReply(f)])):undefined,template,preset:initial,presets:choices,presetBackgrounds:{portrait:null,portrait_compact:null,portrait_event:null},backgroundUrl:feature.background??null,data,qrMatrix:{size:qr.size,data:Array.from(qr.data)},scenarios:Object.fromEntries(['normal','long','missing'].map(s=>[s,sampleData(s,previewOccasion,products)])),background:resources.background?Buffer.from(resources.background).toString('base64'):null,logo:resources.logo?Buffer.from(resources.logo).toString('base64'):null,metrics:resources.metrics,font:Buffer.from(resources.font).toString('base64')});
    const result=await generateTicketPdf(data,resources,template,type,true);
    boundDocumentOutput(result.bytes,1,limits);
    return boundedReply(200,{file:Buffer.from(result.bytes).toString('base64'),warnings:result.warnings});
  }catch(error) {if(error && typeof error==='object' && 'status' in error && error.status===429)return reply(429,{error:'temporarily_limited'});if(error instanceof TicketFontError)return reply(400,{error:error.code});return reply(400,{error:'Ticket preview rejected. Check layout and image resources.'});}
}
