import {parseConsentExport, createManagedConsentSource} from '../../../web_client/src/embed/host_consent_export.js';
import {SERVICE_ORIGIN, TAG_NAME} from './config.js';

export function elementConsent(element) {
  return element.getAttribute('consent-enabled') === 'on'
    ? parseConsentExport(element.getAttribute('consent-export'), {serviceOrigin:SERVICE_ORIGIN, websiteOrigin:element.ownerDocument.defaultView.location.origin}) : null;
}
export function ensureHelper(document) {
  const win=document.defaultView;
  if (win.FestappEmbed || win.__festappEmbedV1) return Promise.resolve(win.FestappEmbed);
  let script=[...document.scripts].find(script => script.src === `${SERVICE_ORIGIN}/embed.js`);
  const created=!script;
  script ??= document.createElement('script');
  const ready=new Promise(resolve=>{
    script.addEventListener('load',()=>resolve(win.FestappEmbed),{once:true});
    script.addEventListener('error',()=>{script.remove();resolve(null);},{once:true});
  });
  if (created) {script.src=`${SERVICE_ORIGIN}/embed.js`;script.async=true;document.head.append(script);}
  return ready;
}

// Only adapt the exported configuration to the existing host source registry.
// Conflicting imports in multiple elements cannot silently choose a scope.
export function createWebsiteConsentAdapter(win) {
  let generation=0, current, stop;
  return {sync() {
    const request=++generation;
    const elements=[...win.document.querySelectorAll(TAG_NAME)].filter(element=>element.mode==='Site' && element.getAttribute('consent-enabled')==='on');
    if (!elements.length) {stop?.();stop=null;current=undefined;return;}
    const configs=elements.map(elementConsent);
    const input=configs.every(Boolean) && new Set(configs.map(c=>JSON.stringify(c))).size===1 ? configs[0] : null;
    const key=JSON.stringify(input);
    if (current===key) return;
    ensureHelper(win.document).then(api=>{
      if (request!==generation || !api?.connectMeasurementSource) return;
      stop?.();
      stop=api.connectMeasurementSource(createManagedConsentSource(win,input,SERVICE_ORIGIN));
      current=key;
    });
  }};
}
