import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {resolve} from 'node:path';

// This archive deploys the public extension assets. Wix registers apps in its
// dashboard; uploading this archive never registers or publishes a Wix app.
const manifest=JSON.parse(await readFile('dist/manifest.json','utf8'));
for (const [file,hash] of Object.entries(manifest.files)) {
  if (!/^[\w.-]+$/.test(file)) throw new Error('Unexpected asset filename');
  const actual=createHash('sha256').update(await readFile(`dist/${file}`)).digest('hex');
  if (actual!==hash) throw new Error(`Built asset changed: ${file}. Run the build again.`);
}
if (!/^\d+\.\d+\.\d+$/.test(manifest.version)) throw new Error('Invalid version');
await mkdir('artifacts',{recursive:true});
const name=`vstupenky-online-wix-${manifest.version}.zip`;
const target=resolve('artifacts',name);
await rm(target,{force:true});
execFileSync('zip',['-q','-X',target,'manifest.json',...Object.keys(manifest.files).sort()],{cwd:'dist'});
const hash=createHash('sha256').update(await readFile(target)).digest('hex');
await writeFile(`${target}.sha256`,`${hash}  ${name}\n`);
console.log(`Packaged ${name}; public assets only. SHA-256 ${hash}`);
