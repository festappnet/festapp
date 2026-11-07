import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {measurementConsent} from '../../src/components/forms/form_measurement_contract.js';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const read=path=>readFileSync(new URL('../../../'+path,import.meta.url),'utf8');

test('cross-language limits, capability projection and canonical migration are current',()=>{
    for(const script of ['generate_form_measurement_limits.py','generate_authorization_projection.py','generate_authorization_capabilities.py','assemble-form-measurement-migration.py','assemble-configuration-migration.py','assemble-form-measurement-consent-migration.py']){
        execFileSync('python3',['automation/'+script,'--check'],{cwd:root,stdio:'pipe'});
    }
});

test('embed is a deterministic build from the shared contact-free contract',()=>{
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
