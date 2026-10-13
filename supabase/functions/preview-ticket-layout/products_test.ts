import {assertEquals,assertRejects} from 'jsr:@std/assert@1';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.58.0';
import {loadPreviewProducts} from './products.ts';
import {rawCatalog} from '../../../test/fixtures/ticket_layout/products.ts';
Deno.test('one public RPC returns a normalized ID catalog including hidden products',async()=>{
 const calls:string[]=[];
 const client=createClient('https://test.invalid','test',{auth:{persistSession:false},global:{fetch:async(input)=>{const url=new URL(String(input));calls.push(url.pathname);return Response.json(rawCatalog);}}});
 const catalog=await loadPreviewProducts(client,7);
 assertEquals(calls,['/rest/v1/rpc/get_products_and_types']);assertEquals(catalog.types.get(123)?.example?.value,'Řízek');assertEquals(catalog.products.has(2),true);
});
Deno.test('catalog failures remain explicit',async()=>{
 const client=createClient('https://test.invalid','test',{auth:{persistSession:false},global:{fetch:async()=>Response.json({message:'unavailable'},{status:500})}});
 await assertRejects(()=>loadPreviewProducts(client,7));
});
