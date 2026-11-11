import {build} from 'esbuild';
// Real pinned npm library, isolated in each window (no mocked public CMP API).
// API/config shapes: https://cookieconsent.orestbida.com/reference/api-reference.html
// https://cookieconsent.orestbida.com/reference/configuration-reference.html
const bundle = await build({stdin:{contents:"import * as CookieConsent from 'vanilla-cookieconsent'; window.CookieConsent = CookieConsent;",
 resolveDir:new URL('../../',import.meta.url).pathname},bundle:true,write:false,format:'iife',platform:'browser'});
export const consentRevision = 'a'.repeat(32);
export const cookieconsentConfig = {provider:'cookieconsent',organization:1,unit:2,consentRevision,revision:42};
export async function cookieconsentFixture(win, {choice=null, config={}}={}) {
 win.eval(bundle.outputFiles[0].text);
 const cmp=win.CookieConsent;
 await cmp.run({mode:'opt-in',revision:42,autoShow:false,hideFromBots:false,
  categories:{necessary:{enabled:true,readOnly:true},analytics:{},marketing:{}},
  language:{default:'cs',translations:{cs:{consentModal:{title:'Soukromí',description:'Volba měření',acceptAllBtn:'Přijmout vše',acceptNecessaryBtn:'Odmítnout'},
   preferencesModal:{title:'Nastavení soukromí',acceptAllBtn:'Přijmout vše',acceptNecessaryBtn:'Odmítnout',savePreferencesBtn:'Uložit',sections:[]}}}},...config});
 const choose=value=>{
  if(value===null){cmp.reset(true);return;}
  const names=Object.keys(cmp.getConfig('categories')).filter(name=>!cmp.getConfig('categories')[name].readOnly);
  cmp.acceptCategory(names.filter(name=>value[name]===true));
 };
 if(choice!==null) choose(choice);
 // Only storage fault/other-tab tests edit records; ordinary choices use the library.
 const store=record=>{
  const cookie=cmp.getConfig('cookie');
  if(cookie.useLocalStorage) win.localStorage.setItem(cookie.name,JSON.stringify(record));
  else win.document.cookie=cookie.name+'='+encodeURIComponent(JSON.stringify(record))+';path='+cookie.path;
 };
 return {cmp,choose,store,event:name=>win.dispatchEvent(new win.CustomEvent(name))};
}
