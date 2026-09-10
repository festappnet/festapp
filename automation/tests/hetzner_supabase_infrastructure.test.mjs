import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import os from 'node:os';
import test from 'node:test';

const root = path.resolve(import.meta.dirname, '../..');
const terraformDir = path.join(root, 'automation/hetzner-supabase/terraform');

function read(name) {
  return fs.readFileSync(path.join(terraformDir, name), 'utf8');
}

test('Hetzner rehearsal module pins stable Terraform/provider and protected low-cost compute', () => {
  const versions = read('versions.tf');
  const variables = read('variables.tf');
  const server = read('server.tf');
  const pins = JSON.parse(fs.readFileSync(path.join(root, 'automation/hetzner-supabase/runtime/pins.json')));

  assert.match(versions, /required_version\s*=\s*"~> 1\.16\.0"/);
  assert.match(versions, /version\s*=\s*"= 1\.68\.0"/);
  assert.match(variables, /default\s*=\s*"cax11"/);
  assert.match(variables, /default\s*=\s*"nbg1"/);
  assert.equal(pins.architecture, 'linux/arm64');
  assert.equal(pins.supabase.registryEvidence.platform, pins.architecture);
  assert.match(server, /delete_protection\s*=\s*true/);
  assert.match(server, /rebuild_protection\s*=\s*true/);
  assert.match(server, /backups\s*=\s*var\.enable_backups/);
  assert.match(variables, /variable "enable_backups"[\s\S]*default\s*=\s*false/);
});

test('Hetzner firewall never exposes PostgreSQL and restricts SSH to approved CIDRs', () => {
  const firewall = read('firewall.tf');
  assert.doesNotMatch(firewall, /port\s*=\s*"5432"/);
  assert.match(firewall, /port\s*=\s*"22"[\s\S]*source_ips\s*=\s*var\.admin_cidrs/);
  assert.match(firewall, /port\s*=\s*"80"/);
  assert.match(firewall, /port\s*=\s*"443"/);
});

test('Hetzner provisioning refuses an unrestricted SSH allowlist', () => {
  const variables = read('variables.tf');
  assert.match(variables, /admin_cidrs must contain explicit IPv4 or IPv6 CIDRs/);
  assert.match(variables, /0\.0\.0\.0\/0/);
  assert.match(variables, /::\/0/);
});

