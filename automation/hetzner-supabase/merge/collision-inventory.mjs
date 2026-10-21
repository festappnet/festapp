#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { accessToken, assertCanonicalDefaultTarget, assertNewEvidencePaths, assertPrivateOutput, managementQuery, sha256, stableJson, SOURCE_ALIASES, SOURCES } from './lib.mjs';
import { classifyAuthCollisions, classifyStorageCollisions } from './collision-lib.mjs';

const outputIndex = process.argv.indexOf('--output');
const sourceIndex = process.argv.indexOf('--source');
const canonicalDatabaseIndex = process.argv.indexOf('--canonical-database');
if (outputIndex < 0 || !process.argv[outputIndex + 1] || sourceIndex < 0 || !process.argv[sourceIndex + 1]) {
  throw new Error(`usage: collision-inventory.mjs --source ${SOURCE_ALIASES.filter((alias) => alias !== 'default').join('|')} --output /private/path/collisions.json`);
}
const output = assertPrivateOutput(process.argv[outputIndex + 1]);
const sourceAlias = process.argv[sourceIndex + 1];
const canonicalDatabase = canonicalDatabaseIndex < 0 ? null : process.argv[canonicalDatabaseIndex + 1];
const sourcePosition = SOURCE_ALIASES.indexOf(sourceAlias);
if (sourcePosition < 1) throw new Error('collision source must be an approved non-default source');
if (canonicalDatabase !== null && !/^festapp_rehearsal_[0-9]{14}$/.test(canonicalDatabase)) {
  throw new Error('canonical collision target must be a timestamped isolated rehearsal database');
}
if (sourcePosition > 1 && canonicalDatabase === null) {
  throw new Error('third and later sources require --canonical-database to avoid ambiguous historical ownership');
}
const comparisonAliases = canonicalDatabase === null ? SOURCE_ALIASES.slice(0, sourcePosition) : ['canonical'];
const token = accessToken();
const hmacKey = crypto.randomBytes(32);
await assertCanonicalDefaultTarget({ token });

async function collectRows(queryRows) {
  const users = await queryRows(`SELECT id::text, lower(trim(email)) AS normalized_email,
      nullif(trim(phone), '') AS normalized_phone,
      email_confirmed_at IS NOT NULL AS verified,
      phone_confirmed_at IS NOT NULL AS phone_verified,
      COALESCE(is_sso_user, false) AS is_sso_user,
      COALESCE(is_anonymous, false) AS is_anonymous,
      nullif(confirmation_token, '') IS NOT NULL AS confirmation_pending,
      nullif(recovery_token, '') IS NOT NULL AS recovery_pending,
      (nullif(email_change_token_current, '') IS NOT NULL OR nullif(email_change_token_new, '') IS NOT NULL OR email_change_confirm_status <> 0) AS email_change_pending,
      nullif(phone_change_token, '') IS NOT NULL AS phone_change_pending,
      nullif(reauthentication_token, '') IS NOT NULL AS reauthentication_pending
      FROM auth.users ORDER BY id`);
  const identities = await queryRows(`SELECT user_id::text, provider, provider_id
    FROM auth.identities ORDER BY user_id, provider, provider_id`);
  const mfa = await queryRows(`SELECT user_id::text, factor_type::text, status::text
    FROM auth.mfa_factors ORDER BY user_id, factor_type, status`);
  const providersByUser = groupByUser(identities);
  const mfaByUser = groupByUser(mfa);
  for (const user of users) {
    user.provider_links = (providersByUser.get(user.id) ?? []).map(({ provider, provider_id }) => ({ provider, provider_id }));
    user.providers = [...new Set(user.provider_links.map((identity) => identity.provider))].sort();
    user.mfa = (mfaByUser.get(user.id) ?? []).map(({ factor_type, status }) => ({ factor_type, status }));
  }
  const storage = await queryRows(`SELECT bucket_id, name, metadata->>'eTag' AS etag,
      CASE WHEN metadata->>'size' ~ '^[0-9]+$' THEN (metadata->>'size')::bigint ELSE NULL END AS size
      FROM storage.objects ORDER BY bucket_id, name`);
  return { users, storage };
}

