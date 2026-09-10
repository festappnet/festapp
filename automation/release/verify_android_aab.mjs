#!/usr/bin/env node

import { execFileSync, spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

function run(command, args, options = {}) {
  return execFileSync(command, args, { encoding: 'utf8', ...options }).trim();
}

function normalizeFingerprint(value) {
  return value.replaceAll(':', '').trim().toLowerCase();
}

function main() {
  const [aabValue, manifestValue, sourceSha, receiptValue] = process.argv.slice(2);
  if (!aabValue || !manifestValue || !/^[0-9a-f]{40}$/.test(sourceSha ?? '') || !receiptValue) {
    throw new Error('Usage: verify_android_aab.mjs <aab> <manifest> <source-sha> <receipt>');
  }
  const aab = fs.realpathSync(aabValue);
  const manifest = JSON.parse(fs.readFileSync(fs.realpathSync(manifestValue), 'utf8'));
  const expectedFingerprint = normalizeFingerprint(process.env.EXPECTED_UPLOAD_CERT_SHA256 ?? '');
  const toolingSha = process.env.TOOLING_SHA?.toLowerCase();
  if (!/^[0-9a-f]{40}$/.test(toolingSha ?? '')) throw new Error('TOOLING_SHA is missing');
  if (!/^[0-9a-f]{64}$/.test(expectedFingerprint)) {
    throw new Error('EXPECTED_UPLOAD_CERT_SHA256 must contain the approved upload certificate SHA-256');
  }

  run('jarsigner', ['-verify', '-strict', aab]);
  const certificate = run('keytool', ['-printcert', '-jarfile', aab]);
  const actualFingerprint = normalizeFingerprint(certificate.match(/^\s*SHA256:\s*(.+)$/m)?.[1] ?? '');
  if (actualFingerprint !== expectedFingerprint) throw new Error('AAB signer differs from the approved upload certificate');

  const bundletool = process.env.BUNDLETOOL_JAR;
  if (!bundletool || !fs.existsSync(bundletool)) throw new Error('BUNDLETOOL_JAR is missing');
  const xml = run('java', ['-jar', bundletool, 'dump', 'manifest', `--bundle=${aab}`]);
  const packageName = xml.match(/\bpackage="([^"]+)"/)?.[1];
  const versionCode = Number(xml.match(/\bandroid:versionCode="(\d+)"/)?.[1]);
  if (packageName !== manifest.androidPackage) throw new Error('AAB package differs from release manifest');
  if (!Number.isSafeInteger(versionCode) || versionCode < 1) throw new Error('AAB has no valid Android version code');

  const markerPattern = /(bujnmi|miakh|\/Users\/|[A-Za-z]:\\Users\\)/i;
  const names = run('unzip', ['-Z1', aab]);
  if (markerPattern.test(names)) throw new Error('AAB contains a forbidden personal path or identity marker');
  const strings = spawnSync('bash', ['-c', 'set -o pipefail; unzip -p "$1" | strings', 'scan-aab', aab], {
    encoding: 'utf8', maxBuffer: 128 * 1024 * 1024,
  });
  if (strings.status !== 0) throw new Error('Could not scan AAB contents');
  if (markerPattern.test(strings.stdout)) throw new Error('AAB contains a forbidden personal path or identity marker');

  const artifactSha256 = crypto.createHash('sha256').update(fs.readFileSync(aab)).digest('hex');
  const receipt = {
    schemaVersion: 1,
    packageName,
    versionCode,
    sourceSha,
    toolingSha,
    artifactSha256,
    uploadCertificateSha256: actualFingerprint,
    builder: 'github-actions/ubuntu',
  };
  fs.writeFileSync(receiptValue, `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
  process.stdout.write(JSON.stringify(receipt));
}

try { main(); } catch (error) {
  console.error(`ERROR: ${error.message}`);
  process.exit(1);
}
