import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { OrderResult } from '../../src/components/forms/order_result.js';
import { LocalizationService } from '../../src/services/localization_service.js';
import { SupabaseService } from '../../src/services/supabase_service.js';
import { FormNetwork } from '../../src/components/forms/form_network.js';
import { executeTicketOrderRpc } from '../../../supabase/functions/send-ticket-order/ticketOrderRpc.ts';
for (const locale of ['cs','en','sk','pl','de','uk']) {
    test(`unknown transport outcome is distinguished from rejection in ${locale}`, () => {
        const dom = new JSDOM('<div id="host"></div>');
        globalThis.document = dom.window.document;
        const original = LocalizationService.translations;
        try {
            const catalog = JSON.parse(readFileSync(new URL(`../../../assets/translations/${locale}.json`,import.meta.url)));
            LocalizationService.translations = catalog;
            const host = document.querySelector('#host');
            let returned = false;
            OrderResult.render(host,false,{code:503,errorCode:'ORDER_OUTCOME_UNKNOWN'},{visibleFields:[]},()=>{returned=true;});
            assert.equal(host.querySelector('.result-title').textContent,catalog.PublicOrder.outcomeUnknownTitle);
            assert.equal(host.querySelector('.result-subtitle').textContent,catalog.PublicOrder.outcomeUnknownHint);
            assert.notEqual(host.querySelector('.result-title').textContent,catalog.PublicOrder.orderFailed ?? 'PublicOrder.orderFailed');
            host.querySelector('.btn-back-to-form').click();
            assert.equal(returned,true);
            OrderResult.render(host,false,{code:400},{visibleFields:[]},()=>{});
            assert.equal(host.querySelector('.result-title').textContent,catalog.PublicOrder.orderFailed ?? 'PublicOrder.orderFailed');
        } finally {LocalizationService.translations=original;dom.window.close();}
    });
}

for (const locale of ['cs','en','sk','pl','de','uk']) {
    test(`a real RPC email admission error remains a clear rejection through checkout in ${locale}`, async () => {
        const dom = new JSDOM('<main></main>', {url:'https://tickets.example/form/pout'});
        const previous = {document:globalThis.document, window:globalThis.window, localStorage:globalThis.localStorage,
            client:SupabaseService._client, backend:SupabaseService._backend,
            translations:LocalizationService.translations, locale:LocalizationService.currentLocale};
        Object.assign(globalThis, {document:dom.window.document, window:dom.window, localStorage:dom.window.localStorage});
        const catalog = JSON.parse(readFileSync(new URL(`../../../assets/translations/${locale}.json`,import.meta.url)));
        LocalizationService.translations=catalog;LocalizationService.currentLocale=locale;
        const rawError={code:'PT429', message:'abuse_limit_exceeded', details:JSON.stringify({
            ruleKey:'email.ordinary.recipient.day',policyRevision:1,retryAfterSeconds:6600})};
        const commands=[];
        try {
            for (const principal of [null, 'signed-in-buyer']) {
                SupabaseService._backend={supabaseUrl:'https://capacity.example'};
                SupabaseService._client={
                    auth:{getSession:async()=>({data:{session:principal ? {user:{id:principal}} : null},error:null})},
                    functions:{invoke:async(name,{body})=>{
                        assert.equal(name,'send-ticket-order');commands.push(body.commandId);
                        const response=await executeTicketOrderRpc({rpc:async(rpc,args)=>{
                            assert.equal(rpc,'create_ticket_order_client_sync_v1');
                            assert.equal(args.p_command_id,body.commandId);
                            return {data:null,error:rawError};
                        }},'create_ticket_order_client_sync_v1',{p_order:body.orderDetails,p_command_id:body.commandId});
                        return {data:response.order,error:null};
                    }},
                };
                const payload={form:'capacity-'+principal,email:'buyer@example.invalid',ticket:[]};
                const result=await FormNetwork.submitOrder(payload);
                assert.equal(result.success,false);assert.equal(result.data.code,429);
                assert.equal(result.data.limitReason,'email_recipient');assert.equal(result.data.retryAfterSeconds,6600);
                assert.doesNotMatch(JSON.stringify(result.data),/ruleKey|policyRevision|abuse_limit_exceeded/);
                OrderResult.render(document.querySelector('main'),false,result.data,{visibleFields:[],occasionFeatures:[]},()=>{});
                assert.equal(document.querySelector('.result-title').textContent,catalog.PublicOrder.capacityRegistrationTitle);
                const hint=document.querySelector('.result-subtitle').textContent;
                assert.ok(hint.includes(catalog.PublicOrder.emailRecipientLimit));
                assert.ok(hint.includes(new Intl.RelativeTimeFormat(locale,{numeric:'always'}).format(110,'minute')));
                assert.ok(!hint.includes(catalog.PublicOrder.outcomeUnknownHint));
                await FormNetwork.submitOrder(payload);
                assert.notEqual(commands.at(-1),commands.at(-2),'definitive rejection completes the intent; a new explicit attempt gets a new identity');
            }
        } finally {
            Object.assign(globalThis,{document:previous.document,window:previous.window,localStorage:previous.localStorage});
            SupabaseService._client=previous.client;SupabaseService._backend=previous.backend;
            LocalizationService.translations=previous.translations;LocalizationService.currentLocale=previous.locale;
            dom.window.close();
        }
    });
}

test('RPC capacity errors expose only bounded public reasons and preserve other unknown failures', async () => {
    const accepted={code:200,order:{id:42}};
    for (const data of [accepted,{data:accepted}]) {
        const result=await executeTicketOrderRpc({rpc:async()=>({data,error:null})},'create_ticket_order_client_sync_v1',{});
        assert.deepEqual(result.order,accepted,'successful raw and command-envelope responses retain their order');
    }
    for (const details of ['not JSON', 'null', '{"retryAfterSeconds":-1}', '{"ruleKey":"unknown.secret","retryAfterSeconds":1e30}']) {
        const result=await executeTicketOrderRpc({rpc:async()=>({data:null,error:{code:'PT429',details}})},'create_ticket_order_client_sync_v1',{});
        assert.equal(result.order.code,429);assert.equal(result.order.limitReason,'service');
        assert.equal(result.order.retryAfterSeconds,undefined);
    }
    const result=await executeTicketOrderRpc({rpc:async()=>({data:null,error:{code:'XX000',message:'failure'}})},'create_ticket_order_client_sync_v1',{});
    assert.equal(result.order.code,500,'unproven server failures must still preserve the pending order identity');
});
