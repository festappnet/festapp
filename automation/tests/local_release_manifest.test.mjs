import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
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
test('CLI failures do not expose private input in logs', () => {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('../release/seal_local_release_manifest.mjs', import.meta.url))], {
    encoding: 'utf8',
    env: { ...process.env, RELEASE_MANIFEST: '{existing-private-fixture' },
  });
  assert.equal(result.status, 1);
  assert.ok(!`${result.stdout}${result.stderr}`.includes('existing-private-fixture'));
  assert.equal(result.stderr.trim(), 'Existing release input could not be sealed.');
});
