import {resolveTicketFont,parseRegisteredTicketLayout} from '../_shared/ticketFontStorage.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import { supabaseAdmin } from '../_shared/supabaseUtil.ts';
import { loadLayoutResources } from '../_shared/ticketGeneration.ts';
import { handlePreview } from './handler.ts';
import { loadPreviewProducts } from './products.ts';
Deno.serve(req=>handlePreview(req,{
  draft:async(header,id,revision,bytes)=>{
    const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:header}},auth:{persistSession:false}});
    const {data,error}=await client.rpc('get_occasion_setup_ticket_preview',{p_id:id,p_revision:revision,p_bytes:bytes});
    if(error?.code==='PT429')throw Object.assign(new Error('Usage limited'),{status:429});
    if(error) return false;
    return data;
  },
  authorize:async(header,occasionId,bytes)=>{
    const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:header}},auth:{persistSession:false}});
    const {data,error}=await client.rpc('admit_ticket_preview_limits_v1',{p_occasion:occasionId,p_bytes:bytes});
    if(error?.code==='PT429')throw Object.assign(new Error('Usage limited'),{status:429});
    return !error&&data?.abuseLimits?data:false;
  },
  occasion:async id=>{const {data,error}=await supabaseAdmin.from('occasions').select('id,organization,title,start_time,end_time,features,data').eq('id',id).single();if(error)throw error;return data;},
  products:id=>loadPreviewProducts(supabaseAdmin,id),
  resources:loadLayoutResources,
  font:resolveTicketFont,layout:parseRegisteredTicketLayout,
}));
