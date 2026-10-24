import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';

// A durable preview that needs neither a server nor a running application.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const locale = process.argv.includes('--en') ? 'en' : 'cs';
const target = path.join(root, `.private/help-preview/${locale}/napoveda`);
const run = spawnSync(process.execPath, [path.join(root,'automation/release/render_help_pages.mjs'), '--locale',locale,'--preview','--output',target], {encoding:'utf8'});
if (run.status !== 0) throw new Error(run.stderr);
const data = (file, mime) => `data:${mime};base64,${fs.readFileSync(file).toString('base64')}`;
for (const page of fs.readdirSync(target, {recursive:true}).filter(file => file.endsWith('index.html'))) {
  const file = path.join(target,page);
  let html = fs.readFileSync(file,'utf8');
  html = html.replace(/<link rel="stylesheet" href="\/napoveda\/assets\/([^"]+)">/g, (_,name) => {
    const css = fs.readFileSync(path.join(target,'assets',name),'utf8').replace(/url\("([^"/]+\.ttf)"\)/g, (_,font) => `url("${data(path.join(target,'assets',font),'font/ttf')}")`);
    return `<style>${css}</style>`;
  }).replace(/<script src="\/napoveda\/assets\/([^"]+)" defer><\/script>/g, (_,name) => `<script>${fs.readFileSync(path.join(target,'assets',name),'utf8').replace(/<\/script/g,'<\\/script')}</script>`)
    .replace(/src="\/napoveda\/assets\/([^"]+\.(png|jpg|webp))"/g, (_,name,extension) => `src="${data(path.join(target,'assets',name),'image/'+(extension === 'jpg' ? 'jpeg' : extension))}"`)
    .replace(/href="(\/[^\"]*)"/g, (_,href) => {
      if (!href.startsWith('/napoveda/')) return `href="https://vstupenky.online${href}"`;
      const [relative,hash] = href.slice('/napoveda/'.length).split('#');
      const local = path.join(target,relative, !relative || relative.endsWith('/') ? 'index.html' : '');
      return `href="${pathToFileURL(local).href}${hash ? '#'+hash : ''}"`;
    });
  fs.writeFileSync(file,html);
}
console.log(pathToFileURL(path.join(target,'index.html')).href);
