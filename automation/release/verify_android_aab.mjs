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

function verifyJarSignature(aab) {
  const verification = spawnSync('jarsigner', ['-verify', '-strict', aab], {
    encoding: 'utf8',
  });
  // Android upload certificates are commonly self-signed. jarsigner reports
  // that condition (and an unvalidated self-signed chain) as strict code 4.
  // Every other strict bit remains fatal, including unsigned entries (16),
  // unsuitable key usage (8), wrong alias (32), and verification failure (1).
  if (![0, 4].includes(verification.status)) {
    throw new Error(`jarsigner rejected the AAB (strict exit ${verification.status ?? 'unknown'})`);
  }
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

  verifyJarSignature(aab);
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

  const hardMarkerPattern = /(bujnmi|\/Users\/|[A-Za-z]:\\Users\\)/i;
  const textMarkerPattern = /(bujnmi|miakh|\/Users\/|[A-Za-z]:\\Users\\)/i;
  const names = run('unzip', ['-Z1', aab]);
  if (textMarkerPattern.test(names)) throw new Error('AAB entry name contains a forbidden personal path or identity marker');
  const binaryScan = spawnSync('bash', ['-c', String.raw`
    set -euo pipefail
    scan_root="$(mktemp -d)"
    trap 'rm -rf "$scan_root"' EXIT
    unzip -qq "$1" -d "$scan_root"
    match="$({ find "$scan_root" -type f -print0 | xargs -0 strings -f || true; } |
      awk 'BEGIN { IGNORECASE=1 } /bujnmi|\/Users\/|[A-Za-z]:\\Users\\/ { sub(/:.*/, ""); print; exit }')"
    if [[ -n "$match" ]]; then
      printf '%s\n' "$match" | sed "s#^$scan_root/##"
    fi
  `, 'scan-aab', aab], { encoding: 'utf8', maxBuffer: 1024 * 1024 });
  if (binaryScan.status !== 0) throw new Error('Could not scan AAB contents');
  if (binaryScan.stdout.trim()) {
    throw new Error(`AAB entry contains a forbidden personal path or identity marker: ${binaryScan.stdout.trim()}`);
  }
  const textEntries = names.split('\n').filter((name) => /\.(?:css|csv|html?|js|json|md|properties|toml|txt|xml|ya?ml)$/i.test(name));
  for (const entry of textEntries) {
    const contents = run('unzip', ['-p', aab, entry], { maxBuffer: 32 * 1024 * 1024 });
    if (textMarkerPattern.test(contents)) throw new Error(`AAB text entry contains a forbidden personal marker: ${entry}`);
  }

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
