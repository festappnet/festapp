import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,mkdtempSync,cpSync,mkdirSync,symlinkSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=fileURLToPath(new URL('../../../',import.meta.url));
test('remote runtime imports from the exact Docker COPY tree, without repository file fallbacks',()=>{
 const stage=mkdtempSync(join(tmpdir(),'festapp-remote-image-'));
 try{
  const docker=readFileSync(join(root,'tools/festapp/Dockerfile.remote'),'utf8');
  for(const line of docker.split('\n').filter(line=>line.startsWith('COPY '))){
   const parts=line.slice(5).trim().split(/\s+/),destination=parts.pop();
   for(const source of parts){
    const target=resolve(stage,destination,parts.length>1?source.split('/').at(-1):'');
    mkdirSync(dirname(target),{recursive:true});
    cpSync(join(root,source),target,{recursive:true});
   }
  }
  // Production dependencies are supplied by the frozen install RUN layer.
  symlinkSync(join(root,'tools/festapp/node_modules'),join(stage,'tools/festapp/node_modules'),'dir');
  const module=pathToFileURL(join(stage,'tools/festapp/src/remote/server.mjs')).href;
  const result=spawnSync(process.execPath,['--input-type=module','-e',`await import(${JSON.stringify(module)});`],{cwd:stage,encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
 }finally{rmSync(stage,{recursive:true,force:true});}
});
