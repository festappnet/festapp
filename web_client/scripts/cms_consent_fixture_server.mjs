// Foreground, loopback-only CMS test transport. No production backend or CMP.
import {readFileSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import https from 'node:https';
import {createServer} from 'vite';
import {JSDOM} from 'jsdom';
import pg from 'pg';
const fixture=path.resolve(process.argv[2]), base=Number(process.argv[3]);
if (!Number.isInteger(base) || base<1024 || base>65480 || !/festapp-cms-consent-[a-z0-9-]+$/.test(fixture)) throw Error('Owned fixture root and port block required');
const source=path.resolve(import.meta.dirname,'../..');
const marker=path.basename(fixture);
const status=JSON.parse(readFileSync(path.join(fixture,'integrations/wordpress/.private/backend-status.json'),'utf8'));
if(status.API_URL!==`http://127.0.0.1:${base+21}`)throw Error('Foreign backend status refused');
const db=new pg.Client({connectionString:`postgresql://postgres:postgres@127.0.0.1:${base+22}/postgres`});await db.connect();
try {if((await db.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton')).rows[0]?.project!==marker)throw Error('Foreign database refused');}finally{await db.end();}
const origin=n=>`https://127.0.0.1:${base+n}`;
const service=origin(32), api=origin(33);
const state=()=>JSON.parse(readFileSync(path.join(fixture,'fixture-state.json'),'utf8'));
const cmp=`<script>/* Modeled CMP public API boundary, never a live provider */
window.testChoice=true;let consentCreatedAt=new Date();window.__festappTestSetConsent=value=>{window.testChoice=value;consentCreatedAt=new Date();document.dispatchEvent(new Event('consentPolicyChanged'));dispatchEvent(new Event('cc:onChange'));};
const cats=['statistika návštěv','reklama'];window.CookieConsent={validConsent:()=>window.testChoice!==null,getConfig:k=>({mode:'opt-in',revision:7,categories:Object.fromEntries(cats.map(x=>[x,{}]))}[k]),getCookie:()=>({revision:7,categories:window.testChoice?cats:[],consentId:'fixture-record',consentTimestamp:consentCreatedAt.toISOString(),lastConsentTimestamp:consentCreatedAt.toISOString(),expirationTime:consentCreatedAt.getTime()+3600000,services:Object.fromEntries(cats.map(x=>[x,[]]))}),acceptedCategory:()=>window.testChoice};
window.consentPolicyManager={getCurrentConsentPolicy:()=>({defaultPolicy:window.testChoice===null,createdDate:consentCreatedAt,policy:{essential:true,functional:false,analytics:window.testChoice,advertising:window.testChoice,dataToThirdParty:window.testChoice}})};</script>`;
function generatedHtml(config) {
 const dom=new JSDOM(readFileSync(path.join(source,'automation/release/help/en/embed-generator.html'),'utf8').replaceAll('{{FORM_ORIGIN}}',service),{url:config.websiteOrigin,runScripts:'outside-only'});
 try {
  dom.window.document.documentElement.lang='en';dom.window.eval(readFileSync(path.join(source,'automation/release/help/help.js'),'utf8'));
  const form=dom.window.document.querySelector('form');form.querySelector('[name=form-url]').value=service+'/form/embedded-synthetic';
  form.querySelector('[name=host-datalayer]').checked=false;form.querySelector('[name=consent-enabled]').checked=true;form.querySelector('[name=consent-export]').value=JSON.stringify(config);
  form.dispatchEvent(new dom.window.Event('submit',{cancelable:true}));
  if(form.querySelector('[data-embed-output]').hidden)throw Error('Actual HTML generator rejected export');
  return '<!doctype html><html><head><meta charset="utf-8">'+cmp+'</head><body>'+form.querySelector('[data-embed-output] textarea').value+'</body></html>';
 }finally{dom.window.close();}
}
const vite=await createServer({root:path.join(source,'web_client'),configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:base+1,strictPort:true,hmr:false,fs:{allow:[source],deny:['**/.private/**','**/.env*','**/.git/**']}},plugins:[{
 name:'owned-cms-backend',configureServer(server){server.middlewares.use((req,res,next)=>{
  const match=/^\/assets\/translations\/(cs|en|sk|de|pl|uk)\.json$/.exec(req.url);
  if(match){res.setHeader('content-type','application/json');res.end(readFileSync(path.join(source,'assets/translations',match[1]+'.json')));return;}
  if(req.url==='/__cms-wix-entry.js'){
   res.setHeader('content-type','text/javascript');res.end(`import {registerTicketElement} from '/@fs/${path.join(source,'integrations/wix/src/element.js')}';registerTicketElement(window,async()=>'Site');`);return;
  }
  next();
 });},transform(text,id){
  if(id.endsWith('/src/app_config.js')){
   for(const expression of [/static backendActivationTenantId = [^;]+;/,/static supabaseUrl = [^;]+;/,/static anonKey = [^;]+;/])if(!expression.test(text))throw Error('Unknown app config shape');
   return text.replace(/static backendActivationTenantId = [^;]+;/,"static backendActivationTenantId = '';").replace(/static supabaseUrl = [^;]+;/,`static supabaseUrl = ${JSON.stringify(api)};`).replace(/static anonKey = [^;]+;/,`static anonKey = ${JSON.stringify(status.ANON_KEY)};`);
  }
  if(id.endsWith('/integrations/wix/src/config.js'))return text.replace("export const SERVICE_ORIGIN = 'https://vstupenky.online';",`export const SERVICE_ORIGIN = ${JSON.stringify(service)};`);
 }
}]});await vite.listen();
const tls={key:readFileSync(path.join(fixture,'tls/key.pem')),cert:readFileSync(path.join(fixture,'tls/cert.pem'))};
const servers=[];const sockets=new Set();
function listen(offset,handler){const server=https.createServer(tls,handler);server.on('connection',s=>{sockets.add(s);s.once('close',()=>sockets.delete(s));});servers.push(server);return new Promise((resolve,reject)=>{server.once('error',reject);server.listen(base+offset,'127.0.0.1',resolve);});}
for(const [offset,target,joomla] of [[31,11,false],[36,12,false],[34,15,true],[35,16,true],[32,1,false],[33,21,false]]) {
 await listen(offset,(req,res)=>{
  const upstream=http.request({host:'127.0.0.1',port:base+target,path:req.url,method:req.method,headers:{...req.headers,host:req.headers.host,'accept-encoding':'identity','x-forwarded-proto':'https'}},r=>{
   const headers={...r.headers};
   if(joomla && !state().coop)delete headers['cross-origin-opener-policy'];
   if(target!==1 && target!==21 && String(headers['content-type']).includes('text/html')){
    const chunks=[];r.on('data',c=>chunks.push(c));r.on('end',()=>{const body=Buffer.concat(chunks).toString().replace(/<head[^>]*>/i,match=>match+cmp);delete headers['content-length'];res.writeHead(r.statusCode,headers);res.end(body);});
   }else{res.writeHead(r.statusCode,headers);r.pipe(res);}
  });upstream.on('error',()=>{if(!res.headersSent)res.writeHead(502);res.end();});req.pipe(upstream);
 });
}
await listen(37,(req,res)=>{
 const config=state().exports[origin(37)];res.setHeader('content-type','text/html');
 const escape=v=>v.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 res.end(`<!doctype html><html><head>${cmp}</head><body><vstupenky-online-form form-url="${service}/form/embedded-synthetic" measurement="unit" consent-enabled="on" consent-export="${escape(JSON.stringify(config))}"></vstupenky-online-form><script type="module" src="${service}/__cms-wix-entry.js"></script></body></html>`);
});
await listen(38,(_req,res)=>{res.setHeader('content-type','text/html');res.end(generatedHtml(state().exports[origin(38)]));});
writeFileSync(path.join(fixture,'transport-ready'),'ready');
let closing=false;
async function close(){if(closing)return;closing=true;for(const s of sockets)s.destroy();await Promise.all(servers.map(s=>new Promise(r=>s.close(r))));await vite.close();process.exit();}
process.on('SIGTERM',close);process.on('SIGINT',close);
console.log('Owned HTTPS CMS/service/API transports ready; CMP and Wix Site mode are modeled');
