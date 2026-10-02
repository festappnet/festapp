import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import { supabaseAdmin } from '../_shared/supabaseUtil.ts';
import { loadLayoutResources } from '../_shared/ticketGeneration.ts';
import { handlePreview } from './handler.ts';
import { loadPreviewProducts } from './products.ts';
Deno.serve(req=>handlePreview(req,{
  authorize:async(header,occasionId)=>{
    const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:header}},auth:{persistSession:false}});
    const {data,error}=await client.rpc('can_edit_ticket_layout',{p_occasion:occasionId});
    return !error&&data===true;
  },
  occasion:async id=>{const {data,error}=await supabaseAdmin.from('occasions').select('id,organization,title,start_time,end_time,features,data').eq('id',id).single();if(error)throw error;return data;},
  products:id=>loadPreviewProducts(supabaseAdmin,id),
  resources:loadLayoutResources,
}));
