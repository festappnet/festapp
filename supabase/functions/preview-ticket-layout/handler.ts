import QRCode from 'npm:qrcode';
import { Buffer } from 'node:buffer';
import { PDFDocument } from 'npm:pdf-lib';
import { parseLayout, preset, ticketPresets, TicketType } from '../_shared/ticketLayout.ts';
import { sampleData } from '../_shared/ticketRenderData.ts';
import { loadLayoutResources, generateTicketPdf, resolveTicketTemplate, ticketFonts } from '../_shared/ticketGeneration.ts';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Cache-Control':'no-store'};
export interface PreviewDependencies {
  authorize(header:string,occasionId:number):Promise<boolean>;
  occasion(id:number):Promise<any>;
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
    if(!Number.isSafeInteger(occasionId)||occasionId<1||!['resolve','pdf'].includes(mode)||!['wide','named'].includes(type)||!['normal','long','missing'].includes(scenario)||'requestSecret' in body || 'ticketId' in body) return reply(400,{error:'Invalid preview request'});
    if(!await deps.authorize(auth,occasionId))return reply(403,{error:'Forbidden'});
    const occasion=await deps.occasion(occasionId);
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

    const layout=body.layout===undefined?(feature.layout===undefined?undefined:parseLayout(feature.layout)):parseLayout(body.layout);
    if(layout)feature.layout=layout;
    const resources=await deps.resources(occasion,feature,{allowMissingBackground:mode==='resolve'});
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
    const data=sampleData(scenario,occasion);
    const qr=QRCode.create(data.qr!,{errorCorrectionLevel:'M'}).modules;
    if(mode==='resolve') return reply(200,{missingBackground:resources.missingBackground===true,fonts:resources.fonts?Object.fromEntries(Object.entries(resources.fonts).map(([key,f])=>[key,{label:ticketFonts[key as keyof typeof ticketFonts],font:Buffer.from(f.font).toString('base64'),metrics:f.metrics}])):undefined,template,preset:initial,presets:choices,presetBackgrounds:{portrait:null,portrait_compact:null,portrait_event:null},backgroundUrl:feature.background??null,data,qrMatrix:{size:qr.size,data:Array.from(qr.data)},scenarios:Object.fromEntries(['normal','long','missing'].map(s=>[s,sampleData(s,occasion)])),background:resources.background?Buffer.from(resources.background).toString('base64'):null,logo:resources.logo?Buffer.from(resources.logo).toString('base64'):null,metrics:resources.metrics,font:Buffer.from(resources.font).toString('base64')});
    const result=await generateTicketPdf(data,resources,template,type,true);
    return reply(200,{file:Buffer.from(result.bytes).toString('base64'),warnings:result.warnings});
  }catch {return reply(400,{error:'Ticket preview rejected. Check layout and image resources.'});}
}
