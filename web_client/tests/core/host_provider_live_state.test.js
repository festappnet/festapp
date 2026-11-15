import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {createComplianzSource} from '../../src/embed/host_complianz.js';
import {createCookiebotSource} from '../../src/embed/host_cookiebot.js';
import {createCookieConsentSource} from '../../src/embed/host_cookieconsent.js';
import {createWixConsentSource} from '../../src/embed/host_wix_consent.js';
import {cookiebotFixture,cookiebotConfig} from '../support/cookiebot_fixture.js';
import {cookieconsentFixture} from '../support/cookieconsent_fixture.js';
const consentRevision='a'.repeat(32), origin='https://host.example';
const config=provider=>({provider,organization:1,unit:2,origin,consentRevision});
const both={consentRevision,analytics:true,marketing:true};
const coverage=()=>({consentValidFrom:new Date(Date.now()-1000).toISOString(),maxAgeSeconds:86400});

test('Complianz cannot silently relabel a saved policy after coverage changes',()=>{
 const cookies={policy_id:'42',statistics:'allow',marketing:'allow'};
 const win={complianz:{consenttype:'optin',current_policy_id:'42'},cmplz_get_cookie:k=>cookies[k],cmplz_get_banner_status:()=> 'dismissed',cmplz_has_consent:()=>true};
 assert.equal(createComplianzSource(win,config('complianz')).read(),null);
 const source=createComplianzSource(win,{...config('complianz'),policyId:'42'});
 assert.deepEqual(source.read(),both);
 win.complianz.current_policy_id='43';cookies.policy_id='43';assert.equal(source.read(),null);
 assert.deepEqual(createComplianzSource(win,{...config('complianz'),policyId:'43'}).read(),both);
});

test('Cookiebot needs confirmed coverage even when its cookie and API agree',t=>{
 const win=new JSDOM('',{url:origin,runScripts:'outside-only'}).window;t.after(()=>win.close());
 const {cmp}=cookiebotFixture(win,{choice:both});
 const c={...config('cookiebot'),...coverage()};
 const source=createCookiebotSource(win,c);
 assert.deepEqual(source.read(),both,'CBID need not be entered manually');
 assert.equal(createCookiebotSource(win,config('cookiebot')).read(),null);
 cmp.consentUTC=new win.Date(Date.parse(c.consentValidFrom)-1);assert.equal(source.read(),null);
 cmp.consentUTC=new win.Date(c.consentValidFrom);assert.deepEqual(source.read(),both);
 win.Date.now=()=>cmp.consentUTC.getTime()+c.maxAgeSeconds*1000;assert.equal(source.read(),null);
});

test('Cookiebot legacy CBID, cutoff and shorter lifetime remain binding',t=>{
 const win=new JSDOM('',{url:origin,runScripts:'outside-only'}).window;t.after(()=>win.close());
 const {cmp,script}=cookiebotFixture(win,{choice:both});
 const source=createCookiebotSource(win,cookiebotConfig);
 assert.deepEqual(source.read(),both);
 script.setAttribute('data-cbid','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');assert.equal(source.read(),null);
 script.setAttribute('data-cbid',cookiebotConfig.cbid);
 cmp.consentUTC=new win.Date('2020-01-01T00:00:00Z');assert.equal(source.read(),null);
});

test('CookieConsent live revision also requires a saved decision after server confirmation',async t=>{
 const win=new JSDOM('',{url:origin,runScripts:'outside-only',pretendToBeVisual:true}).window;t.after(()=>win.close());
 const {cmp,store}=await cookieconsentFixture(win,{choice:both,config:{revision:43}});
 const c={...config('cookieconsent'),...coverage()};
 const source=createCookieConsentSource(win,c);
 assert.deepEqual(source.read(),both);
 assert.equal(createCookieConsentSource(win,config('cookieconsent')).read(),null);
 assert.equal(createCookieConsentSource(win,{...c,revision:42}).read(),null,'legacy revision pin is enforced');
 const cookie=cmp.getCookie();
 cookie.lastConsentTimestamp=new Date(Date.parse(c.consentValidFrom)-1).toISOString();store(cookie);assert.equal(source.read(),null);
 cookie.lastConsentTimestamp=c.consentValidFrom;store(cookie);assert.deepEqual(source.read(),both);
 win.Date.now=()=>Date.parse(c.consentValidFrom)+c.maxAgeSeconds*1000;assert.equal(source.read(),null);
});

for(const extra of [{}, {consentValidFrom:'invalid'}, {maxAgeSeconds:0}, {maxAgeSeconds:365*86400+1}])
 test('Wix never imports missing or invalid coverage '+JSON.stringify(extra),()=>{
  const win={Date,location:{origin},consentPolicyManager:{getCurrentConsentPolicy:()=>({defaultPolicy:false,createdDate:new Date(),policy:{essential:true,functional:false,analytics:true,advertising:true,dataToThirdParty:true}})}};
  const c=Object.keys(extra).length?{...config('wix'),...coverage(),...extra}:config('wix');
  assert.equal(createWixConsentSource(win,c).read(),null);
 });

test('Wix coverage and lifetime are enforced even while saved policy remains available',()=>{
 const c={...config('wix'),...coverage()};
 const saved={defaultPolicy:false,createdDate:c.consentValidFrom,policy:{essential:true,functional:false,analytics:true,advertising:true,dataToThirdParty:true}};
 let now=Date.now();
 const win={Date:{now:()=>now},location:{origin},consentPolicyManager:{getCurrentConsentPolicy:()=>saved}};
 const source=createWixConsentSource(win,c);
 assert.deepEqual(source.read(),both);
 saved.createdDate='2020-01-01T00:00:00.000Z';assert.equal(source.read(),null);
 saved.createdDate=c.consentValidFrom;now=Date.parse(c.consentValidFrom)+c.maxAgeSeconds*1000;assert.equal(source.read(),null);
});
