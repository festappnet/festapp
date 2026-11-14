import {assertEquals,assert,assertRejects} from 'jsr:@std/assert@1';
import {GoogleWallet,googleSigner,walletDate,walletDocuments,walletIds} from './googleWallet.ts';
const identity={issuer:'123456',environment:'local-immutable',organization:3,occasion:9,ticketId:44};
const projection:any={branding:{APP_NAME:'vstupenky.online',DEFAULT_URL:'https://vstupenky.online'},state:'ACTIVE',ticket:{id:44,ticket_symbol:'ČÍSLO-1',order_product_ticket:[{spot_title:'12',spot_group_title:'A',product:{title:'Dospělý'}}]},occasion:{id:9,organization:3,title:'Večer hudby',start_time:'2026-07-01T18:00:00Z',end_time:'2026-07-02T00:00:00Z',data:{timezone:'Europe/Prague',place_name:'Kulturní dům'}}};
Deno.test('Wallet identities isolate environments/tenants and preserve exact QR without purchaser data',async()=>{
 const ids=await walletIds(identity);assertEquals(await walletIds(identity),ids);
 assert((await walletIds({...identity,environment:'production'})).objectId!==ids.objectId);
 assert((await walletIds({...identity,organization:4})).classId!==ids.classId);
 const docs=walletDocuments(ids,projection);
 assertEquals(docs.objectBody.barcode.value,'ČÍSLO-1');assertEquals(docs.objectBody.seatInfo.seat.defaultValue.value,'12');
 assertEquals(docs.classBody.dateTime.start,'2026-07-01T20:00:00+02:00');
 assertEquals(walletDate('2026-12-01T18:00:00Z','Europe/Prague'),'2026-12-01T19:00:00+01:00');
 assert(!JSON.stringify(docs).includes('purchaser'));assert(!Object.hasOwn(docs.objectBody,'ticketHolderName'));
 const standing=walletDocuments(ids,{...projection,ticket:{...projection.ticket,order_product_ticket:[]}});assert(!Object.hasOwn(standing.objectBody,'seatInfo'));
});
Deno.test('Wallet displays the stored portal brand and platform logo without changing pass identity',async()=>{
 const ids=await walletIds(identity);
 for(const [name,origin,logo] of [
  ['vstupenky.online','https://vstupenky.online','regional'],
  ['Festapp Tickets','https://tickets.festapp.net','global'],
 ]){
  const documents=walletDocuments(ids,{...projection,branding:{APP_NAME:name,DEFAULT_URL:origin,WALLET_LOGO_URL:`https://img.festapp.net/assets/${logo}.png`},occasion:{...projection.occasion,data:{...projection.occasion.data,logo:'https://img.festapp.net/images/event-logo.png'}}});
  assertEquals(documents.classBody.issuerName,name);
  assertEquals(documents.classBody.logo!.sourceUri.uri,`https://img.festapp.net/assets/${logo}.png?f=png`);
  assertEquals(documents.classBody.id,ids.classId);
  assertEquals(documents.objectBody.barcode.value,projection.ticket.ticket_symbol);
 }
 const removed=walletDocuments(ids,{...projection,branding:{...projection.branding,WALLET_LOGO_URL:'https://img.festapp.net/assets/portal.png'},occasion:{...projection.occasion,ticketFeature:{wallet_appearance:{logo:null}}}});
 assert(!Object.hasOwn(removed.classBody,'logo'));
 await assertRejects(async()=>walletDocuments(ids,{...projection,branding:{APP_NAME:'',DEFAULT_URL:'https://tenant.invalid'}}));
});
Deno.test('real RSA signature signs short-lived reference-only Save JWT',async()=>{
 const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
 const bytes=new Uint8Array(await crypto.subtle.exportKey('pkcs8',keys.privateKey));
 const signer=await googleSigner({client_email:'wallet@example.invalid',private_key:'-----BEGIN PRIVATE KEY-----\n'+btoa(String.fromCharCode(...bytes))+'\n-----END PRIVATE KEY-----'});
 const google=new GoogleWallet('wallet@example.invalid',signer,fetch,()=>1234567000);
 const url=await google.saveUrl('1234.object','https://tenant.invalid');assert(url.length<1800);
 const jwt=url.split('/').pop()!;const [head,body,signature]=jwt.split('.');
 const decode=(s:string)=>Uint8Array.from(atob(s.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0));
 assert(await crypto.subtle.verify('RSASSA-PKCS1-v1_5',keys.publicKey,decode(signature),new TextEncoder().encode(head+'.'+body)));
 const payload=JSON.parse(new TextDecoder().decode(decode(body)));assertEquals(payload.iss,'wallet@example.invalid');assertEquals(payload.aud,'google');assertEquals(payload.exp-payload.iat,300);
 assertEquals(payload.payload,{eventTicketObjects:[{id:'1234.object'}]});
 const multi=await google.saveUrl(['1234.first','1234.second','1234.third'],'https://tenant.invalid');
 const multiPayload=JSON.parse(new TextDecoder().decode(decode(multi.split('/').pop()!.split('.')[1])));
 assertEquals(multiPayload.payload.eventTicketObjects.map((item:any)=>item.id),['1234.first','1234.second','1234.third']);assert(multi.length<=1800);
});
Deno.test('Google executor handles concurrent-create 409, 429 and 5xx with fenced retries and cached OAuth',async()=>{
 const paths:string[]=[],methods:string[]=[],waits:number[]=[];let fenced=0;
 const responses=[{access_token:'access',expires_in:3600},404,409,{id:'123.object'},429,503,{id:'123.object',state:'COMPLETED'}];
 const google=new GoogleWallet('wallet@example.invalid',async()=> 'signed',async(input,init)=>{
  paths.push(String(input));methods.push(init?.method??'GET');const next=responses.shift();
  return typeof next==='number'?new Response('{}',{status:next}):Response.json(next);
 },Date.now,async ms=>{waits.push(ms);});
 const result=await google.upsert('eventTicketObject',{id:'123.object',state:'COMPLETED'},async()=>{fenced++;});
 assertEquals(result.state,'COMPLETED');assertEquals(methods,['POST','GET','POST','GET','PUT','PUT','PUT']);assertEquals(fenced,7);assertEquals(waits.length,2);
 assertEquals(paths.filter(x=>x.includes('oauth2')).length,1);
});
Deno.test('revoked/deleted pass is inactivated without QR, and missing remote identity is harmless',async()=>{
 let request:any;
 const google=new GoogleWallet('wallet@example.invalid',async()=> 'signed',async(input,init)=>{
  if(String(input).includes('oauth2'))return Response.json({access_token:'x',expires_in:3600});
  request=init;return new Response('{}',{status:404});
 });
 await google.synchronize({classId:'123.class',objectId:'123.object'},{state:'INACTIVE',occasion:null,ticket:null},async()=>{});
 assertEquals(JSON.parse(request.body),{state:'INACTIVE'});
});
Deno.test('lost lease aborts before transport, Google failure remains recoverable with same identity',async()=>{
 let writes=0;const google=new GoogleWallet('wallet@example.invalid',async()=> 'signed',async()=>{writes++;return new Response('{}',{status:503});},Date.now,async()=>{});
 await assertRejects(()=>google.upsert('eventTicketObject',{id:'123.object'},async()=>{throw new Error('wallet_lease_lost');}));assertEquals(writes,0);
});
Deno.test('Wallet appearance shares compatible colors and public images with the editor contract',async()=>{
 const {googleWalletAppearance}=await import('./googleWalletAppearance.ts');
 const cases=JSON.parse(await Deno.readTextFile(new URL('../../../packages/festapp_contracts/ticket-wallet-appearance-cases.json',import.meta.url)));
 for(const sample of cases)assertEquals(JSON.parse(JSON.stringify(googleWalletAppearance(sample.feature,sample.data))),sample.expected,sample.name);
 const docs=walletDocuments(await walletIds(identity),{...projection,occasion:{...projection.occasion,ticketFeature:cases[1].feature,data:{...projection.occasion.data,...cases[1].data}}});
 assertEquals(docs.classBody.hexBackgroundColor,'#123abc');assertEquals(docs.classBody.logo!.sourceUri.uri,cases[1].expected.logo);
});
Deno.test('class and object executors own disjoint resources, repair only writes actual remote drift',async()=>{
 const ids=await walletIds(identity);const remote=new Map<string,any>();const writes:string[]=[];
 const google=new GoogleWallet('wallet@example.invalid',async()=> 'signed',async(input,init)=>{
  if(String(input).includes('oauth2'))return Response.json({access_token:'x',expires_in:3600});
  const path=decodeURIComponent(String(input).split('/v1/')[1]);const method=init?.method??'GET';
  if(method==='GET')return remote.has(path)?Response.json(remote.get(path)):new Response('{}',{status:404});
  const body=JSON.parse(String(init?.body));const key=method==='POST'?path+'/'+body.id:path;
  writes.push(key);const saved={...body,...(key.startsWith('eventTicketClass')?{reviewStatus:'APPROVED'}:{})};remote.set(key,saved);return Response.json(saved);
 });
 await google.synchronizeClass(ids,projection,async()=>{});
 await google.synchronize(ids,projection,async()=>{});
 assertEquals(writes.map(x=>x.split('/')[0]),['eventTicketClass','eventTicketObject']);
 await google.synchronizeClass(ids,projection,async()=>{});await google.synchronize(ids,projection,async()=>{});
 assertEquals(writes.length,2,'healthy repair must not rewrite cards');
 // A delayed stale provider write after a successful newer attempt is repaired.
 remote.set('eventTicketObject/'+ids.objectId,{...remote.get('eventTicketObject/'+ids.objectId),state:'COMPLETED'});
 await google.synchronize(ids,projection,async()=>{});
 assertEquals(remote.get('eventTicketObject/'+ids.objectId).state,'ACTIVE');assertEquals(writes.length,3);
});
Deno.test('timeout after accepted object write retries the same identity without a second class writer',async()=>{
 const ids=await walletIds(identity);let remote:any=null;let timedOut=false;let writes=0;
 const google=new GoogleWallet('wallet@example.invalid',async()=> 'signed',async(input,init)=>{
  if(String(input).includes('oauth2'))return Response.json({access_token:'x',expires_in:3600});
  assert(!String(input).includes('eventTicketClass'));
  if(init?.method==='GET')return remote?Response.json(remote):new Response('{}',{status:404});
  remote=JSON.parse(String(init?.body));writes++;
  if(!timedOut){timedOut=true;throw new DOMException('accepted but response lost','TimeoutError');}
  return Response.json(remote);
 });
 await assertRejects(()=>google.synchronize(ids,projection,async()=>{}),DOMException);
 await google.synchronize(ids,projection,async()=>{});
 assertEquals(remote.id,ids.objectId);assertEquals(writes,1,'retry reads the accepted state');
});
