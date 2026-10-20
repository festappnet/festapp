import {fontFamilyCatalog,TicketFontError,type TicketFont} from './ticketFonts.ts';
import {LayoutTextFace} from './layoutTextShaper.ts';
import {prepareLayoutText,prepareLayoutNumberSymbols,type LayoutTextRequest} from './layoutTextPreparation.ts';

/** Closed, bounded batch. The caller admits the scope before invoking this
 * function and registers the complete bounded result before returning it. */
export async function prepareLayoutTextResources(value:unknown,resolve:(id:string)=>Promise<TicketFont>){
 const invalid=():never=>{throw new TicketFontError('layout_text_request');};
 if(!value||typeof value!=='object'||Array.isArray(value))invalid();
 const batch=value as {requests:LayoutTextRequest[];numericFaces:Array<{fontFamilyId:string;fontFaceId:string}>};
 if(Object.keys(batch).some(k=>!['requests','numericFaces'].includes(k))||!Array.isArray(batch.requests)||batch.requests.length>32||!Array.isArray(batch.numericFaces)||batch.numericFaces.length>8)invalid();
 let characters=0;
 const families:Record<string,unknown>={},faceIds=new Set<string>();
 for(const request of [...batch.requests,...batch.numericFaces]){
  if(!request||typeof request!=='object')invalid();
  const family=fontFamilyCatalog.find(f=>f.id===request.fontFamilyId);
  if(!family||!Object.values(family.faces).includes(request.fontFaceId))throw new TicketFontError('font_face_unavailable');
  families[family.id]=family;faceIds.add(request.fontFaceId);
 }
 for(const request of batch.requests){if(typeof request.text!=='string')invalid();characters+=[...request.text].length;}
 for(const request of batch.numericFaces)if(Object.keys(request).some(k=>!['fontFamilyId','fontFaceId'].includes(k)))invalid();
 if(characters>8192||faceIds.size>8)throw new TicketFontError('font_characters_limit');
 const faces=new Map<string,LayoutTextFace>();
 for(const id of faceIds)faces.set(id,await LayoutTextFace.fromTicketFont(await resolve(id)));
 const textLayouts:Record<string,Awaited<ReturnType<typeof prepareLayoutText>>>={};
 for(const request of batch.requests){const prepared=await prepareLayoutText(faces.get(request.fontFaceId)!,request);textLayouts[prepared.id]=prepared;}
 const numberSymbols:Record<string,Awaited<ReturnType<typeof prepareLayoutNumberSymbols>>>={};
 for(const request of batch.numericFaces)numberSymbols[request.fontFaceId]=await prepareLayoutNumberSymbols(faces.get(request.fontFaceId)!);
 return {protocol:2,fontFamilies:families,textLayouts,numberSymbols};
}
