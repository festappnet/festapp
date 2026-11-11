import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
import {publicHelpRoot} from '../../web_client/src/services/help_action_routes.js';
import {publicThemeHead} from './organizers/site_shell.mjs';

// A self-contained review copy, with real localized artwork and no server.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const locale = process.argv.includes('--en') ? 'en' : 'cs';
const helpRoot = publicHelpRoot(locale);
const origin = locale === 'en' ? 'https://tickets.festapp.net' : 'https://vstupenky.online';
const base = path.join(root, `.private/help-preview/${locale}`);
const target = path.join(base,helpRoot.slice(1,-1));
fs.mkdirSync(base,{recursive:true});
const config = path.join(base,'preview.conf');
fs.writeFileSync(config,`WEB_LINK=${origin}\nWEB_ORGANIZER_LANDING_ENABLED=true\nWEB_SUPPORTED_LANGUAGES=${locale}\nWEB_ORGANIZER_CONTENT_PROFILE=${locale==='en'?'festapp-en':'vstupenky-cs'}\nAPP_NAME=${locale==='en'?'Festapp Tickets':'vstupenky.online'}\n`);
const run = spawnSync(process.execPath,[path.join(root,'automation/release/render_help_pages.mjs'),'--config',config,'--locale',locale,'--preview','--output',target],{encoding:'utf8'});
if(run.status!==0)throw new Error(run.stderr);
const data=(file,mime)=>`data:${mime};base64,${fs.readFileSync(file).toString('base64')}`;
for(const page of fs.readdirSync(target,{recursive:true}).filter(file=>file.endsWith('index.html'))){
 const file=path.join(target,page);
 let html=fs.readFileSync(file,'utf8').replace(publicThemeHead,"<script>document.documentElement.style.colorScheme='light'</script>");
 html=html.replace(/<link rel="stylesheet" href="\/(?:napoveda|help)\/assets\/([^"]+)">/g,(_,name)=>{
  const css=fs.readFileSync(path.join(target,'assets',name),'utf8').replace(/url\("([^"/]+\.ttf)"\)/g,(_,font)=>`url("${data(path.join(target,'assets',font),'font/ttf')}")`);
  return `<style>${css}</style>`;
 }).replace(/<script src="\/(?:napoveda|help)\/assets\/([^"]+)" defer><\/script>/g,(_,name)=>`<script>document.addEventListener('DOMContentLoaded',()=>{${fs.readFileSync(path.join(target,'assets',name),'utf8').replace(/<\/script/g,'<\\/script')}},{once:true});</script>`)
 .replace(/src="\/(?:napoveda|help)\/assets\/([^"]+\.(png|jpg|webp|svg))"/g,(_,name,ext)=>{
  if(name==='brand-logo.svg')name='brand-logo-light.svg';
  return `src="${data(path.join(target,'assets',name),'image/'+(ext==='jpg'?'jpeg':ext==='svg'?'svg+xml':ext))}"`;
 }).replace(/href="(\/[^\"]*)"/g,(_,href)=>{
  if(!href.startsWith(helpRoot))return `href="${origin}${href}"`;
  const[relative,hash]=href.slice(helpRoot.length).split('#');
  const local=path.join(target,relative,!relative||relative.endsWith('/')?'index.html':'');
  return `href="${pathToFileURL(local).href}${hash?'#'+hash:''}"`;
 });
 fs.writeFileSync(file,html);
}
console.log(pathToFileURL(path.join(target,'index.html')).href);
