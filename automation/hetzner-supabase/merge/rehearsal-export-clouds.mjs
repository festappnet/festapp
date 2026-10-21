#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import {
  SOURCES,
  accessToken,
  assertPrivateOutput,
  managementQuery,
  quoteIdentifier,
} from './lib.mjs';

const POOLER_HOST = 'aws-0-eu-central-1.pooler.supabase.com';
const APPROVED_EXPORT_SSH_TARGET = 'root@46.224.187.4';

async function privilegedQuery({ projectRef, token, query, secrets = [] }) {
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${projectRef}/database/query`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ query }),
    },
  );
  if (!response.ok) {
    let detail = await response.text();
    for (const secret of [token, ...secrets]) detail = detail.replaceAll(secret, '<redacted>');
    throw new Error(`privileged query failed for ${projectRef}: HTTP ${response.status}: ${detail.slice(0, 1200)}`);
  }
}

function runExporter({ alias, output, databaseUrl, recipient }) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      [new URL('./export-source.mjs', import.meta.url).pathname, alias, output],
      {
        env: {
          ...process.env,
          FESTAPP_SOURCE_DATABASE_URL: databaseUrl,
          FESTAPP_EXPORT_AGE_RECIPIENT: recipient,
        },
        stdio: ['ignore', 'inherit', 'inherit'],
      },
    );
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${alias} exporter exited with code ${code}`));
    });
  });
}

async function createExportRole({ projectRef, token, role, password, validUntil }) {
  const existing = await managementQuery({
    projectRef,
    token,
    query: `SELECT count(*)::int AS role_count FROM pg_roles WHERE rolname = '${role}'`,
  });
  if (existing[0]?.role_count !== 0) throw new Error(`refusing existing export role on ${projectRef}`);
  const identifier = quoteIdentifier(role);
  await privilegedQuery({
    projectRef,
    token,
    secrets: [password],
    query: `BEGIN;
CREATE ROLE ${identifier} LOGIN PASSWORD '${password}' VALID UNTIL '${validUntil}' NOINHERIT;
ALTER ROLE ${identifier} BYPASSRLS;
GRANT pg_read_all_data TO ${identifier};
GRANT USAGE ON SCHEMA public, eshop TO ${identifier};
GRANT SELECT ON ALL TABLES IN SCHEMA public, eshop TO ${identifier};
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public, eshop TO ${identifier};
COMMIT;`,
  });
}

async function disableExportRole({ projectRef, token, role }) {
  const identifier = quoteIdentifier(role);
  await privilegedQuery({
    projectRef,
    token,
    query: `BEGIN;
ALTER ROLE ${identifier} NOLOGIN NOBYPASSRLS;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public, eshop FROM ${identifier};
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public, eshop FROM ${identifier};
REVOKE USAGE ON SCHEMA public, eshop FROM ${identifier};
REVOKE pg_read_all_data FROM ${identifier};
COMMIT;`,
  });
  const state = await managementQuery({
    projectRef,
    token,
    query: `SELECT rolcanlogin, rolbypassrls,
      pg_has_role('${role}', 'pg_read_all_data', 'MEMBER') AS has_read_all_data,
      (SELECT count(*)::int FROM pg_namespace n
        CROSS JOIN LATERAL aclexplode(n.nspacl) acl
        JOIN pg_roles granted_role ON granted_role.oid = acl.grantee
        WHERE n.nspname IN ('public', 'eshop')
          AND granted_role.rolname = '${role}') AS direct_schema_grants,
      (SELECT count(*)::int FROM information_schema.role_table_grants WHERE grantee = '${role}') AS table_grants
      FROM pg_roles WHERE rolname = '${role}'`,
  });
  if (state.length !== 1 || state[0].rolcanlogin || state[0].rolbypassrls ||
      state[0].has_read_all_data || state[0].direct_schema_grants !== 0 ||
      state[0].table_grants !== 0) {
    throw new Error(`export role did not reach disabled state on ${projectRef}`);
  }
}

async function main() {
  const [requestedRoot, publicKeyPath = path.join(process.env.HOME ?? '', '.ssh/id_ed25519.pub')] =
    process.argv.slice(2);
  if (!requestedRoot) {
    throw new Error('usage: rehearsal-export-clouds.mjs /private/evidence/root [ssh-public-key]');
  }
  const evidenceRoot = assertPrivateOutput(requestedRoot);
  const runId = `cloud-snapshots-${new Date().toISOString().replaceAll(/[^0-9]/g, '')}`;
  const runDir = path.join(evidenceRoot, runId);
  if (fs.existsSync(runDir)) throw new Error(`refusing existing run directory: ${runDir}`);
  fs.mkdirSync(runDir, { mode: 0o700 });
  const recipient = fs.readFileSync(publicKeyPath, 'utf8').trim();
  if (!recipient.startsWith('ssh-ed25519 ')) throw new Error('snapshot recipient must be an SSH Ed25519 public key');

  const token = accessToken();
  const requestedAliases = (process.env.FESTAPP_EXPORT_SOURCES ?? Object.keys(SOURCES).join(','))
    .split(',').filter(Boolean);
  if (requestedAliases.length === 0 || new Set(requestedAliases).size !== requestedAliases.length ||
      requestedAliases.some((alias) => !SOURCES[alias])) {
    throw new Error('FESTAPP_EXPORT_SOURCES must be a unique comma-separated subset of approved aliases');
  }
  const exportSshTarget = process.env.FESTAPP_EXPORT_SSH_TARGET;
  if (exportSshTarget && exportSshTarget !== APPROVED_EXPORT_SSH_TARGET) {
    throw new Error('FESTAPP_EXPORT_SSH_TARGET is not the approved rehearsal host');
  }
  const role = `festapp_export_${Date.now()}`;
  const validUntil = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  const created = [];
  let primaryError;
  try {
    for (const alias of requestedAliases) {
      const projectRef = SOURCES[alias];
      const password = crypto.randomBytes(32).toString('base64url');
      await createExportRole({ projectRef, token, role, password, validUntil });
      created.push({ alias, projectRef });
      const username = exportSshTarget ? role : `${role}.${projectRef}`;
      const databaseHost = exportSshTarget ? `db.${projectRef}.supabase.co` : POOLER_HOST;
      const databaseUrl = `postgresql://${encodeURIComponent(username)}:${encodeURIComponent(password)}@${databaseHost}:5432/postgres`;
      await runExporter({
        alias,
        output: path.join(runDir, `${alias}.dump.age`),
        databaseUrl,
        recipient,
      });
    }
  } catch (error) {
    primaryError = error;
  } finally {
    for (const source of created.reverse()) {
      try {
        await disableExportRole({ projectRef: source.projectRef, token, role });
        process.stdout.write(`${source.alias} export role disabled and read grant revoked\n`);
      } catch (error) {
        primaryError ??= error;
        process.stderr.write(`${source.alias} role cleanup failed: ${error.message}\n`);
      }
    }
  }
  if (primaryError) throw primaryError;
  process.stdout.write(`Encrypted source snapshots complete: ${runDir}\n`);
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
