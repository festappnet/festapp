import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const read=path=>readFileSync(new URL('../../../'+path,import.meta.url),'utf8');

test('cross-language limits, capability projection and canonical migration are current',()=>{
    for(const script of ['generate_form_measurement_limits.py','generate_authorization_projection.py','generate_authorization_capabilities.py','assemble-form-measurement-migration.py','assemble-configuration-migration.py']){
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
        for(const key of ['measurementNoDestination','measurementReady','measurementEnabled','measurementDisabled','measurementOrganizationBlocked','measurementRuntimeBlocked','measurementAdvanced','measurementTitle','gtmContainer','gtmHelp','gtmInvalid','measurementScripts','measurementScriptsHelp','measurementScriptsTooLong']){
            assert.ok(flutter[key]?.length,`${locale}.${key}`);assert.equal(flutter[key],web[key]);
        }
    }
});
