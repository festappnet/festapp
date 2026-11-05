import fs from 'node:fs';
import path from 'node:path';

export const publicBrandFiles=Object.freeze(['brand-logo.svg','brand-logo-light.svg','brand-symbol.svg','brand-wordmark.svg','brand-wordmark-stacked.svg']);
const escape=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

// Public documents do not report an installed app version. Their complete
// runtime and canonical artwork belong under a network-owned page namespace.
export function publicRuntime(root,{builtIndex,entry,assetRoot}){
 if(!assetRoot.startsWith('/')||!assetRoot.endsWith('/'))throw new Error('Public asset root must be an absolute directory');
 const assets=Object.fromEntries(publicBrandFiles.map(name=>[name,fs.readFileSync(path.join(root,'web_client/public',name))]));
 if(!builtIndex)return{assets,assetRoot,entryUrl:null,themeLinks:''};
 const dist=path.dirname(path.resolve(builtIndex));
 const manifest=JSON.parse(fs.readFileSync(path.join(dist,'.vite/manifest.json'),'utf8'));
 const runtimeEntry=manifest[entry];
 if(!runtimeEntry?.file)throw new Error(`Built public page needs the Vite ${entry} entry`);
 const relocate=text=>text.replaceAll('web-assets/',assetRoot.slice(1)+'runtime/').replaceAll('/assets/translations/',assetRoot+'translations/');
 for(const file of fs.readdirSync(path.join(dist,'web-assets'),{recursive:true})){
  const full=path.join(dist,'web-assets',file);
  if(fs.statSync(full).isFile())assets['runtime/'+file]=/\.(?:m?js|css)$/.test(file)?relocate(fs.readFileSync(full,'utf8')):fs.readFileSync(full);
 }
 for(const file of fs.readdirSync(path.join(dist,'assets/translations')))if(file.endsWith('.json'))assets['translations/'+file]=fs.readFileSync(path.join(dist,'assets/translations',file));
 const themeLinks=(fs.readFileSync(builtIndex,'utf8').match(/<link[^>]*rel="stylesheet"[^>]*>/g)||[]).filter(tag=>/href="\/web-assets\/[^"]+\.css"/.test(tag)||tag.includes('https://fonts.googleapis.com/icon?family=Material+Icons')).map(relocate).join('');
 return{assets,assetRoot,entryUrl:escape(relocate('/'+runtimeEntry.file)),themeLinks};
}
