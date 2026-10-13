import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import { indexProductCatalog, type ProductCatalog } from '../_shared/ticketRenderData.ts';
export async function loadPreviewProducts(client:SupabaseClient,occasionId:number):Promise<ProductCatalog> {
  const {data,error}=await client.rpc('get_products_and_types',{p_occasion_id:occasionId});
  if(error)throw error;
  return indexProductCatalog(data,occasionId);
}
