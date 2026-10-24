import { supabaseAdmin } from './supabaseUtil.ts';
import { batchBucket, type BatchObjectStore } from './ticketBatchDocuments.ts';
import { isMissingTicketFontObject } from './ticketFontStorage.ts';
export const batchObjectStore:BatchObjectStore={
 async read(key) {
  const {data,error}=await supabaseAdmin.storage.from(batchBucket).download(key);
  if(error){if(await isMissingTicketFontObject(error))return null;throw new Error('batch_storage_read');}
  if(!data||data.size>16777216)throw new Error('batch_storage_limit');
  return new Uint8Array(await data.arrayBuffer());
 },
 async create(key,bytes,contentType) {
  const {error}=await supabaseAdmin.storage.from(batchBucket).upload(key,bytes,{upsert:false,contentType});
  if(error&&!(['409','400'].includes(String((error as any).statusCode))&&/duplicate|already exists/i.test(error.message)))throw new Error('batch_storage_write');
 }
};
export async function storedBatchTicketPdf(ticketId:number,client=supabaseAdmin):Promise<Uint8Array|null> {
 const {data,error}=await client.rpc('get_ticket_batch_stored_document',{p_ticket:ticketId});
 if(error)throw new Error('batch_document_access');
 if(!data)return null;
 const {readBatchStoredPdf}=await import('./ticketBatchDocuments.ts');
 return readBatchStoredPdf(data,batchObjectStore);
}
