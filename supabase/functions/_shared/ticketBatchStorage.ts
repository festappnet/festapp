import { supabaseAdmin } from './supabaseUtil.ts';
import {createTicketBatchR2Store} from './ticketBatchR2.ts';
export const batchObjectStore=createTicketBatchR2Store(()=>Deno.env.get('TICKET_BATCH_SERVICE_SECRET'),fetch,Deno.env.get('TICKET_BATCH_SERVICE_URL'));
export async function storedBatchTicketPdf(ticketId:number,client=supabaseAdmin):Promise<Uint8Array|null> {
 const {data,error}=await client.rpc('get_ticket_batch_stored_document',{p_ticket:ticketId});
 if(error)throw new Error('batch_document_access');
 if(!data)return null;
 const {readBatchStoredPdf}=await import('./ticketBatchDocuments.ts');
 return readBatchStoredPdf(data,batchObjectStore);
}