async function sourceRows(projectRef) {
  return collectRows((query) => managementQuery({ projectRef, token, query }));
}

async function canonicalRows(database) {
  return collectRows(async (query) => {
    const command = 'docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U postgres ' +
      `-d ${database} -At`;
    const result = spawnSync('ssh', ['-T', '-o', 'BatchMode=yes', 'root@46.224.187.4', command], {
      encoding: 'utf8',
      input: `SELECT row_to_json(result) FROM (${query}) result;\n`,
      maxBuffer: 64 * 1024 * 1024,
    });
    if (result.status !== 0) {
      throw new Error(`canonical collision query failed: ${(result.stderr ?? '').slice(0, 800)}`);
    }
    return result.stdout.split(/\r?\n/).filter(Boolean).map((line) => JSON.parse(line));
  });
}

function groupByUser(rows) {
  const grouped = new Map();
  for (const row of rows) {
    const values = grouped.get(row.user_id) ?? [];
    values.push(row);
    grouped.set(row.user_id, values);
  }
  return grouped;
}

function relabelAuth(auth) {
  const relabel = (entry) => Object.fromEntries(Object.entries(entry).map(([key, value]) => {
    if (key.startsWith('default_')) return [`canonical_${key.slice('default_'.length)}`, value];
    if (key.startsWith('a_')) return [`source_${key.slice('a_'.length)}`, value];
    return [key, value];
  }));
  return Object.fromEntries(Object.entries(auth).map(([kind, entries]) => [
    kind,
    entries.map(relabel),
  ]));
}

const source = await sourceRows(SOURCES[sourceAlias]);
const comparisons = Object.fromEntries(await Promise.all(comparisonAliases.map(async (alias) => {
  const canonical = alias === 'canonical'
    ? await canonicalRows(canonicalDatabase)
    : await sourceRows(SOURCES[alias]);
  return [alias, {
    auth: relabelAuth(classifyAuthCollisions(canonical.users, source.users, hmacKey)),
    storage: classifyStorageCollisions(canonical.storage, source.storage, hmacKey),
  }];
})));
const totals = Object.values(comparisons).reduce((result, comparison) => ({
  same_uuid_different_email: result.same_uuid_different_email + comparison.auth.same_uuid_different_email.length,
  same_email_different_uuid: result.same_email_different_uuid + comparison.auth.same_email_different_uuid.length,
  same_provider_identity_different_uuid: result.same_provider_identity_different_uuid + comparison.auth.same_provider_identity_different_uuid.length,
  same_verified_phone_different_uuid: result.same_verified_phone_different_uuid + comparison.auth.same_verified_phone_different_uuid.length,
  storage_key_collisions: result.storage_key_collisions + comparison.storage.length,
  storage_content_blockers: result.storage_content_blockers + comparison.storage.filter((value) => value.status === 'content-collision-blocker').length,
}), {
  same_uuid_different_email: 0,
  same_email_different_uuid: 0,
  same_provider_identity_different_uuid: 0,
  same_verified_phone_different_uuid: 0,
  storage_key_collisions: 0,
  storage_content_blockers: 0,
});
const report = {
  report_version: 3,
  generated_at: new Date().toISOString(),
  source_alias: sourceAlias,
  sources: Object.fromEntries(SOURCE_ALIASES.map((alias) => [alias, SOURCES[alias]])),
  compared_against: comparisonAliases,
  privacy: 'emails and Storage object keys are HMACed with an ephemeral key that is not persisted',
  comparisons,
  validation: {
    status: 'blocked',
    ...totals,
    notes: [
      'all identity collisions require explicit decisions in the private mapping workspace',
      'matching Storage metadata is not content proof; object SHA-256 comparison remains required',
      'UUID and natural-key collisions outside Auth require the table-level collision pass',
    ],
  },
};
report.report_sha256 = sha256(stableJson(report));
assertNewEvidencePaths([output]);
fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
process.stdout.write(`collision inventory ${sourceAlias}: against=${comparisonAliases.join(',')} auth_uuid=${report.validation.same_uuid_different_email}, auth_email=${report.validation.same_email_different_uuid}, storage_keys=${report.validation.storage_key_collisions}, sha256=${report.report_sha256}\n`);
