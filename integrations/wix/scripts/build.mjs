import {build} from 'esbuild';
import {mkdir, copyFile, readdir, readFile, writeFile, rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const registration=JSON.parse(await readFile('wix-app.json','utf8'));
if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(registration.appId)) throw new Error('Missing assigned Wix application ID');
await rm('dist', {recursive:true,force:true});
await mkdir('dist', {recursive: true});
await build({entryPoints:['src/widget.js','src/settings.js'], bundle:true, outdir:'dist', format:'iife', target:['es2022'], minify:true, legalComments:'linked', sourcemap:false});
for (const file of ['settings.html','settings.css','help.html','_headers']) await copyFile(`src/${file}`, `dist/${file}`);
const files={};
for (const file of (await readdir('dist')).sort()) {
  if (file==='manifest.json') continue;
  files[file]=createHash('sha256').update(await readFile(`dist/${file}`)).digest('hex');
}
await writeFile('dist/manifest.json', JSON.stringify({
  schemaVersion:1, version:JSON.parse(await readFile('package.json','utf8')).version,
  appId:registration.appId,
  tagName:'vstupenky-online-form', framework:'self-managed-custom-element',
  files,
},null,2)+'\n');
console.log('Built self-managed Wix widget and settings panel; no upload or Wix registration.');
