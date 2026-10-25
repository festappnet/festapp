import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {inlineHashes, generateManifest, verifyManifest} from '../generate_csp_policy.mjs';

test('hashes exact parser-decoded script text, not tags, attributes or external scripts', () => {
  const body = '\nwindow.bootstrap = "<&";\n';
  const digest = "'sha256-" + createHash('sha256').update(body).digest('base64') + "'";
  assert.deepEqual(inlineHashes(`<SCRIPT nonce="ignored">${body}</SCRIPT><script src="/x.js"></script>`), [digest]);
  assert.notDeepEqual(inlineHashes(`<script>${body} </script>`), [digest]);
});
test('manifest binds each actual document and detects changed, missing and added scripts', async t => {
  const dir = await mkdtemp(path.join(tmpdir(), 'festapp-csp-'));
  t.after(() => rm(dir, {recursive: true, force: true}));
  for (const file of ['webclient', 'flutter', 'auth_bridge', 'organizers-page']) await writeFile(path.join(dir, file), `<html><script>window.profile=${JSON.stringify(file)};</script></html>`);
  const manifest = await generateManifest(dir);
  await writeFile(path.join(dir, 'csp-manifest.json'), JSON.stringify(manifest));
  await verifyManifest(dir);
  for (const [profile, config] of Object.entries(manifest.profiles)) {
    assert.doesNotMatch(config.policy, /'unsafe-inline'|'unsafe-eval'|\*|script-src[^;]* https:;/);
    assert.match(config.policy, /script-src-attr 'none'/);
    if (profile !== 'flutter') assert.doesNotMatch(config.policy, /wasm-unsafe-eval|onesignal/);
  }
  const file = path.join(dir, 'webclient');
  const original = await readFile(file, 'utf8');
  for (const html of [original.replace('window.profile', 'window.changed'), '<html></html>', original + '<script>extra()</script>']) {
    await writeFile(file, html);
    await assert.rejects(verifyManifest(dir), /CSP manifest/);
  }
});

test('source header copies use the same canonical owner and retain hosting rules', async () => {
 const {BASE_POLICY} = await import('../lib/csp_policy.mjs');
 const template = await readFile(new URL('../lib/web_headers.template',import.meta.url),'utf8');
 assert.match(template, /\/embed\.js\n  Cache-Control: public, max-age=300, must-revalidate/);
 const expected = template.replace('/*\n',`/*\n  Content-Security-Policy: ${BASE_POLICY}\n`);
 for (const route of ['/stripe/connect/callback','/app/stripe/connect/callback','/stripe/pay','/stripe/return','/app/stripe/pay','/app/stripe/return']) assert.ok(expected.includes(`${route}\n  Cache-Control: no-store\n  Referrer-Policy: no-referrer`), `${route} must survive configuration generation`);
 for (const file of ['../../web/_headers','../../web_client/public/_headers']) assert.equal(await readFile(new URL(file,import.meta.url),'utf8'),expected);
});

test('tenants without the optional organizer document retain CSP for every shipped shell', async t => {
  const dir = await mkdtemp(path.join(tmpdir(), 'festapp-csp-no-organizers-'));
  t.after(() => rm(dir, {recursive:true, force:true}));
  for (const file of ['webclient','flutter','auth_bridge']) await writeFile(path.join(dir,file), '<html><script>boot()</script></html>');
  const manifest=await generateManifest(dir);
  assert.deepEqual(Object.keys(manifest.documents).sort(), ['auth_bridge','flutter','webclient']);
  assert.equal(manifest.profiles.organizers, undefined);
  await writeFile(path.join(dir,'csp-manifest.json'),JSON.stringify(manifest));
  await verifyManifest(dir);
  await rm(path.join(dir,'auth_bridge'));
  await assert.rejects(generateManifest(dir), {code:'ENOENT'});
});


test('analytics is allowed in the public response profiles and absent from private document policies', async t => {
 const dir=await mkdtemp(path.join(tmpdir(),'festapp-csp-analytics-'));
 t.after(()=>rm(dir,{recursive:true,force:true}));
 for (const file of ['webclient','flutter','auth_bridge']) await writeFile(path.join(dir,file),'<html><body>app</body></html>');
 await writeFile(path.join(dir,'organizers-page'),`<html><body><script type="module" src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon='{}'></script></body></html>`);
 const manifest=await generateManifest(dir);
 assert.match(manifest.profiles.organizers.policy,/https:\/\/static\.cloudflareinsights\.com/);
 assert.match(manifest.profiles.webclient.policy,/https:\/\/static\.cloudflareinsights\.com/);
 for(const profile of ['flutter','auth_bridge','none']) assert.doesNotMatch(manifest.profiles[profile].policy,/cloudflareinsights/);
 await writeFile(path.join(dir,'csp-manifest.json'),JSON.stringify(manifest));
 await verifyManifest(dir);
});
