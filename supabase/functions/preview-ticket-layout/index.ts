import {resolveTicketFont,parseRegisteredTicketLayout} from '../_shared/ticketFontStorage.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import { supabaseAdmin } from '../_shared/supabaseUtil.ts';
import { loadLayoutResources } from '../_shared/ticketGeneration.ts';
import { handlePreview } from './handler.ts';
import { loadPreviewProducts } from './products.ts';
Deno.serve(req=>handlePreview(req,{
  authorize:async(header,occasionId,readOnly=false)=>{
    const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:header}},auth:{persistSession:false}});
    if(readOnly){
      const results=await Promise.all(['get_is_editor_on_occasion','get_is_editor_view_on_occasion','get_is_editor_order_on_occasion','get_is_editor_order_view_on_occasion'].map(name=>client.rpc(name,{oc:occasionId})));
      return results.some(({data,error})=>!error&&data===true);
    }
    const {data,error}=await client.rpc('can_edit_ticket_layout',{p_occasion:occasionId});
    return !error&&data===true;
  },
  occasion:async id=>{const {data,error}=await supabaseAdmin.from('occasions').select('id,organization,title,start_time,end_time,features,data').eq('id',id).single();if(error)throw error;const {data:demo,error:demoError}=await supabaseAdmin.from('demo_occasions').select('occasion').eq('occasion',id).maybeSingle();if(demoError)throw demoError;return {...data,demo_read_only:demo!=null};},
  products:id=>loadPreviewProducts(supabaseAdmin,id),
  resources:loadLayoutResources,
  font:resolveTicketFont,layout:parseRegisteredTicketLayout,
}));
