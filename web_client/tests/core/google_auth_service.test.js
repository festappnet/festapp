import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
let Service,AuthService,dom;
before(async()=>{
 dom=new JSDOM('',{url:'https://vstupenky.online/google-auth?google_code=single-use&google_attempt=fixture'});
 global.window=dom.window;global.document=dom.window.document;global.HTMLElement=dom.window.HTMLElement;global.customElements=dom.window.customElements;global.history=dom.window.history;global.sessionStorage=dom.window.sessionStorage;
 ({GoogleAuthService:Service}=await import('../../src/services/google_auth_service.js'));
 ({AuthService}=await import('../../src/services/auth_service.js'));
});
after(()=>dom.window.close());
test('callback query is removed synchronously before any session work',()=>{
 const callback=Service.takeCallback();assert.equal(callback.code,'single-use');assert.equal(window.location.search,'');assert.equal(Service.takeCallback(),null);
});

test('cancelled Google returns to the same creation flow without accepting another attempt', async () => {
 for (const [attempt,expires,expected] of [
  ['organizer',Date.now()+600000,'/login?create=1'],
  ['other',Date.now()+600000,'/google-auth'],
  ['organizer',1,'/google-auth'],
 ]) {
  history.replaceState(null,'','/google-auth?google_error=provider_cancelled&google_attempt=organizer');
  sessionStorage.setItem('festapp-google-attempt-v1',JSON.stringify({attempt,expires,returnPath:'/login?create=1'}));
  const callback=Service.takeCallback();
  assert.equal(window.location.pathname+window.location.search,expected);
  assert.equal(callback.error,'provider_cancelled');
  await assert.rejects(Service.complete(callback),/provider_cancelled/);
  assert.equal(sessionStorage.getItem('festapp-google-attempt-v1'),null);
 }
});
test('claim has one flight, consumes tab verifier and keeps continuation only in memory',async()=>{
 sessionStorage.setItem('festapp-google-attempt-v1',JSON.stringify({attempt:'fixture',verifier:'fixture-verifier',expires:Date.now()+600000,returnPath:'/event'}));
 const request=Service.request;let requests=0;
 Service.request=async()=>{requests++;await new Promise(r=>setTimeout(r,10));return {status:'needs_account_proof',continuation:'rotating-secret'};};
 try{
  const first=Service.complete({attempt:'fixture',code:'handoff'});const second=Service.complete({attempt:'fixture',code:'handoff'});
  assert.equal(first,second);await first;assert.equal(requests,1);assert.equal(sessionStorage.length,0);assert.equal(Service._pending.continuation,'rotating-secret');
 }finally{Service.request=request;Service.cancel();}
});
test('expired and cross-attempt callbacks cannot call the broker',async()=>{
 const request=Service.request;Service.request=async()=>{throw Error('must not invoke');};
 try{
  for(const pending of [{attempt:'other',expires:Date.now()+600000},{attempt:'fixture',expires:1}]){
   sessionStorage.setItem('festapp-google-attempt-v1',JSON.stringify(pending));await assert.rejects(Service.complete({attempt:'fixture',code:'x'}),/attempt_expired/);assert.equal(sessionStorage.length,0);
  }
 }finally{Service.request=request;Service.cancel();}
});
test('Google session uses the existing finalizer exactly once, then clears its proof',async()=>{
 const original=AuthService.completeExternalLogin;let count=0;
 AuthService.completeExternalLogin=async(result)=>{assert.equal(result.userId,'original');count++;};
 Service._pending={returnPath:'/event',continuation:'secret'};
 try{const result=await Service._accept({status:'authenticated',userId:'original'});assert.equal(count,1);assert.equal(result.returnPath,'/event');assert.equal(Service._pending,null);}
 finally{AuthService.completeExternalLogin=original;Service.cancel();}
});

test('consent return keeps only the exact first-party request query', async () => {
 const {safeAuthReturnPath}=await import('../../src/services/google_auth_service.js');
 const valid='/settings/mcp-connect?request='+'R'.repeat(43);
 assert.equal(safeAuthReturnPath(valid),valid);
 for(const bad of [valid+'&next=https://evil.example',valid+'&request=x','//evil.example','/settings/mcp-connect?request=x','/form/test?token=private']) assert.equal(safeAuthReturnPath(bad),'/');
});

test('real Google start and callback preserve organizer creation through account proof', async t => {
 const {SupabaseService}=await import('../../src/services/supabase_service.js');
 const originalWindow=globalThis.window,backend=SupabaseService._backend;
 t.after(()=>{globalThis.window=originalWindow;SupabaseService._backend=backend;Service.cancel();});
 const navigations=[];
 globalThis.window={location:{pathname:'/login',search:'?create=1',origin:'https://vstupenky.online',assign:url=>navigations.push(url)}};
 SupabaseService._backend={supabaseUrl:'https://auth.fixture.invalid'};
 t.mock.method(Service,'request',async(endpoint,body)=>{
  if(endpoint==='start')return {url:'https://auth.fixture.invalid/functions/v1/google-auth-start',attempt:'organizer-fixture'};
  return body.operation==='claim'?{status:'needs_account_proof',continuation:'fixture-proof'}:{status:'authenticated',userId:'organizer'};
 });
 const finalize=t.mock.method(AuthService,'completeExternalLogin',async()=>{});
 await Service.start();
 assert.equal(navigations.length,1);
 assert.equal(JSON.parse(sessionStorage.getItem('festapp-google-attempt-v1')).returnPath,'/login?create=1');
 assert.equal((await Service.complete({attempt:'organizer-fixture',code:'fixture'})).status,'needs_account_proof');
 const result=await Service.advance('prove_existing',{email:'organizer@example.invalid',password:'fixture'});
 assert.equal(result.returnPath,'/login?create=1');
 assert.equal(finalize.mock.calls.length,1);
 assert.equal(sessionStorage.getItem('festapp-google-attempt-v1'),null);
});
