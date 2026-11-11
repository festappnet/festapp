import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import crypto from 'node:crypto';
import {fingerprint,inventory} from '../lib/web_build_cache.mjs';
export function fixture(t) {
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-cache-test-'));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  const put=(name,content='one')=>{const file=path.join(root,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,content);};
  put('.gitignore','/web/generated.json\n/.env*\n/web_client/.env*\n');
  put('automation/web_build_inputs.json',fs.readFileSync(fileURLToPath(new URL('../web_build_inputs.json',import.meta.url))));
  put('automation/project.conf','DOMAIN=example.test\nORGANIZATION_ID=7\nCLOUDFLARE_PROJECT_NAME=test\nVERSION=1.0.0+1\n');
  for(const name of ['lib/main.dart','pubspec.lock','packages/local/lib/local.dart','assets/logo.png','web/index.html','web_client/src/app.js','docs/guide.md'])put(name);
  execFileSync('git',['init','-q',root]);
  execFileSync('git',['-C',root,'add','.']);
  execFileSync('git',['-C',root,'-c','user.name=Test','-c','user.email=test@example.test','commit','-qm','fixture']);
  const tools={sdk:'revision-a',pnpm:'11.24.0'};
  const components=target=>Object.fromEntries(['flutter','vite'].map(c=>{
    const files=inventory(path.join(root,'build/web'));
    return [c,{schema:1,key:fingerprint(root,c,target,tools).key,source:execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(),tools,files,outputHash:crypto.createHash('sha256').update(JSON.stringify(files)).digest('hex')}];
  }));
  return {root,put,tools,components,home:path.join(root,'.private/cache')};
}
