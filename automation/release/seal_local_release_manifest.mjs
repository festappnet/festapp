import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

// Transfer the existing tenant secret to its owner's workstation, never logs.
export function sealReleaseManifest(source, publicKeyPem) {
  assert.ok(source, 'Existing release manifest is required');
  const manifest = JSON.parse(source);
  assert.equal(manifest.backend?.activation?.tenantId, 'festapptickets');
  const publicKey = crypto.createPublicKey(publicKeyPem);
  assert.equal(publicKey.asymmetricKeyType, 'rsa');
  assert.ok(publicKey.asymmetricKeyDetails.modulusLength >= 3072);
  const key = crypto.randomBytes(32);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(source, 'utf8'), cipher.final()]);
  return {
    schemaVersion: 1,
    tenantId: 'festapptickets',
    encryptedKey: crypto.publicEncrypt({ key: publicKey, oaepHash: 'sha256' }, key).toString('base64'),
    iv: iv.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
    ciphertext: ciphertext.toString('base64'),
    sourceSha256: crypto.createHash('sha256').update(source).digest('hex'),
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const envelope = sealReleaseManifest(process.env.RELEASE_MANIFEST,
      Buffer.from(process.env.RECIPIENT_PUBLIC_KEY_BASE64 || '', 'base64').toString('utf8'));
    fs.writeFileSync(process.argv[2], JSON.stringify(envelope), { mode: 0o600 });
    console.log('Existing tenant release input sealed for the recipient.');
  } catch {
    console.error('Existing release input could not be sealed.');
    process.exitCode = 1;
  }
}
