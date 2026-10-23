import { supabaseAdmin,createUserClient } from '../_shared/supabaseUtil.ts';
import { batchObjectStore } from '../_shared/ticketBatchStorage.ts';
import { sealBatchResources,renderBatchPart,readBatchStoredPdf } from '../_shared/ticketBatchDocuments.ts';
import { digest } from '../_shared/ticketFonts.ts';
import { documentLimits,boundDocumentInput,boundDocumentOutput } from '../_shared/documentLimits.ts';
import { PDFDocument } from 'npm:pdf-lib';
import { exportTicketBatch } from '../_shared/ticketBatchExports.ts';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Content-Type':'application/json'};
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 let claim:any;let batchId:string|undefined;
 try {
  if(req.method!=='POST')return new Response('{}',{status:405,headers});
  const auth=req.headers.get('Authorization');if(!auth)return new Response('{}',{status:401,headers});
  const input=await req.json();batchId=input.batchId;
  if(typeof batchId!=='string'||!/^[a-f0-9-]{36}$/.test(batchId))return new Response('{}',{status:400,headers});
  if(input.format !== undefined && input.format !== 'a4' && input.format !== 'zip')return new Response('{}',{status:400,headers});
  const user=createUserClient(auth);
  if(input.format !== undefined) {
   const {data,error}=await user.rpc('get_ticket_batch_export_manifest',{p_batch:batchId});
   if(error)return new Response(JSON.stringify({error:'batch_export_unavailable'}),{status:403,headers});
   const bytes=await exportTicketBatch(data,input.format,batchObjectStore);
   return new Response(bytes,{headers:{...headers,'Content-Type':'application/octet-stream','Cache-Control':'no-store',
    'Content-Disposition':`attachment; filename="tickets.${input.format==='zip'?'zip':'pdf'}"`}});
  }
  const result=await user.rpc('claim_ticket_batch_document',{p_batch:batchId,p_part:input.partId??null});
  if(result.error)return new Response(JSON.stringify({error:'document_access_denied'}),{status:403,headers});
  claim=result.data;
  if(claim.state==='ready'&&claim.objectKey){
   const bytes=await readBatchStoredPdf(claim,batchObjectStore);
   return new Response(bytes,{headers:{...headers,'Content-Type':'application/octet-stream','Cache-Control':'no-store'}});
  }
  if(claim.state!=='claimed')return new Response(JSON.stringify(claim),{headers});
  const limits=documentLimits(claim);boundDocumentInput(claim,limits.inputBytes);
  if(claim.kind==='resources') {
   const manifest=await sealBatchResources(claim,batchObjectStore);
   const {error}=await supabaseAdmin.rpc('complete_ticket_batch_resources_internal',{p_batch:batchId,p_lease:claim.lease,p_manifest:manifest,p_part_size:manifest.printPartSize});
   if(error)throw new Error('batch_manifest_commit');
  } else {
   // Recover an immutable upload after a lost completion response, without rendering new bytes.
   let bytes=await batchObjectStore.read(claim.objectKey),pages:number,hash:string;
   if(bytes){pages=(await PDFDocument.load(bytes)).getPageCount();boundDocumentOutput(bytes,pages,limits);hash=await digest(bytes);}
   else {const rendered=await renderBatchPart(claim,batchObjectStore);bytes=rendered.bytes;pages=rendered.pages;hash=rendered.digest;
    await batchObjectStore.create(claim.objectKey,bytes,'application/pdf');
    const stored=await batchObjectStore.read(claim.objectKey);if(!stored||await digest(stored)!==hash)throw new Error('batch_upload_integrity');}
   const {error}=await supabaseAdmin.rpc('complete_ticket_batch_document_internal',{p_part:claim.partId,p_lease:claim.lease,p_digest:hash,p_bytes:bytes.length,p_pages:pages});
   if(error)throw new Error('batch_document_commit');
  }
  return new Response(JSON.stringify({state:'progress',partId:claim.partId??null}),{headers});
 }catch {
  if(claim?.lease&&batchId)await supabaseAdmin.rpc('fail_ticket_batch_document_internal',{p_batch:batchId,p_part:claim.partId??null,p_lease:claim.lease});
  return new Response(JSON.stringify({state:'failed',error:'batch_document_preparation_failed'}),{status:500,headers});
 }
});
