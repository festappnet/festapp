import {readFile, writeFile} from 'node:fs/promises';
// Promote only after the documented release compatibility gate passes.
export const CSP_MODE = 'report-only';
export const BASE_POLICY = "base-uri 'self'; object-src 'none'";
export function scriptPolicy(profile, hashes) {
  // Flutter CanvasKit compiles WASM. OneSignal is loaded by web/index.html.
  // Kept in Report-Only until the full compatibility gate supplies runtime proof.
  const extra = profile === 'flutter' ? " 'wasm-unsafe-eval' https://cdn.onesignal.com" : '';
  return `${BASE_POLICY}; script-src 'self'${extra}${hashes.length ? ' ' + hashes.join(' ') : ''}; script-src-attr 'none'; report-uri /_security/csp-report?profile=${profile}; report-to csp-${profile}`;
}
export function headerBlock(policy, profile) {
  return CSP_MODE === 'enforce'
    ? `  Content-Security-Policy: ${policy}\n  Reporting-Endpoints: csp-${profile}="/_security/csp-report?profile=${profile}"\n`
    : `  Content-Security-Policy: ${BASE_POLICY}\n  Content-Security-Policy-Report-Only: ${policy}\n  Reporting-Endpoints: csp-${profile}="/_security/csp-report?profile=${profile}"\n`;
}

if (process.argv[2] === '--sync-headers') {
  const template = await readFile(new URL('web_headers.template', import.meta.url), 'utf8');
  const headers = template.replace('/*\n', `/*\n  Content-Security-Policy: ${BASE_POLICY}\n`);
  for (const file of ['../../web/_headers', '../../web_client/public/_headers']) await writeFile(new URL(file, import.meta.url), headers);
}
