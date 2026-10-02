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
