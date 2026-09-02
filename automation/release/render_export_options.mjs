#!/usr/bin/env node
import fs from 'node:fs';

const [manifestPath, outputPath] = process.argv.slice(2);
if (!manifestPath || !outputPath) throw new Error('usage: render_export_options.mjs MANIFEST OUTPUT');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const required = (value, name) => {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`missing ${name}`);
  return value.trim();
};
const escapeXml = (value) => value
  .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;').replaceAll("'", '&apos;');
const appBundle = required(manifest.bundleId, 'bundleId');
const extensionBundle = required(manifest.notificationExtensionBundleId, 'notificationExtensionBundleId');
const team = required(manifest.signingTeamId, 'signingTeamId');
const appProfile = required(manifest.signingProfiles?.app, 'signingProfiles.app');
const extensionProfile = required(manifest.signingProfiles?.notificationExtension, 'signingProfiles.notificationExtension');

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>teamID</key><string>${escapeXml(team)}</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
  <key>provisioningProfiles</key>
  <dict>
    <key>${escapeXml(appBundle)}</key><string>${escapeXml(appProfile)}</string>
    <key>${escapeXml(extensionBundle)}</key><string>${escapeXml(extensionProfile)}</string>
  </dict>
</dict>
</plist>
`;
fs.writeFileSync(outputPath, xml, { mode: 0o600, flag: 'w' });
