import {build} from 'esbuild';
import {mkdir, copyFile} from 'node:fs/promises';
await mkdir('dist', {recursive: true});
await build({entryPoints:['src/widget.js','src/settings.js'], bundle:true, outdir:'dist', format:'iife', target:['es2022'], minify:true, legalComments:'linked', sourcemap:false});
for (const file of ['settings.html','settings.css']) await copyFile(`src/${file}`, `dist/${file}`);
console.log('Built self-managed Wix widget and settings panel; no upload or Wix registration.');
