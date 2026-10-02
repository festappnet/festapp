import { assertEquals, assertRejects } from 'jsr:@std/assert@1';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import { loadPreviewProducts } from './products.ts';
import { handlePreview } from './handler.ts';
import { fontBytes, fontMetrics } from '../_shared/ticketGeneration.ts';

Deno.test('editor resolve works with canonical API exposing only public schema', async () => {
  const calls: string[]=[];
  const client=createClient('https://test.invalid','test', {auth:{persistSession:false}, global:{fetch:async(input,init)=>{
    const url=new URL(String(input));
    calls.push(url.pathname);
    const headers=new Headers(init?.headers);
    if(headers.get('Accept-Profile')==='eshop')return new Response(JSON.stringify({code:'PGRST106',message:'Invalid schema: eshop'}),{status:406});
    assertEquals(url.pathname,'/rest/v1/rpc/get_products_and_types');
    assertEquals(JSON.parse(String(init?.body)),{p_occasion_id:7});
    return new Response(JSON.stringify({product_types:[{id:1,type:'spot'},{id:2,type:'food'}],products:[
      {id:11,product_type:1,title:'Vstupenka',price:450,currency_code:'CZK',is_hidden:false},
      {id:22,product_type:2,title:'Večeře',data:{short_title:'Řízek'},price:170,currency_code:'CZK',is_hidden:false},
    ]}),{headers:{'Content-Type':'application/json'}});
  }}});
  const font=await fontBytes();
  const response=await handlePreview(new Request('https://test.invalid',{method:'POST',headers:{Authorization:'Bearer test'},body:JSON.stringify({occasionId:7,mode:'resolve',type:'named'})}),{
    authorize:async()=>true,occasion:async()=>({id:7,features:[],data:{}}),
    products:id=>loadPreviewProducts(client,id),resources:async()=>({font,metrics:fontMetrics(font)}),
  });
  assertEquals(response.status,200);
  const data=await response.json();
  assertEquals(data.data.food,'Večeře: Řízek');
  assertEquals(data.data.price.replace(/\s/g,''),'Cena:620Kč');
  assertEquals(calls,['/rest/v1/rpc/get_products_and_types']);
});
Deno.test('product RPC errors remain visible instead of inventing an offer',async()=>{
  const client=createClient('https://test.invalid','test',{auth:{persistSession:false},global:{fetch:()=>Promise.resolve(new Response(JSON.stringify({message:'database unavailable'}),{status:500,headers:{'Content-Type':'application/json'}}))}});
  await assertRejects(()=>loadPreviewProducts(client,7));
});
