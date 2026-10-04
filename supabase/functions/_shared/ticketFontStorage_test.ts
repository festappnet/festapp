import {assertEquals} from 'jsr:@std/assert@1';
import {isMissingTicketFontObject} from './ticketFontStorage.ts';
Deno.test('Storage SDK direct 404 and self-hosted wrapped object 404 are cache misses',async()=>{
  assertEquals(await isMissingTicketFontObject({statusCode:'404'}),true);
  for(const status of [400,404])assertEquals(await isMissingTicketFontObject({originalError:new Response(JSON.stringify({statusCode:'404',error:'not_found',message:'Object not found'}),{status})}),true);
});
Deno.test('Storage authorization, server, bucket and malformed failures never become cache misses',async()=>{
  for(const error of [null,{},new Error('network'),{statusCode:'403'},{statusCode:'500'},
    {originalError:new Response(JSON.stringify({statusCode:'404',error:'not_found',message:'Object not found'}),{status:403})},
    {originalError:new Response(JSON.stringify({statusCode:'404',error:'not_found',message:'Bucket not found'}),{status:400})},
    {originalError:new Response('<html>',{status:400})}])assertEquals(await isMissingTicketFontObject(error),false);
});
