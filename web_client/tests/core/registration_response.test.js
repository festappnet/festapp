import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
let dom,AuthService,SupabaseService,original;
before(async()=>{
 dom=new JSDOM('',{url:'http://localhost/'});
 global.window=dom.window;global.document=dom.window.document;global.HTMLElement=dom.window.HTMLElement;global.customElements=dom.window.customElements;
 ({AuthService}=await import('../../src/services/auth_service.js'));
 ({SupabaseService}=await import('../../src/services/supabase_service.js'));
 original=SupabaseService.getClient;
});
after(()=>{SupabaseService.getClient=original;dom.window.close();});
test('registration preserves duplicate-email status for the localized UI recovery',async()=>{
 SupabaseService.getClient=()=>({functions:{invoke:async()=>({data:{code:409,email:'existing@example.invalid'},error:null})}});
 await assert.rejects(AuthService.register({email:'existing@example.invalid'}),e=>e.code===409);
});
test('registration preserves successful response and transport rejection',async()=>{
 const response={code:200,email:'new@example.invalid'};
 SupabaseService.getClient=()=>({functions:{invoke:async()=>({data:response,error:null})}});
 assert.deepEqual(await AuthService.register({email:response.email}),response);
 const failure=new Error('network unavailable');
 SupabaseService.getClient=()=>({functions:{invoke:async()=>({data:null,error:failure})}});
 await assert.rejects(AuthService.register({email:response.email}),e=>e===failure);
});
