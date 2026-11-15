import test from 'node:test';
import assert from 'node:assert/strict';
import {createComplianzSource} from '../../src/embed/host_complianz.js';
import {createCookiebotSource} from '../../src/embed/host_cookiebot.js';
import {createCookieConsentSource} from '../../src/embed/host_cookieconsent.js';
import {createWixConsentSource} from '../../src/embed/host_wix_consent.js';
const origin='https://website.example',consentRevision='a'.repeat(32);
const config=provider=>({provider,organization:1,unit:2,origin,consentRevision});
const legacy={policyId:'obsolete',cbid:'obsolete',revision:999,consentValidFrom:'invalid',maxAgeSeconds:0};
const choice={consentRevision,analytics:true,marketing:true};
for(const extra of [{},legacy]) {
 const label=Object.keys(extra).length?'legacy export':'provider-only export';
 test(`Complianz ${label} follows live policy and rejects stale cookie`,()=>{
  const cookies={policy_id:'42',statistics:'allow',marketing:'allow'};
  const win={complianz:{consenttype:'optin',current_policy_id:'42'},cmplz_get_cookie:k=>cookies[k],cmplz_get_banner_status:()=> 'dismissed',cmplz_has_consent:()=>true};
  const source=createComplianzSource(win,{...config('complianz'),...extra});
  assert.deepEqual(source.read(),choice);
  win.complianz.current_policy_id='43';assert.equal(source.read(),null);
  cookies.policy_id='43';assert.deepEqual(source.read(),choice);
  win.complianz.current_policy_id='invalid';cookies.policy_id='invalid';assert.equal(source.read(),null);
 });
 test(`CookieConsent ${label} requires live positive revision and valid saved consent`,()=>{
  let revision=42,valid=true;
  const cookie={revision:42,categories:['analytics','marketing'],consentId:'saved-choice',consentTimestamp:new Date().toISOString(),lastConsentTimestamp:new Date().toISOString(),expirationTime:Date.now()+86400000,services:{analytics:[],marketing:[]}};
  const win={Date,CookieConsent:{validConsent:()=>valid,getConfig:k=>({revision,mode:'opt-in',categories:{analytics:{},marketing:{}}})[k],getCookie:()=>cookie,acceptedCategory:()=>true}};
  const source=createCookieConsentSource(win,{...config('cookieconsent'),...extra});
  assert.deepEqual(source.read(),choice);
  revision=43;assert.equal(source.read(),null);
  cookie.revision=43;assert.deepEqual(source.read(),choice);
  valid=false;assert.equal(source.read(),null);valid=true;
  revision=0;cookie.revision=0;assert.equal(source.read(),null);
 });
 test(`Cookiebot ${label} requires consistent loader, persisted stamp and sane time`,()=>{
  const id='12345678-1234-1234-1234-123456789abc';let attribute=id;
  const script={src:'https://consent.cookiebot.com/uc.js',getAttribute:k=>k==='data-cbid'?attribute:null};
  const win={Date,location:{origin},document:{baseURI:origin,cookie:"CookieConsent={stamp:'saved-stamp'}",querySelectorAll:()=>[script]},Cookiebot:{consent:{method:'explicit',necessary:true,preferences:false,statistics:true,marketing:true,stamp:'saved-stamp'},consented:true,declined:false,hasResponse:true,regulations:{gdprApplies:true,ccpaApplies:false,lgpdApplies:false},consentID:'saved-stamp',consentUTC:new Date('2020-01-01T00:00:00Z')}};
  const source=createCookiebotSource(win,{...config('cookiebot'),...extra});
  assert.deepEqual(source.read(),choice);
  script.src+='?cbid=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';assert.equal(source.read(),null);
  attribute='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';assert.deepEqual(source.read(),choice);
  win.document.cookie='';assert.equal(source.read(),null);
  win.document.cookie="CookieConsent={stamp:'saved-stamp'}";
  win.Cookiebot.consentUTC=new Date(Date.now()+120000);assert.equal(source.read(),null);
 });
 test(`Wix ${label} requires saved policy with nonfuture date`,()=>{
  const saved={defaultPolicy:false,createdDate:'2020-01-01T00:00:00.000Z',policy:{essential:true,functional:false,analytics:true,advertising:true,dataToThirdParty:true}};
  const win={Date,location:{origin},consentPolicyManager:{getCurrentConsentPolicy:()=>saved}};
  const source=createWixConsentSource(win,{...config('wix'),...extra});
  assert.deepEqual(source.read(),choice);
  saved.defaultPolicy=true;assert.equal(source.read(),null);saved.defaultPolicy=false;
  saved.createdDate=new Date(Date.now()+120000);assert.equal(source.read(),null);
 });
}
