import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {parseOrganizationIdentity} from '../../src/components/forms/organization_identity.js';
import {OrganizationIdentityFooter} from '../../src/components/forms/organization_identity_footer.js';
import { LocalizationService } from '../../src/services/localization_service.js';
import {FormModel} from '../../src/components/forms/form_models.js';
const identity={unitId:1,revision:3,legalName:'Spolek <img src=x onerror=alert(1)>',countryCode:'CZ',registrationNumber:'01234567',address:{street:'Ulice 1',city:'Praha',postalCode:'11000'},contactEmail:'info@example.test',website:'javascript:alert(1)'};
test('authorized identity is strict immutable whitelist and missing identity is absent',()=>{
 for(const value of [null,{}, {...identity,revision:0},{...identity,address:{}},{...identity,legalName:null}])assert.equal(parseOrganizationIdentity(value),null);
 assert.equal(parseOrganizationIdentity(identity).verifiedAt,null);
 const verifiedAt='2026-10-18T10:30:00+00:00';
 assert.equal(parseOrganizationIdentity({...identity,verifiedAt}).verifiedAt,verifiedAt);
 for(const verifiedAt of [false,123,'invalid date'])assert.equal(parseOrganizationIdentity({...identity,verifiedAt}),null);
 const parsed=parseOrganizationIdentity({...identity,reviewNote:'private'});assert.ok(Object.isFrozen(parsed));assert.ok(Object.isFrozen(parsed.address));assert.equal(parsed.reviewNote,undefined);
 assert.equal(new FormModel({}).organizationIdentity,null);assert.equal(new FormModel({organizationIdentity:identity}).organizationIdentity.unitId,1);
});
test('footer preserves form input, never submits, renders safe text and clears old identity/dialog',t=>{
 t.mock.method(LocalizationService, 'tr', key => ({'OrganizationVerification.organizer':'Pořadatel','OrganizationVerification.close':'Zavřít'}[key] ?? key));
 const dom=new JSDOM('<form><input name="answer" value="Draft"><div id="footer"></div></form>');global.document=dom.window.document;
 dom.window.HTMLDialogElement.prototype.showModal=function(){this.open=true;};dom.window.HTMLDialogElement.prototype.close=function(){this.open=false;this.dispatchEvent(new dom.window.Event('close'));};
 const host=document.querySelector('#footer');const footer=new OrganizationIdentityFooter(host);let submits=0;document.querySelector('form').addEventListener('submit',e=>{e.preventDefault();submits++;});
 footer.render(identity);assert.equal(host.querySelectorAll('button').length,1);assert.ok(host.querySelector('button').textContent.startsWith('Pořadatel: '));host.querySelector('button').click();assert.equal(submits,0);assert.equal(document.querySelector('input').value,'Draft');assert.equal(host.querySelectorAll('img').length,0);assert.ok(host.querySelector('dialog[aria-labelledby]'));assert.equal(host.querySelector('a[href^="javascript:"]'),null);
 const close=host.querySelector('button.organization-identity-close');assert.equal(close.getAttribute('aria-label'),'Zavřít');assert.ok(close.querySelector('svg[aria-hidden="true"]'));close.click();assert.equal(host.querySelector('dialog'),null);assert.equal(document.activeElement,host.querySelector('button'));assert.equal(submits,0);
 host.querySelector('button').click();
 footer.render(identity);assert.equal(host.querySelectorAll('dialog').length,0);assert.equal(host.querySelectorAll('button').length,1);footer.render(null);assert.equal(host.childElementCount,0);dom.window.close();
});
