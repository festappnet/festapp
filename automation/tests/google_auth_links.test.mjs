import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
test('selected tenant verified links are generated idempotently with exact HTTPS callback and public signing fingerprints',()=>{
 const root=mkdtempSync(join(tmpdir(),'festapp-links-'));
 try{
  mkdirSync(join(root,'android/app/src/main'),{recursive:true});
  mkdirSync(join(root,'web/.well-known'),{recursive:true});
  writeFileSync(join(root,'web/.well-known/apple-app-site-association'),JSON.stringify({applinks:{details:[{appIDs:['TEAM.tenant'],components:[{'/':'/occasion/*'}]},{appID:'TEAM.legacy',paths:['/legacy/*']}]}}));
  const manifest=join(root,'android/app/src/main/AndroidManifest.xml');writeFileSync(manifest,'<manifest><application><activity>        </activity></application></manifest>');
  const generate=(origin,prints)=>spawnSync('python3',[new URL('../google-auth-links.py',import.meta.url).pathname,root,origin,'test.tenant',prints]);
  assert.equal(generate('https://tenant.invalid','AA:'.repeat(31)+'AA').status,0);
  const first=readFileSync(manifest,'utf8');assert.match(first,/android:host="tenant.invalid" android:path="\/app\/google-auth"/);assert.match(first,/flutter_deeplinking_enabled" android:value="false"/);
  assert.equal(generate('https://tenant.invalid','AA:'.repeat(31)+'AA').status,0);assert.equal(readFileSync(manifest,'utf8'),first);
  for(const path of ['/stripe/pay','/stripe/return','/app/stripe/pay','/app/stripe/return']) assert.ok(first.includes(`android:path="${path}"`));
  const aasa=JSON.parse(readFileSync(join(root,'web/.well-known/apple-app-site-association')));
  assert.deepEqual(aasa.applinks.details[0].appIDs,['TEAM.tenant']);
  assert.ok(aasa.applinks.details[0].components.some(c=>c['/']==='/occasion/*'));
  for(const path of ['/stripe/pay','/stripe/return','/app/stripe/pay','/app/stripe/return']) {
   assert.equal(aasa.applinks.details[0].components.filter(c=>c['/']===path).length,1);
   assert.equal(aasa.applinks.details[1].paths.filter(p=>p===path).length,1);
  }
  assert.ok(!first.includes('/stripe/connect'));
  const links=JSON.parse(readFileSync(join(root,'web/.well-known/assetlinks.json')));assert.equal(links[0].target.package_name,'test.tenant');assert.equal(links[0].target.sha256_cert_fingerprints.length,1);
  for(const origin of ['http://tenant.invalid','https://user@tenant.invalid','https://tenant.invalid?token=x','https://tenant.invalid#secret']) assert.notEqual(generate(origin,'').status,0);assert.notEqual(generate('https://tenant.invalid','INVALID').status,0);
  assert.equal(generate('https://tenant.invalid','').status,0);assert.deepEqual(JSON.parse(readFileSync(join(root,'web/.well-known/assetlinks.json'))),[]);
 }finally{rmSync(root,{recursive:true,force:true});}
});
