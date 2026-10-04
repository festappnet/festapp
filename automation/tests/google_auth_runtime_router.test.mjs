import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
const patch = new URL('../hetzner-supabase/runtime/patch-function-proof-routes.py', import.meta.url).pathname;
test('runtime exposes Google and signed email proof endpoints and fails on upstream router drift',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'festapp-google-router-'));
  const file=path.join(dir,'index.ts');
  try {
    fs.writeFileSync(file,"if (req.method !== 'OPTIONS' && VERIFY_JWT) { verify(); }\nconst service_name = path_parts[1];\nconst envVars = Object.keys(envVarsObj).map((k) => [k, envVarsObj[k]]);\n");
    assert.equal(spawnSync('python3',[patch,file]).status,0);
    const source=fs.readFileSync(file,'utf8');
    assert.match(source,/google-auth-start/);assert.match(source,/google-auth-callback/);assert.match(source,/google-auth-complete/);
    assert.match(source,/process-email-queue/);assert.match(source,/auth-email-hook/);assert.match(source,/email-provider-events/);assert.match(source,/email-confirmation-status/);
    assert.match(source,/emailWorkerEnvironment\(service_name, envVarsObj\)/);
    assert.doesNotMatch(source,/send-email-gateway/);
    assert.doesNotMatch(source,/"register"|"send-email"/);
    assert.equal(spawnSync('python3',[patch,file]).status,0);
    assert.equal(fs.readFileSync(file,'utf8'),source);
    fs.writeFileSync(file,'if (VERIFY_JWT) { verify(); }');
    assert.notEqual(spawnSync('python3',[patch,file]).status,0);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

// Production schedules target DB jobs from postgres, never rehearsal cron stubs.
test('Google cleanup uses only the canonical control-plane scheduler', () => {
  const migration = fs.readFileSync(new URL('../../supabase/migrations/20261001150000_google_auth_broker.sql', import.meta.url), 'utf8');
  const installer = fs.readFileSync(new URL('../hetzner-supabase/runtime/install-google-auth-cleanup.sh', import.meta.url), 'utf8');
  assert.match(migration, /pg_extension WHERE extname = 'pg_cron'/);
  assert.match(migration, /current_database\(\) = current_setting\('cron.database_name', true\)/);
  assert.match(installer, /-d postgres/);
  assert.match(installer, /cron\.schedule_in_database\('festapp-external-login-cleanup-v1'/);
  assert.doesNotMatch(installer, /cron\.unschedule|ALTER SYSTEM|restart/);
});

test('runtime upgrades the former private sender guard and rejects environment drift atomically', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-email-router-'));
  const file = path.join(dir, 'index.ts');
  try {
    const upstream = "if (req.method !== 'OPTIONS' && VERIFY_JWT) { verify(); }\nconst service_name = path_parts[1];\nconst envVars = Object.keys(envVarsObj).map((k) => [k, envVarsObj[k]]);\n";
    const legacy = upstream.replace('const service_name = path_parts[1];', 'const service_name = path_parts[1];\nif (service_name === "send-email-gateway") return new Response("Not found", {status: 404}); /* festapp-email-gateway-private */');
    fs.writeFileSync(file, legacy);
    assert.equal(spawnSync('python3', [patch, file]).status, 0);
    assert.doesNotMatch(fs.readFileSync(file, 'utf8'), /send-email-gateway/);
    const drift = upstream.replace('Object.keys(envVarsObj).map((k) => [k, envVarsObj[k]])', 'Object.entries(envVarsObj)');
    fs.writeFileSync(file, drift);
    assert.notEqual(spawnSync('python3', [patch, file]).status, 0);
    assert.equal(fs.readFileSync(file, 'utf8'), drift);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
