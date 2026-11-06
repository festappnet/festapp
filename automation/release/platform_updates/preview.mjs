import {publicBrandFiles} from '../organizers/public_runtime.mjs';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {readConfig,resolveContext} from '../organizers/context.mjs';
import {renderUpdate} from './render.mjs';
const arg=(name,fallback)=>{const i=process.argv.indexOf(name);return i<0?fallback:process.argv[i+1];};
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const output=path.resolve(arg('--output','/tmp/festapp-platform-updates-preview'));
const context=resolveContext(readConfig(arg('--config',path.join(root,'automation/project.conf'))),{updatesOptions:{...(arg('--content')?{contentDir:path.resolve(arg('--content'))}:{})}});
if (!context.updates) throw new Error('This tenant has no platform updates capability');
const css=fs.readFileSync(path.join(root,'automation/release/organizers/page.css'),'utf8');
const filename=page=>`${page.locale}-${page.updateId??'index'}.html`;
fs.mkdirSync(output,{recursive:true});
for (const asset of context.updates.assets) {
  const local=path.join(output,asset.slice(1));
  fs.mkdirSync(path.dirname(local),{recursive:true});
  fs.copyFileSync(path.join(root,'web',asset),local);
}
const outputs=context.updates.pages.map(page=>{
  let html=renderUpdate(page,context,{css});
  for (const other of context.updates.pages) {
    const destination=pathToFileURL(path.join(output,filename(other))).href;
    html=html.replaceAll(`href="${other.canonical}"`,`href="${destination}"`).replaceAll(`href="${other.path}"`,`href="${destination}"`);
  }
  for(const name of publicBrandFiles)html=html.replaceAll(`src="/${name}"`,`src="data:image/svg+xml;base64,${fs.readFileSync(path.join(root,'web_client/public',name)).toString('base64')}"`);
  for (const asset of context.updates.assets) {
    const extension=path.extname(asset).slice(1).replace('jpg','jpeg');
    html=html.replaceAll(`src="${asset}"`,`src="data:image/${extension};base64,${fs.readFileSync(path.join(root,'web',asset)).toString('base64')}"`);
    html=html.replaceAll(`href="${asset}"`,`href="${pathToFileURL(path.join(output,asset.slice(1))).href}"`);
  }
  html=html.replace(/href="(\/[^\"]*)"/g,(_,href)=>`href="${new URL(href,context.origin).href}"`);
  return {name:filename(page),html};
});
for (const {name,html} of outputs) fs.writeFileSync(path.join(output,name),html);
console.log(path.join(output,'cs-index.html'));
