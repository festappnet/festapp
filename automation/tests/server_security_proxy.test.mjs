import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..');
test('actual pinned Caddy accepts supported Storage and enforces streaming caps',{timeout:180000},()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-security-caddy-'));
 const clientName='festapp-security-proxy-client-'+process.pid;
 const name='festapp-security-caddy-'+process.pid;
 const image=JSON.parse(fs.readFileSync(path.join(root,'automation/hetzner-supabase/runtime/pins.json'))).supabase.images.caddy;
 const docker=(...args)=>execFileSync('docker',args,{encoding:'utf8',stdio:['pipe','pipe','pipe'],timeout:150000});
 try{
  let config=fs.readFileSync(path.join(root,'automation/hetzner-supabase/runtime/Caddyfile'),'utf8');
  // Only site/env changes; production matchers, headers, body handlers and upstream stay exact.
  config=config.replace('{$FESTAPP_SUPABASE_SITE_ADDRESSES}','http://:8080').replace('{$FESTAPP_SUPABASE_ADMIN_BASIC_AUTH}','fixture');
  fs.writeFileSync(path.join(directory,'Caddyfile'),config);
  docker('create','--name',name,'--network','none',image);
  docker('cp',path.join(directory,'Caddyfile'),`${name}:/etc/caddy/Caddyfile`);
  docker('start',name);
  docker('create','--name',clientName,'--network',`container:${name}`,'node:22-alpine','node','/test.mjs');
  docker('cp',path.join(root,'database/tests/security/proxy_body_contract.mjs'),`${clientName}:/test.mjs`);
  const output=docker('start','-a',clientName);
  assert.match(output,/websocket passed/);
 }finally{try{docker('rm','-f','-v',clientName,name);}finally{fs.rmSync(directory,{recursive:true,force:true});}}
});
