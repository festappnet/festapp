import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { sealReleaseManifest } from '../release/seal_local_release_manifest.mjs';

const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 3072 });
const publicPem = publicKey.export({ type: 'spki', format: 'pem' });
const source = JSON.stringify({ backend: { activation: { tenantId: 'festapptickets' } }, privateValue: 'existing-private-fixture' });
test('sealed input preserves exact original bytes without plaintext', () => {
  const envelope = sealReleaseManifest(source, publicPem);
  assert.ok(!JSON.stringify(envelope).includes('existing-private-fixture'));
  const key = crypto.privateDecrypt({ key: privateKey, oaepHash: 'sha256' }, Buffer.from(envelope.encryptedKey, 'base64'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
  const plaintext = Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext, 'base64')), decipher.final()]);
  assert.equal(plaintext.toString(), source);
  assert.equal(crypto.createHash('sha256').update(plaintext).digest('hex'), envelope.sourceSha256);
});
test('missing or other tenant inputs fail closed', () => {
  assert.throws(() => sealReleaseManifest('', publicPem));
  assert.throws(() => sealReleaseManifest('{"backend":{"activation":{"tenantId":"another"}}}', publicPem));
});
test('PEM and DER inputs retain RSA type and minimum size requirements', () => {
  for (const key of [
    crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).publicKey,
    crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).publicKey,
  ]) {
    for (const format of ['pem', 'der']) {
      assert.throws(() => sealReleaseManifest(source, key.export({ type: 'spki', format })));
    }
  }
});
test('CLI failures do not expose private input in logs', () => {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('../release/seal_local_release_manifest.mjs', import.meta.url))], {
    encoding: 'utf8',
    env: { ...process.env, RELEASE_MANIFEST: '{existing-private-fixture' },
  });
  assert.equal(result.status, 1);
  assert.ok(!`${result.stdout}${result.stderr}`.includes('existing-private-fixture'));
  assert.equal(result.stderr.trim(), 'Existing release input could not be sealed.');
});

for (const format of ['pem', 'der']) test(`CLI accepts ${format.toUpperCase()} SPKI public keys without corrupting their bytes`, t => {
  const directory = mkdtempSync(join(tmpdir(), 'festapp-sealed-input-test-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const output = join(directory, 'sealed.json');
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('../release/seal_local_release_manifest.mjs', import.meta.url)), output], {
    encoding: 'utf8',
    env: { ...process.env, RELEASE_MANIFEST: source, RELEASE_TENANT_ID: 'festapptickets',
      RECIPIENT_PUBLIC_KEY_BASE64: Buffer.from(publicKey.export({ type: 'spki', format })).toString('base64') },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.ok(!`${result.stdout}${result.stderr}`.includes('existing-private-fixture'));
  const envelope = JSON.parse(readFileSync(output, 'utf8'));
  const key = crypto.privateDecrypt({ key: privateKey, oaepHash: 'sha256' }, Buffer.from(envelope.encryptedKey, 'base64'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
  assert.equal(Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext, 'base64')), decipher.final()]).toString(), source);
});

test('explicit tenant selection binds the sealed envelope to the requested manifest', () => {
  for (const tenant of ['festapp', 'festivalslunovrat', 'hvezdamorska']) {
    const selected = JSON.stringify({ backend: { activation: { tenantId: tenant } } });
    assert.equal(sealReleaseManifest(selected, publicPem, tenant).tenantId, tenant);
    assert.throws(() => sealReleaseManifest(source, publicPem, tenant));
  }
  assert.throws(() => sealReleaseManifest(source, publicPem, '../festapptickets'));
});
