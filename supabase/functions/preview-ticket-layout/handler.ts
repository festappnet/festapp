import QRCode from 'npm:qrcode';
import { Buffer } from 'node:buffer';
import { PDFDocument } from 'npm:pdf-lib';
import { parseLayout, preset, ticketPresets, TicketType } from '../_shared/ticketLayout.ts';
import { sampleData, type PreviewProduct } from '../_shared/ticketRenderData.ts';
import { loadLayoutResources, generateTicketPdf, resolveTicketTemplate } from '../_shared/ticketGeneration.ts';
import {TicketFontError,type TicketFont,legacyFontIds,futuraId} from '../_shared/ticketFonts.ts';
const fontReply=(f:TicketFont)=>({id:f.id,family:f.family,weight:f.weight,font:Buffer.from(f.bytes).toString('base64'),metrics:f.metrics});
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Cache-Control':'no-store'};
export interface PreviewDependencies {
  authorize(header:string,occasionId:number):Promise<boolean>;
  occasion(id:number):Promise<any>;
  products(id:number):Promise<PreviewProduct[]>;
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
    if(!Number.isSafeInteger(occasionId)||occasionId<1||!['resolve','pdf','font'].includes(mode)||(mode!=='font'&&!['wide','named'].includes(type))||!['normal','long','missing'].includes(scenario)||'requestSecret' in body || 'ticketId' in body) return reply(400,{error:'Invalid preview request'});
    if(!await deps.authorize(auth,occasionId))return reply(403,{error:'Forbidden'});
    if(mode==='font'){if(body.fontProtocol!==2||typeof body.fontId!=='string'||!deps.font)return reply(400,{error:'Invalid font request'});return reply(200,fontReply(await deps.font(body.fontId)));}
    const occasion=await deps.occasion(occasionId);
    const products=await deps.products(occasionId);
    const feature={...(occasion.features?.find((f:any)=>f.code==='ticket')??{}),ticket_type:type};
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
    if(layout?.schemaVersion===2&&body.fontProtocol!==2)return reply(400,{error:'ticket_font_protocol_unsupported'});
    if(layout)feature.layout=layout;
    const resources=await deps.resources(occasion,feature,{allowMissingBackground:mode==='resolve',legacyFontProtocol:body.fontProtocol!==2});
    let template=layout?.templates[type as TicketType];
    let width=1600,height=900;
    if(resources.background){const doc=await PDFDocument.create();let img;try{img=await doc.embedPng(resources.background);}catch{img=await doc.embedJpg(resources.background);}width=img.width;height=img.height;}
    const choices=ticketPresets();
    const initial=await resolveTicketTemplate({...occasion,features:[feature]},resources);

    if(/^[0-9A-Fa-f]{6}$/.test(feature.darkColor??'')) {
      const colored=[...Object.entries(choices).filter(([key])=>!key.startsWith('portrait')).map(([,t])=>t),...(type==='wide'?[initial]:[])];
      for(const t of colored)for(const e of t.elements)if(e.binding!=='qr')e.style.color=feature.darkColor;
    }
    template??=initial;
    const data=sampleData(scenario,occasion,products);
    const qr=QRCode.create(data.qr!,{errorCorrectionLevel:'M'}).modules;
    if(mode==='resolve') return reply(200,{missingBackground:resources.missingBackground===true,fonts:resources.fonts?(body.fontProtocol===2?Object.fromEntries(Object.entries(resources.fonts).map(([id,f])=>[id,fontReply(f)])):Object.fromEntries(Object.entries(legacyFontIds).filter(([,id])=>resources.fonts?.[id]).map(([name,id])=>[name,{label:resources.fonts![id].family,font:Buffer.from(resources.fonts![id].bytes).toString('base64'),metrics:resources.fonts![id].metrics}]))):undefined,template,preset:initial,presets:choices,presetBackgrounds:{portrait:null,portrait_compact:null,portrait_event:null},backgroundUrl:feature.background??null,data,qrMatrix:{size:qr.size,data:Array.from(qr.data)},scenarios:Object.fromEntries(['normal','long','missing'].map(s=>[s,sampleData(s,occasion,products)])),background:resources.background?Buffer.from(resources.background).toString('base64'):null,logo:resources.logo?Buffer.from(resources.logo).toString('base64'):null,metrics:resources.metrics,font:Buffer.from(resources.font).toString('base64')});
    const result=await generateTicketPdf(data,resources,template,type,true);
    return reply(200,{file:Buffer.from(result.bytes).toString('base64'),warnings:result.warnings});
  }catch(error) {if(error instanceof TicketFontError)return reply(400,{error:error.code});return reply(400,{error:'Ticket preview rejected. Check layout and image resources.'});}
}
