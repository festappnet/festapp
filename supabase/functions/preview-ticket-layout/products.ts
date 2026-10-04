import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import type { PreviewProduct } from '../_shared/ticketRenderData.ts';

// Canonical PostgREST exposes public only. Keep eshop tables behind the existing RPC.
export async function loadPreviewProducts(client: SupabaseClient, occasionId: number): Promise<PreviewProduct[]> {
  const {data,error}=await client.rpc('get_products_and_types',{p_occasion_id:occasionId});
  if(error)throw error;
  const types=new Map<number,string>((data?.product_types??[]).map((type: {id:number;type:string})=>[type.id,type.type]));
  return (data?.products??[]).map((product: PreviewProduct & {product_type:number})=>({...product,type:types.get(product.product_type)}));
}
