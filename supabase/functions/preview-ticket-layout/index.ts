import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import { supabaseAdmin } from '../_shared/supabaseUtil.ts';
import { loadLayoutResources } from '../_shared/ticketGeneration.ts';
import { handlePreview } from './handler.ts';
Deno.serve(req=>handlePreview(req,{
  authorize:async(header,occasionId)=>{
    const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:header}},auth:{persistSession:false}});
    const {data,error}=await client.rpc('can_edit_ticket_layout',{p_occasion:occasionId});
    return !error&&data===true;
  },
  occasion:async id=>{const {data,error}=await supabaseAdmin.from('occasions').select('id,organization,title,start_time,end_time,features,data').eq('id',id).single();if(error)throw error;return data;},
  products:async id=>{
    const {data,error}=await supabaseAdmin.schema('eshop').from('product_types')
      .select('type,products(id,title,data,price,currency_code,is_hidden)').eq('occasion',id);
    if(error)throw error;
    return (data??[]).flatMap(group=>group.products.map(product=>({...product,type:group.type})));
  },
  resources:loadLayoutResources,
}));
