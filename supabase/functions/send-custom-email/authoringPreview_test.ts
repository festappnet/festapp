import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { authoringPreviewResponse } from "./authoringPreview.ts";
import examples from "../_shared/emailPreviewScenarios.json" with {type:"json"};
import { renderEmail } from "../_shared/emailDelivery.ts";
const input={action:'authoringPreview',entityType:'occasion',entityId:42,organizationId:3,unitId:8,
 code:'TICKET_ORDER_CONFIRMATION',scenario:'zero',locale:'cs',tone:'formal'};
const context={organization:3,unit:8,occasion:42};
const resolved={context,template:{id:1,code:input.code,subject:'{{name}} / {{amount}}',html:'<p>{{name}}</p>{{balanceReasoning}}{{fullOrder}}'},wrapper:{html:'<main>{{content}}</main>'}};
Deno.test('authoring preview uses actual production renderer and frozen zero-price facts without a queue or recipient lookup',async()=>{
 let reads=0;const response=await authoringPreviewResponse(input,'Bearer fixture',{senderAddress:'preview@festapp.net',read:async(_auth,args)=>{assertEquals(args,input);reads++;return resolved;}});
 assertEquals(response.status,200);const result=await response.json();assertEquals(result.synthetic,true);assertEquals(reads,1);assertStringIncludes(result.html,'<main>');
 const sample=examples.records.find(r=>r.templateCode===input.code&&r.scenario==='zero'&&r.locale==='cs'&&r.tone==='formal')!;
 const rendered=await renderEmail({context,from:'preview@festapp.net',to:'preview@example.invalid',templateCode:input.code,
  substitutions:sample.values,subjectSubstitutions:sample.values,requiredLinks:sample.requiredLinks},async()=>resolved);
 assertEquals(result.html,rendered.html);assertEquals(result.subject,rendered.subject);
});
Deno.test('preview rejects recipients, custom substitutions, unsupported scenarios and unauthenticated requests before reading',async()=>{
 const deps={senderAddress:'preview@festapp.net',read:async()=>{throw new Error('must not read');}};
 for(const extra of [{email:'customer@example.com'},{orderId:12},{substitutions:{name:'real'}},{scenario:'unknown'},{entityType:'organization'},{unitId:undefined}])assertEquals((await authoringPreviewResponse({...input,...extra},'Bearer fixture',deps)).status,400);
 assertEquals((await authoringPreviewResponse(input,'',deps)).status,401);
 assertEquals((await authoringPreviewResponse(input,'Bearer fixture',{...deps,read:async()=>null})).status,403);
});
Deno.test('all generated template/currency/language scenarios use the saved template and inherited wrapper exactly once',async()=>{
 for(const sample of examples.records){
  const req={...input,code:sample.templateCode,scenario:sample.scenario,locale:sample.locale,tone:sample.tone};
  const response=await authoringPreviewResponse(req,'Bearer fixture',{senderAddress:'preview@festapp.net',read:async()=>({...resolved,template:{id:1,code:sample.templateCode,subject:'{{name}}',html:'<p>{{name}}</p>{{fullOrder}}'}})});
  assertEquals(response.status,200,JSON.stringify(req));const body=await response.json();assertEquals(body.html.split('<main>').length,2);assertEquals(body.html.split('</main>').length,2);
 }
});
