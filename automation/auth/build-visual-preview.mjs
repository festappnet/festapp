import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {build} from '../../web_client/node_modules/esbuild/lib/main.js';
const root=new URL('../../',import.meta.url);
const out=new URL('docs/plans/google-sign-in-reference-2026-10-01/implementation/',root);mkdirSync(out,{recursive:true});
const source=`import {LoginModal} from './web_client/src/components/users/login_modal.js';
import {GoogleAuthService} from './web_client/src/services/google_auth_service.js';
import {LocalizationService} from './web_client/src/services/localization_service.js';
import {RightsService} from './web_client/src/services/rights_service.js';
const translations=${JSON.stringify(Object.fromEntries(['cs','en'].map(l=>[l,JSON.parse(readFileSync(new URL('assets/translations/'+l+'.json',root)))])))};
GoogleAuthService.capability=async()=>true;
RightsService.context={organization:{IS_REGISTRATION_ENABLED:true}};
window.preview=(view='login',locale='cs',dark=false)=>{
 document.querySelectorAll('login-modal,app-modal').forEach(e=>e.remove());
 LocalizationService.translations=translations[locale];LocalizationService.currentLocale=locale;document.documentElement.lang=locale;
 document.body.classList.toggle('dark-mode',dark);
 const modal=document.createElement('login-modal');document.body.appendChild(modal);
 modal.googleEnabled=true;
 if(['proof','profile','mailbox','mfa','unlink'].includes(view))modal.showGoogleResult({status:['proof','unlink'].includes(view)?'needs_account_proof':view==='mfa'?'needs_mfa':'needs_profile',email:'jana@example.com',name:'Jana Nováková',mailboxRequired:view==='mailbox',intent:view==='unlink'?'unlink':'login'});
 else {modal.currentView=view==='register'?'register':view==='loading'?'google_completing':'login';modal.googleError=view==='error'?'attempt_expired':view==='cancelled'?'provider_cancelled':'';modal._updateContent();}
};
const q=new URLSearchParams(location.search);window.preview(q.get('view')||'login',q.get('locale')||'cs',q.get('dark')==='true');`;
const bundle=await build({stdin:{contents:source,resolveDir:root.pathname,loader:'js'},bundle:true,format:'iife',write:false,minify:true,loader:{'.css':'empty'},logLevel:'error',plugins:[{name:'fixture-router',setup(b){
 b.onResolve({filter:/router_service\.js$/},()=>({path:'router',namespace:'fixture'}));
 b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export class RouterService {static navigate(){} static getCurrentPath(){return "/";}}'}));
}}]});
let css=readFileSync(new URL('web_client/src/theme_config.css',root),'utf8');css=css.replace(/url\('\.\/assets\/fonts\/([^']+)'\)/g,(_,f)=>`url('data:font/${f.endsWith('ttf')?'ttf':'otf'};base64,${readFileSync(new URL('web_client/src/assets/fonts/'+f,root)).toString('base64')}')`);
// Same auth theme aliases provided by production main stylesheet.
css+='\n:root{--font-family:Futura,sans-serif;--bg-color:var(--surface-color);--text-secondary:#666;--border-color:#ddd;--btn-text-color:white}body.dark-mode{--text-secondary:#c0c0c0;--border-color:#555;--text-color-dark:#eee;--bg-input-dark:#2b2d31;--btn-text-color:#152238}*{box-sizing:border-box}';
writeFileSync(new URL('web-preview.html',out),`<!doctype html><html lang="cs"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FestApp Google auth - actual component preview</title><style>${css}</style><body><script>${bundle.outputFiles[0].text.replaceAll('</script','<\\/script')}</script></body></html>`);
console.log('Actual-component static preview generated');
