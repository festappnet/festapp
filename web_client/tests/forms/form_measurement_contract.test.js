import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {measurementConsent, analyticsPayload, measurementDataLayerPayload} from '../../src/components/forms/form_measurement_contract.js';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const read=path=>readFileSync(new URL('../../../'+path,import.meta.url),'utf8');

test('cross-language limits, capability projection and canonical migration are current',()=>{
    for(const script of ['generate_form_measurement_limits.py','generate_authorization_projection.py','generate_authorization_capabilities.py','assemble-form-measurement-migration.py','assemble-configuration-migration.py','assemble-form-measurement-consent-migration.py']){
        execFileSync('python3',['automation/'+script,'--check'],{cwd:root,stdio:'pipe'});
    }
});

test('embed is a deterministic build from the shared allowlisted payload contract',()=>{
 execFileSync(process.execPath,['web_client/scripts/build_embed.mjs','--check'],{cwd:root,stdio:'pipe'});
});

test('every supported locale has complete measurement labels in both clients',()=>{
    for(const locale of ['cs','en','sk','de','pl','uk']){
        const flutter=JSON.parse(read(`assets/translations/${locale}.json`)).FeatureFormSettings;
        const web=JSON.parse(read(`web_client/public/assets/translations/${locale}.json`)).FeatureFormSettings;
        for(const key of ['measurementConsentTitle','measurementConsentAnalyticsDescription','measurementConsentMarketing','measurementConsentMarketingDescription','measurementConsentLayout','measurementConsentLayoutBar','measurementConsentLayoutModal','measurementConsentCustomTitle','measurementConsentCustomTitleHelp','measurementConsentCustomText','measurementConsentCustomTextHelp','measurementConsentAccept','measurementConsentSave','measurementConsentClose','measurementConsentPrivacy','measurementNoDestination','measurementReady','measurementEnabled','measurementDisabled','measurementOrganizationBlocked','measurementRuntimeBlocked','measurementAdvanced','measurementTitle','gtmContainer','gtmHelp','gtmInvalid','measurementScripts','measurementScriptsHelp','measurementScriptsTooLong']){
            assert.ok(flutter[key]?.length,`${locale}.${key}`);assert.equal(flutter[key],web[key]);
        }
    }
});

test('consent state grants only strict true purposes and a boolean stays analytics only',()=>{
    assert.deepEqual(measurementConsent(true),{analytics:true,marketing:false});
    for(const input of [false,null,undefined,'true',1,{},{analytics:'true',marketing:1}]) assert.deepEqual(measurementConsent(input),{analytics:false,marketing:false});
    assert.deepEqual(measurementConsent({marketing:true,extra:true}),{analytics:false,marketing:true});
});

test('the fixed consent text names advertising and sharing in every language',()=>{
    const words={cs:/reklam/i,en:/advertising/i,sk:/reklam/i,de:/werb/i,pl:/reklam/i,uk:/реклам/i};
    for(const [locale,word] of Object.entries(words)) for(const root of ['assets','web_client/public/assets']) {
        const strings=JSON.parse(read(`${root}/translations/${locale}.json`)).FeatureFormSettings;
        for(const key of ['measurementConsentTitle','measurementConsentDescription','measurementConsentMarketingDescription']) assert.match(strings[key],word,`${root} ${locale}.${key}`);
    }
});


test('dataLayer projection owns embedded event semantics without changing the wire contract', () => {
    const page = {event: 'page_view', form_embedded: 'untrusted', private: 'secret'};
    assert.deepEqual(analyticsPayload(page), {event: 'page_view'});
    assert.deepEqual(measurementDataLayerPayload(page, {embedded: true}), {page_type: null, user_type: 'b2c', language: null, event: 'form_page_view', form_embedded: true});
    for (const embedded of [false, undefined, 'true', 1]) {
        assert.deepEqual(measurementDataLayerPayload(page, {embedded}), {page_type: null, user_type: 'b2c', language: null, event: 'page_view', form_embedded: false});
    }
    assert.equal(page.event, 'page_view', 'projection does not mutate the source');
    assert.equal(analyticsPayload({event: 'form_page_view'}), null, 'destination event is not a wire event');
    assert.equal(measurementDataLayerPayload({event: 'unknown'}, {embedded: true}), null);
    assert.deepEqual(measurementDataLayerPayload({page_type: 'sale_opening', language: 'cs'}, {embedded: true}),
        {page_type: 'sale_opening', user_type: 'b2c', language: 'cs', form_embedded: true});
});

test('current wire events survive a pre-change protocol 3 receiver during a rolling upgrade', async () => {
    const previous = await import('../fixtures/measurement_protocol_3/contract.mjs');
    for (const event of ['page_view', 'form_start', 'form_submit_error']) {
        const wire = analyticsPayload({event});
        assert.deepEqual(previous.analyticsPayload(wire), wire);
        assert.equal(measurementDataLayerPayload(wire, {embedded: true}).event,
            event === 'page_view' ? 'form_page_view' : event);
    }
});

test('destination projection rebuilds scoped page context without trusting event or context extras',()=>{
 const input={event:'form_start',page_type:'confirmation',language:'de'};
 const pageContext={page_type:'product',language:'cs',user_type:'staff',email:'private@example.test',page_location:'https://private.invalid'};
 assert.deepEqual(measurementDataLayerPayload(input,{embedded:true,pageContext}),
  {page_type:'product',user_type:'b2c',language:'cs',event:'form_start',form_embedded:true});
 for(const pageContext of [null,{page_type:'private',language:'de'}]){
  assert.deepEqual(measurementDataLayerPayload(input,{embedded:true,pageContext}),
   {page_type:null,user_type:'b2c',language:null,event:'form_start',form_embedded:true});
 }
 assert.deepEqual(measurementDataLayerPayload({page_type:'checkout'},{embedded:true,pageContext}),
  {page_type:'checkout',user_type:'b2c',form_embedded:true},'a new page replaces prior context completely');
});
