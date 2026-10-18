import test from 'node:test';
import assert from 'node:assert/strict';
import {register} from 'node:module';
import {JSDOM} from 'jsdom';
register('../css_loader.mjs',import.meta.url);
const identity={unitId:1,revision:1,legalName:'Public organizer',countryCode:'CZ',registrationNumber:'01234567',address:{street:'Street',city:'City',postalCode:'12345'},contactEmail:'info@example.test'};
test('page shell owns one identity across status rendering and clears stale loads',async t=>{
 const dom=new JSDOM('<div id="page"></div>',{url:'https://example.test/form/first'});global.window=dom.window;global.document=dom.window.document;global.HTMLElement=dom.window.HTMLElement;global.CustomEvent=dom.window.CustomEvent;window.scrollTo=()=>{};t.after(()=>dom.window.close());
 const [{FormPage},{DbForms},{FormAvailabilityService},{RightsService},{SeoService},{FormModel}]=await Promise.all([import('../../src/components/forms/form_page.js'),import('../../src/components/forms/db_forms.js'),import('../../src/components/forms/form_availability_service.js'),import('../../src/services/rights_service.js'),import('../../src/services/seo_service.js'),import('../../src/components/forms/form_models.js')]);
 t.mock.method(RightsService,'canSeeReservations',()=>false);t.mock.method(SeoService,'updateMetaTags',()=>{});
 t.mock.method(FormAvailabilityService,'renderStatus',host=>{host.replaceChildren(document.createTextNode('Closed'));return true;});
 let resolveOld;t.mock.method(DbForms,'getFormByLink',async link=>link==='old'?await new Promise(resolve=>{resolveOld=resolve;}):link==='missing'?null:new FormModel({link,organizationIdentity:identity}));
 const page=new FormPage('page');t.mock.method(page,'applyTheme',()=>{});
 await page.init('first');assert.equal(document.querySelectorAll('.organization-identity-button').length,1);assert.equal(page.host.textContent,'Closed');
 const old=page.init('old');await page.init('missing');assert.equal(document.querySelectorAll('.organization-identity-button').length,0);resolveOld(new FormModel({link:'old',organizationIdentity:identity}));await old;assert.equal(document.querySelectorAll('.organization-identity-button').length,0);
 await page.init('second');assert.equal(document.querySelectorAll('.organization-identity-button').length,1);page.clear();assert.equal(document.querySelectorAll('.organization-identity-button').length,0);
});
