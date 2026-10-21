import {resolveTicketFont,parseRegisteredTicketLayout} from '../_shared/ticketFontStorage.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import { supabaseAdmin } from '../_shared/supabaseUtil.ts';
import { loadLayoutResources } from '../_shared/ticketGeneration.ts';
import { handlePreview } from './handler.ts';
import { loadPreviewProducts } from './products.ts';
Deno.serve(req=>handlePreview(req,{
  authorizeSetupDraft:async(header,draftId,bytes)=>{
    const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:header}},auth:{persistSession:false}});
    const {data,error}=await client.rpc('admit_occasion_setup_blueprint_resources_v1',{p_draft:draftId,p_bytes:bytes});
    if(error?.code==='PT429')throw Object.assign(new Error('Usage limited'),{status:429});
    return !error&&data?.abuseLimits?data:false;
  },
  setupDraft:async(header,draftId)=>{
    const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:header}},auth:{persistSession:false}});
    const {data:row,error}=await client.rpc('get_occasion_setup_draft',{p_id:draftId});
    if(error||!row?.data||row.data.finalizedOccasion)throw new Error('Draft access denied');
    const d=row.data;
    const types=new Map(),products=new Map();
    for(const field of d.formDraft?.fields??[]){
      const t=field.product_type_data;if(!t||!Number.isSafeInteger(t.id))continue;
      const example=(t.products??[]).find((p:any)=>!p.is_hidden);
      types.set(t.id,{id:t.id,occasion:0,title:t.title??field.title??'',offered:!field.is_hidden,referenced:false,admission:t.type==='spot',hasVisibleProducts:!!example,example:example?{id:example.id,value:example.title,price:example.price,currency_code:example.currency_code,currency_symbol:example.currency_code}:null});
      for(const p of t.products??[])products.set(p.id,{...p,product_type:t.id});
    }
    return {occasion:{id:0,title:d.title,start_time:d.start,end_time:d.end,
      data:{place_name:d.placeName},features:[{...d.ticketDraft,code:'ticket'}]},products:{types,products}};
  },
  authorize:async(header,occasionId,bytes,readOnly=false,resourceMode)=>{
    const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:header}},auth:{persistSession:false}});
    const {data,error}=resourceMode
      ? await client.rpc('admit_layout_resources_limits_v1',{p_occasion:occasionId,p_bytes:bytes})
      : await client.rpc('admit_ticket_preview_limits_v1',{p_occasion:occasionId,p_bytes:bytes,p_read_only:readOnly});
    if(error?.code==='PT429')throw Object.assign(new Error('Usage limited'),{status:429});
    return !error&&data?.abuseLimits?data:false;
  },
  occasion:async id=>{const {data,error}=await supabaseAdmin.from('occasions').select('id,organization,title,start_time,end_time,features,data').eq('id',id).single();if(error)throw error;const {data:demo,error:demoError}=await supabaseAdmin.rpc('is_demo_occasion',{p_occasion:id});if(demoError)throw demoError;return {...data,demo_read_only:demo===true};},
  products:id=>loadPreviewProducts(supabaseAdmin,id),
  resources:loadLayoutResources,
  font:resolveTicketFont,layout:parseRegisteredTicketLayout,
  registerLayoutTextResources:async(scope,resources)=>{
    const {error}=await supabaseAdmin.rpc('register_blueprint_text_resources',{p_occasion:scope.occasionId??null,p_setup_draft:scope.setupDraftId??null,p_resources:resources});
    if(error)throw error;
  },
}));
