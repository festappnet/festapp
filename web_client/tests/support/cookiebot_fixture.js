// Modeled Cookiebot boundary, never loads the remote CMP or simulates blocking.
// Shape measured on uc.js in Chromium, Firefox and WebKit (2026-11-11): the
// script carries only id, src, data-cbid (and data-blockingmode on auto sites);
// undecided state is consentID/stamp '0', method null; a choice sets hasResponse,
// method 'explicit', consentUTC (Date) and a new consentID equal to consent.stamp.
// renew() keeps the saved choice but sets hasResponse false until a new choice.
// Public booleans/method/regulations/events: https://www.cookiebot.com/en/developer/
// consentUTC cutoff example: https://support.cookiebot.com/hc/en-us/articles/12875664186268
// Cookie record shape: https://support.cookiebot.com/hc/en-us/articles/360006346473
export const consentRevision = 'a'.repeat(32);
export const cookiebotConfig = {provider:'cookiebot',organization:1,unit:2,consentRevision,
 cbid:'12345678-1234-1234-1234-123456789abc',origin:'https://host.example',
 consentValidFrom:'2026-01-01T00:00:00.000Z',maxAgeSeconds:180*86400};
export function cookiebotFixture(win,{choice=null,blocking='auto'}={}) {
 const script=win.document.createElement('script');script.id='Cookiebot';
 script.src='https://consent.cookiebot.com/uc.js';script.setAttribute('data-cbid',cookiebotConfig.cbid);
 if(blocking)script.setAttribute('data-blockingmode',blocking);
 script.type='text/javascript';win.document.head.append(script);
 const cmp=win.Cookiebot={consent:{stamp:'0',necessary:true,preferences:false,statistics:false,marketing:false,method:null},
  consentID:'0',consentUTC:null,hasResponse:false,consented:false,declined:false,isRenewal:false,
  responseMode:'leveloptin',consentLevel:'strict',regulations:{gdprApplies:true,ccpaApplies:false,lgpdApplies:false}};
 const event=name=>win.dispatchEvent(new win.CustomEvent(name));
 let serial=0;
 // Measured encoding: quotes and commas percent-encoded, keys unquoted.
 const store=record=>{
  const fields=Object.entries(record).map(([key,value])=>key+':'+(typeof value==='string'?"'"+value+"'":String(value)));
  win.document.cookie='CookieConsent='+('{'+fields.join(',')+'}').replace(/'/g,'%27').replace(/,/g,'%2C')+';path=/';
 };
 const choose=value=>{
  if(value===null){
   win.document.cookie='CookieConsent=;max-age=0;path=/';
   Object.assign(cmp,{hasResponse:false,consented:false,declined:false,consentID:'0',consentUTC:null,isRenewal:false});
   Object.assign(cmp.consent,{stamp:'0',preferences:false,statistics:false,marketing:false,method:null});
   event('CookiebotOnDialogDisplay');return;
  }
  const preferences=value.preferences===true,statistics=value.analytics===true,marketing=value.marketing===true;
  const utc=win.Date.now(),stamp='Q2hvaWNl'+(++serial)+'+saved/'+win.Math.random().toString(36).slice(2)+'==';
  Object.assign(cmp.consent,{stamp,necessary:true,preferences,statistics,marketing,method:'explicit'});
  cmp.consentID=stamp;cmp.consentUTC=new win.Date(utc);cmp.hasResponse=true;
  cmp.consented=preferences||statistics||marketing;cmp.declined=!cmp.consented;
  store({stamp,necessary:true,preferences,statistics,marketing,method:'explicit',ver:1,utc,region:'cz'});
  event('CookiebotOnConsentReady');event('CookiebotOnLoad');event(cmp.declined?'CookiebotOnDecline':'CookiebotOnAccept');
 };
 const renew=()=>{cmp.hasResponse=false;cmp.isRenewal=true;event('CookiebotOnDialogDisplay');};
 choose(choice);
 return {cmp,script,choose,renew,store,event};
}
