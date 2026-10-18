import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..');
const read=p=>fs.readFileSync(path.join(root,p),'utf8');
test('forward security migrations agree with canonical SQL',()=>{
 assert.match(execFileSync('python3',['automation/assemble-server-security-migrations.py','--check'],{cwd:root,encoding:'utf8'}),/canonical/);
 assert.match(read('database/functions/inventory/update_spots_assignments.sql'),/REVOKE ALL ON FUNCTION public\.update_spot_assignments\(jsonb\) FROM PUBLIC, anon/);
 assert.doesNotMatch(read('database/functions/security/server_security_retirement.sql'),/CASCADE\s*;/i);
});
test('security activation has digest, target, lock, validation and live readback gates',()=>{
 const s=read('automation/hetzner-supabase/runtime/apply-security-config.sh');
 for(const text of ['flock -n','sha256sum','caddy validate','caddy reload','127.0.0.1:2019/config/','BEGIN READ ONLY','festapp_rehearsal_20260909220601']) assert(s.includes(text),text);
 assert.doesNotMatch(s,/docker compose (up|down|restart)|promote-production-runtime/);
 for(const file of ['apply-security-config.sh','collect-resource-budget.sh']) execFileSync('bash',['-n',path.join(root,'automation/hetzner-supabase/runtime',file)]);
});
test('online restore refuses mutable images, production mounts, network and preexisting evidence',()=>{
 const s=read('automation/hetzner-supabase/restore/drill-online-backup-local.py');
 for(const text of ["'--network','none'","'HostConfig']['Binds']","not a.evidence.exists()","'@sha256:'","'rpo_seconds':None"]) assert(s.includes(text),text);
 assert.match(s, /'runtime_executed':bool\(a\.gateway_smoke\)/);
 assert.match(s, /add_argument\('\-\-gateway-smoke',action='store_true'\)/);
 const isolated=read('database/tests/security/run-local.sh');
 assert.match(isolated,/major_version = 17/);
 assert.match(read('automation/bootstrap_local_db.sh'),/postgresql:\/\/supabase_admin:postgres@127\.0\.0\.1/);
});

test('every definer in the security package declares its path and direct ACL',()=>{
 const manifest=JSON.parse(read('database/functions/security/server_security_acl_manifest.json'));
 const directory=path.join(root,'database/functions/security');
 const files=[...manifest.reviewed_definer_sources,...fs.readdirSync(directory).filter(f=>f.endsWith('.sql')).map(f=>'database/functions/security/'+f)];
 for(const file of files){
  const source=read(file);
  for(const match of source.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?(\w+)\s*\([\s\S]*?\bAS\s+\$[\w]*\$/gi)){
   if(!/SECURITY\s+DEFINER/i.test(match[0]))continue;
   assert.match(match[0],/SET\s+search_path/i,file);
   assert.match(source,new RegExp('REVOKE[\\s\\S]*?ON FUNCTION (?:public\\.)?'+match[1]+'\\(','i'),file);
   assert(Object.keys(manifest.entrypoints).some(key=>key.startsWith('public.'+match[1]+'(')),file+' must declare its ACL in the manifest');
  }
 }
});

test('root runtime observer sanitizes Docker data and rejects a different host',()=>{
 execFileSync('python3',[path.join(root,'automation/tests/test_security_runtime_evidence.py')],{stdio:'pipe'});
});

test('new application definer headers require an explicit signature and ACL declaration',async()=>{
 const {createHash}=await import('node:crypto');
 const contracts=JSON.parse(read('database/functions/security/definer_contracts.json'));
 const manifest=JSON.parse(read('database/functions/security/server_security_acl_manifest.json'));
 const legacy=new Set(contracts.grandfathered_headers);
 const digest=text=>createHash('sha256').update(text.replace(/\s+/g,' ').trim().toLowerCase()).digest('hex');
 function validate(source,file){
  for(const m of source.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:"?public"?\.)?"?(\w+)"?\s*\([\s\S]*?\bAS\s+\$[\w]*\$/gi)){
   if(!/SECURITY\s+DEFINER/i.test(m[0]))continue;
   const key=digest(m[0]);
   if(legacy.has(key))continue;
   const declared=contracts.declared[key];
   assert(declared,file+': undeclared definer '+m[1]);
   assert.equal(declared.source,file);
   assert(manifest.entrypoints[declared.signature],file+': missing role ACL');
   assert.match(m[0],/SET\s+search_path/i,file);
   assert.match(source,new RegExp('REVOKE[\\s\\S]*?ON FUNCTION (?:public\\.)?'+m[1]+'\\(','i'),file);
  }
 }
 function walk(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){
  const file=path.join(dir,entry.name);
  if(entry.isDirectory())walk(file);
  else if(file.endsWith('.sql'))validate(fs.readFileSync(file,'utf8'),path.relative(root,file));
 }}
 walk(path.join(root,'database/functions'));
 assert.throws(()=>validate('CREATE FUNCTION public.undeclared_security_fixture(bigint) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$','new.sql'),/undeclared definer/);
});
