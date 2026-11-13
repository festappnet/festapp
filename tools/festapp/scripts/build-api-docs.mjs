import {API_DATA_PROFILES,API_PROOF_PROFILES,apiProjectionDirectory} from '../src/remote/endpoints.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { facades, generate } from './generate-api-reference.mjs';
generate({ check: true });
const checking = process.argv.includes('--check');
for (const facade of facades) for (const profile of API_DATA_PROFILES) for (const proofProfile of API_PROOF_PROFILES) {
    const directory = new URL('../contracts/api-v1/' + apiProjectionDirectory(facade.endpointId,profile,proofProfile) + '/', import.meta.url);
    const target = new URL('docs/index.html', directory);
    const temporary = fs.mkdtempSync(path.join(os.tmpdir(),'festapp-api-docs-'));
    const out = new URL('file://' + path.join(temporary,'reference.html'));
    fs.mkdirSync(new URL('docs/',directory), { recursive: true });
    execFileSync('pnpm',['exec','redocly','build-docs',new URL('openapi.json',directory).pathname,'--inlineBundle','--output',out.pathname,'--config',new URL('../redocly.yaml',import.meta.url).pathname], { env: { ...process.env, REDOCLY_TELEMETRY: 'off' }, stdio: ['ignore','pipe','pipe'] });
    let html = fs.readFileSync(out,'utf8');
    // The pinned tool still emits a CDN logo even with inlineBundle. Remove the
    // branding image and deny all networking in the self-contained document.
    html = html.replaceAll('https://cdn.redoc.ly/redoc/logo-mini-full.svg', 'data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%2272%22 height=%2220%22%3E%3Ctext x=%220%22 y=%2215%22 font-size=%2214%22%3ERedoc%3C/text%3E%3C/svg%3E');
    html = html.replace(/<img\b[^>]*src=["']https?:\/\/[^>]*>/gi,'');
    const specification = JSON.parse(fs.readFileSync(new URL('openapi.json',directory)));
    const exampleJson = JSON.stringify(specification.paths['/operations/context.inspect'].post.requestBody.content['application/json'].example);
    const exampleHtml = value => value.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
    const manifest = JSON.parse(fs.readFileSync(new URL('manifest.json',directory)));
    const profileLinks = API_DATA_PROFILES.flatMap(data => API_PROOF_PROFILES.map(proof => {
        const destination = new URL('../contracts/api-v1/'+apiProjectionDirectory(facade.endpointId,data,proof)+'/docs/index.html',import.meta.url);
        return `<a href="${path.relative(new URL('docs/',directory).pathname,destination.pathname)}">${data} / ${proof}</a>`;
    })).join(' | ');
    const onboarding = `<aside style="padding:16px;background:white;color:#17202a;font:14px system-ui"><strong>${facade.brand} - ${profile} / ${proofProfile}</strong><p>${profileLinks}</p><p>Contract ${manifest.contractVersion}; projectionDigest: <code>${manifest.projectionDigest}</code></p><p>Register an explicit client, authorize with code + PKCE S256 at ${facade.issuer}/auth and resource ${facade.resource}. Select one context and consented units/events. Exchange with the same issuer and resource; verify callback iss and state. Inspect context.inspect and access.inspect before scoped operations. Keep tokens in protected storage.</p><p>For writes read the aggregate version, preserve commandId and payload through retry, and use required preview/confirmation. A timeout or revocation after admission can hide a committed write: an authorized administrator must establish its outcome before any replacement command. A new connection is not permission to duplicate an uncertain command.</p><p>Sensitive operations in the DPoP projection require a registered DPoP + PAR client and GoTrue-verified AAL2 authentication from a verified TOTP factor no older than 300 seconds. Refresh does not renew MFA time. An insufficient_user_authentication challenge includes acr_values=urn:festapp:aal2 and max_age=300; reconnect and verify a new code in the tenant consent. Request-body authentication claims are ignored.</p><p>Artwork: retain the complete original saveRequest. Repeating it preserves the same canonical SQL command after an uncertain outward reply, including after reconnect. Pending/resume recovers unresolved upstream results.</p><p>Serialize refresh and atomically store the new refresh token. Lost responses or reuse require reconnect. Revoke at ${facade.issuer}/token/revocation. Artifacts require the original active grant and scopes, expire after 15 minutes, and disappear on restart. API cookies do not authenticate requests. No autonomous service identities.</p>${proofProfile === 'dpop' ? '<p>Use a DPoP-capable OAuth client to sign every request; the reference describes all required token and proof headers.</p>' : `<p>Shell read: <code>curl -X POST '${facade.publicBase}/operations/context.inspect' -H "Authorization: ${proofProfile === 'dpop' ? 'DPoP' : 'Bearer'} $ACCESS_TOKEN" -H 'Content-Type: application/json' -d '${exampleHtml(exampleJson)}'</code></p><p>Python read: <code>import json, requests; requests.post('${facade.publicBase}/operations/context.inspect', headers={'Authorization': '${proofProfile === 'dpop' ? 'DPoP' : 'Bearer'} '+access_token}, json=json.loads(${exampleHtml(JSON.stringify(exampleJson))}), timeout=30)</code></p><p>JavaScript read: <code>fetch('${facade.publicBase}/operations/context.inspect', {method:'POST',headers:{Authorization:'${proofProfile === 'dpop' ? 'DPoP' : 'Bearer'} '+accessToken,'Content-Type':'application/json'},body:JSON.stringify(${exampleHtml(exampleJson)})})</code></p>`}<p>Proof profile: ${proofProfile}. DPoP-only clients require Authorization: DPoP and a fresh signed proof on every retry, binding htm, public htu, ath, iat and jti to the token key; Bearer is never an alternative for a bound token.</p></aside>`;
    html = html.replace(/<head>/i, `<head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; base-uri 'none'">`).replace(/<body([^>]*)>/i,'<body$1>'+onboarding);
    if(checking){if(!fs.existsSync(target)||fs.readFileSync(target,'utf8')!==html)throw new Error('Static API reference drift: '+target.pathname);}
    else fs.writeFileSync(target,html);
    fs.rmSync(temporary,{recursive:true,force:true});
}
console.log(checking?'Offline API reference: 8 deterministic projections current.':'Offline API reference: 8 projections built.');