test('rehearsal runtime is immutable, loopback-only and non-destructive', () => {
  const runtime = path.join(root, 'automation/hetzner-supabase/runtime');
  const deploy = fs.readFileSync(path.join(runtime, 'deploy-rehearsal.sh'), 'utf8');
  const compose = fs.readFileSync(path.join(runtime, 'docker-compose.festapp.yml'), 'utf8');
  const caddy = fs.readFileSync(path.join(runtime, 'Caddyfile'), 'utf8');
  const databaseTarget = fs.readFileSync(path.join(runtime, 'docker-compose.database-target.yml'), 'utf8');
  assert.match(deploy, /241bb11c0627f2981746d37033f57dbfa81d29b0/);
  assert.match(deploy, /refusing to overwrite/);
  assert.doesNotMatch(deploy, /rm\s|down\s+-v|prune/);
  assert.match(compose, /127\.0\.0\.1:8000:8000/);
  assert.match(compose, /FESTAPP_SUPABASE_SITE_ADDRESSES/);
  assert.match(compose, /FESTAPP_SUPABASE_ADMIN_SITE/);
  assert.match(compose, /FESTAPP_SUPABASE_ADMIN_HOSTNAME/);
  assert.match(compose, /FESTAPP_SUPABASE_ADMIN_BASIC_AUTH/);
  assert.match(compose, /QR_RATE_SALT: \$\{QR_RATE_SALT:\?configure QR_RATE_SALT/);
  assert.match(compose, /SMTP_HOSTNAME: \$\{SMTP_HOST\}/);
  assert.match(compose, /PROJECT_URL: http:\/\/api-gw:8000/);
  assert.doesNotMatch(compose, /5432:5432/);
  assert.equal((compose.match(/@sha256:/g) ?? []).length, 13);
  assert.match(compose, /admin-tunnel:[\s\S]*profiles:[\s\S]*admin-dashboard/);
  assert.match(compose, /admin-tunnel:[\s\S]*network_mode: host/);
  assert.match(compose, /admin-tunnel:[\s\S]*--token-file/);
  assert.match(compose, /admin-tunnel:[\s\S]*read_only: true/);
  assert.match(compose, /admin-tunnel:[\s\S]*user: "0:0"/);
  assert.match(compose, /admin-tunnel:[\s\S]*cap_drop:[\s\S]*- ALL/);
  assert.match(caddy, /http:\/\/\{\$FESTAPP_SUPABASE_ADMIN_HOSTNAME:supabase\.festapp\.net\}:8999[\s\S]*bind 127\.0\.0\.1/);
  assert.match(caddy, /request_header Authorization "Basic \{\$FESTAPP_SUPABASE_ADMIN_BASIC_AUTH\}"/);
  for (const service of ['auth', 'rest', 'realtime', 'storage', 'meta', 'functions', 'studio']) {
    assert.match(databaseTarget, new RegExp(`^  ${service}:`, 'm'));
  }
  assert.match(databaseTarget, /storage:[\s\S]*DATABASE_URL:[\s\S]*FESTAPP_RUNTIME_DATABASE/);
  assert.match(deploy, /caddy\/Caddyfile/);
  assert.match(deploy, /switch-rehearsal-runtime-database\.sh/);
  assert.match(deploy, /activate-admin-dashboard\.sh/);
  const verifier = fs.readFileSync(path.join(runtime, 'verify-pins.mjs'), 'utf8');
  assert.match(verifier, /assert\.ok\(arm64, `\$\{name\} has no linux\/arm64 registry manifest`\)/);
  assert.doesNotMatch(verifier, /\?\? manifests\[0\]/);
});

test('rehearsal environment remains valid when sourced by a shell', () => {
  const runtime = path.join(root, 'automation/hetzner-supabase/runtime');
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-rehearsal-env-'));
  fs.writeFileSync(
    path.join(tempDir, '.env'),
    'STUDIO_DEFAULT_ORGANIZATION=Default Organization\nSTUDIO_DEFAULT_PROJECT=Default Project\n',
  );

  const configured = spawnSync('python3', [path.join(runtime, 'configure-rehearsal-env.py')], {
    cwd: tempDir,
    encoding: 'utf8',
  });
  assert.equal(configured.status, 0, configured.stderr);
  const envText = fs.readFileSync(path.join(tempDir, '.env'), 'utf8');
  assert.match(envText, /STUDIO_DEFAULT_ORGANIZATION='Festapp Rehearsal'/);
  assert.match(envText, /STUDIO_DEFAULT_PROJECT='Canonical Merge Rehearsal'/);
  assert.match(envText, /^FESTAPP_RUNTIME_DATABASE=postgres$/m);
  assert.match(envText,
    /^FESTAPP_SUPABASE_SITE_ADDRESSES='rehearsal-api\.festapp\.net, api\.festapp\.net'$/m);
  assert.match(envText, /^FESTAPP_SUPABASE_ADMIN_SITE=http:\/\/127\.0\.0\.1:8999$/m);
  assert.match(envText, /https:\/\/csmostrava\.festapp\.net\/reset-password/);
  assert.match(envText, /https:\/\/hvezdamorska\.netlify\.app\/auth_bridge\.html/);
  assert.match(envText, /https:\/\/jubileum2025\.festapp\.net\/auth_bridge\.html/);
  assert.match(envText, /https:\/\/jubileum2025\.netlify\.app\/reset-password/);
  assert.match(envText, /https:\/\/clovekavira\.pages\.dev\/resetPassword/);
  assert.match(envText, /https:\/\/app\.festivalslunovrat\.cz\/auth_bridge/);
  const qrRateSalt = envText.match(/^QR_RATE_SALT=([^\n]+)$/m)?.[1];
  assert.ok(qrRateSalt && qrRateSalt.length >= 32);

  const configuredAgain = spawnSync('python3', [path.join(runtime, 'configure-rehearsal-env.py')], {
    cwd: tempDir,
    encoding: 'utf8',
  });
  assert.equal(configuredAgain.status, 0, configuredAgain.stderr);
  assert.equal(fs.readFileSync(path.join(tempDir, '.env'), 'utf8').match(/^QR_RATE_SALT=([^\n]+)$/m)?.[1],
    qrRateSalt);

  const sourced = spawnSync('bash', ['-c', 'set -a; source "$1"', 'bash', path.join(tempDir, '.env')], {
    encoding: 'utf8',
  });
  assert.equal(sourced.status, 0, sourced.stderr);

  const explicitTarget = spawnSync('python3', [path.join(runtime, 'configure-rehearsal-env.py')], {
    cwd: tempDir,
    encoding: 'utf8',
    env: { ...process.env, FESTAPP_RUNTIME_DATABASE: 'festapp_rehearsal_20260828234500' },
  });
  assert.equal(explicitTarget.status, 0, explicitTarget.stderr);
  assert.match(fs.readFileSync(path.join(tempDir, '.env'), 'utf8'),
    /^FESTAPP_RUNTIME_DATABASE=festapp_rehearsal_20260828234500$/m);

  const authConfigured = spawnSync('python3', [path.join(runtime, 'configure-rehearsal-env.py')], {
    cwd: tempDir,
    encoding: 'utf8',
    env: {
      ...process.env,
      FESTAPP_AUTH_SITE_URL: 'https://rehearsal-web.festapp.net',
      FESTAPP_AUTH_ADDITIONAL_ORIGINS:
        'https://csmostrava.festapp.net,https://hvezdamorska.festapp.net,https://clovekavira.festapp.net',
      FESTAPP_AUTH_REDIRECT_URLS:
        'https://rehearsal-web.festapp.net/auth_bridge,https://clovekavira.festapp.net/transfer',
    },
  });
  assert.equal(authConfigured.status, 0, authConfigured.stderr);
  const authEnv = fs.readFileSync(path.join(tempDir, '.env'), 'utf8');
  assert.match(authEnv, /^SITE_URL=https:\/\/rehearsal-web\.festapp\.net$/m);
  assert.match(authEnv,
    /^ADDITIONAL_REDIRECT_URLS=.*https:\/\/rehearsal-web\.festapp\.net\/reset-password.*https:\/\/clovekavira\.festapp\.net\/auth_bridge\.html.*https:\/\/clovekavira\.festapp\.net\/transfer$/m);
  assert.match(authEnv,
    /^FESTAPP_ALLOWED_WEB_ORIGINS=https:\/\/rehearsal-web\.festapp\.net,https:\/\/csmostrava\.festapp\.net,https:\/\/hvezdamorska\.festapp\.net,https:\/\/clovekavira\.festapp\.net$/m);

  const foreignRedirect = spawnSync('python3', [path.join(runtime, 'configure-rehearsal-env.py')], {
    cwd: tempDir,
    encoding: 'utf8',
    env: {
      ...process.env,
      FESTAPP_AUTH_SITE_URL: 'https://rehearsal-web.festapp.net',
      FESTAPP_AUTH_ADDITIONAL_ORIGINS: 'https://csmostrava.festapp.net',
      FESTAPP_AUTH_REDIRECT_URLS: 'https://attacker.example/callback',
    },
  });
  assert.notEqual(foreignRedirect.status, 0);

  const invalidTarget = spawnSync('python3', [path.join(runtime, 'configure-rehearsal-env.py')], {
    cwd: tempDir,
    encoding: 'utf8',
    env: { ...process.env, FESTAPP_RUNTIME_DATABASE: 'unsafe-db-name' },
  });
  assert.notEqual(invalidTarget.status, 0);
});
