// Local-only Vite transport configuration for the owned Blueprint integration
// backend. It never modifies the production AppConfig or a tenant branch.
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {dirname,resolve} from 'node:path';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const backend=resolve(root,'../festapp-blueprint-b-e2e-20261019');
const definitions=JSON.parse(await readFile(resolve(backend,'private-defines.json'),'utf8'));
if(definitions.FESTAPP_SUPABASE_URL!=='http://127.0.0.1:59521')throw Error('Owned loopback backend required');
const config=`import fs from 'node:fs';
const definitions=JSON.parse(fs.readFileSync(new URL('./private-defines.json',import.meta.url)));
if(definitions.FESTAPP_SUPABASE_URL!=='http://127.0.0.1:59521')throw Error('Owned loopback backend required');
export default {root:${JSON.stringify(resolve(root,'web_client'))},server:{host:'127.0.0.1',port:59601,strictPort:true},plugins:[{
name:'blueprint-disposable-backend',transform(source,id){
if(!id.endsWith('/src/app_config.js'))return;
return source.replace(/static supabaseUrl = [^;]+;/,'static supabaseUrl = '+JSON.stringify(definitions.FESTAPP_SUPABASE_URL)+';').replace(/static anonKey = [^;]+;/,'static anonKey = '+JSON.stringify(definitions.FESTAPP_SUPABASE_ANON_KEY)+';');
},transformIndexHtml(){return [{tag:'script',injectTo:'head-prepend',children:
\`(()=>{const original=globalThis.fetch.bind(globalThis);globalThis.fetch=(input,init)=>{
 const uri=new URL(typeof input==='string'||input instanceof URL?input:input.url,location.href);
 const control=uri.hostname==='image-api.festapp.net';
 const image=['img.festapp.net','a.img.festapp.net'].includes(uri.hostname);
 if(!control&&!image)return original(input,init);
 if(uri.protocol!=='https:')throw Error('Invalid local image transport');
 const mapped='http://127.0.0.1:59525'+(image?'/public':'')+uri.pathname+uri.search;
 return original(input instanceof Request?new Request(mapped,input):mapped,init);
};})();\`}];}
}]};
`;
const path=resolve(backend,'vite-blueprint.config.mjs');
await writeFile(path,config,{mode:0o600});
console.log(path);
