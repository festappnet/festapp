import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const read=path=>readFileSync(new URL('../../../'+path,import.meta.url),'utf8');

test('cross-language limits, capability projection and canonical migration are current',()=>{
    for(const script of ['generate_form_measurement_limits.py','generate_authorization_projection.py','generate_authorization_capabilities.py','assemble-form-measurement-migration.py']){
        execFileSync('python3',['automation/'+script,'--check'],{cwd:root,stdio:'pipe'});
    }
});

test('classic embed host has the same field whitelist as the form owner',()=>{
    const module=read('web_client/src/components/forms/form_datalayer.js');
    const validator=module.slice(module.indexOf('const ecommerceEvents'),module.indexOf('export function publicFormLocation')).trim().replaceAll('export function','function');
    const host=read('web_client/public/embed.js').split('\n').map(line=>line.startsWith('    ')?line.slice(4):line).join('\n');
    assert.ok(host.includes(validator));
});

test('every supported locale has complete measurement labels in both clients',()=>{
    for(const locale of ['cs','en','sk','de','pl','uk']){
        const flutter=JSON.parse(read(`assets/translations/${locale}.json`)).FeatureFormSettings;
        const web=JSON.parse(read(`web_client/public/assets/translations/${locale}.json`)).FeatureFormSettings;
        for(const key of ['enhancedConversions','enhancedConversionsHelp','measurementTitle','gtmContainer','gtmHelp','gtmInvalid','measurementScripts','measurementScriptsHelp','measurementScriptsTooLong']){
            assert.ok(flutter[key]?.length,`${locale}.${key}`);assert.equal(flutter[key],web[key]);
        }
    }
});


test('embed format validation mirrors the existing email and phone helpers',()=>{
    const host=read('web_client/public/embed.js').split('\n').map(line=>line.startsWith('    ')?line.slice(4):line).join('\n');
    const email=read('web_client/src/logic/email_address.js');
    assert.ok(host.includes(email.slice(email.indexOf('export function isValidEmail')).trim().replace('export function','function')));
    const phone=read('web_client/src/utils/phone_formatter.js');
    assert.ok(host.includes(phone.slice(phone.indexOf('export function normalizeE164Phone'),phone.indexOf('export class PhoneFormatter')).trim().replace('export function','function')));
});
