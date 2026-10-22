// Synthetic isolated Edge worker. Never deploy this entrypoint to production.
import {handlePreview} from '../../supabase/functions/preview-ticket-layout/handler.ts';
import {loadLayoutResources} from '../../supabase/functions/_shared/ticketGeneration.ts';
const admission={abuseLimits:{'document.input.bytes':1048576,'document.asset.bytes':5242880,'document.output.bytes':16777216,'document.output.pages':20}};
let resources=0;
Deno.serve(async req=>{
 const start=performance.now();
 const response=await handlePreview(req,{
  authorize:async()=>admission,
  occasion:async()=>({id:7,organization:1,title:'Český zkušební večer',features:[{code:'ticket',ticket_type:'named'}],data:{place_name:'Kulturní dům'}}),
  products:async()=>({types:new Map(),products:new Map()}),
  resources:async(...args)=>{resources++;return await loadLayoutResources(...args);},
  font:()=>{throw Error('font dependency forbidden');},
 });
 response.headers.set('x-canary-resource-reads',String(resources));
 response.headers.set('x-canary-wall-ms',String(performance.now()-start));
 return response;
});
