#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import {
  loadCanonicalSupabaseTarget,
  managementQuery,
} from './lib/supabase_management.mjs';

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(moduleDirectory, '..');

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

export function buildCsvInviteAuditSql(target) {
  const occasionLink = sqlLiteral(target.occasionLink);
  return `
WITH target_occasion AS (
  SELECT id, title, link, organization
  FROM public.occasions
  WHERE link = ${occasionLink} AND organization = ${target.organization}
), roster AS (
  SELECT
    ou."user" AS user_id,
    ui.name,
    ui.surname,
    lower(trim(ui.email_readonly)) AS account_email,
    lower(COALESCE(NULLIF(trim(ui.email_delivery), ''), trim(ui.email_readonly)))
      AS delivery_email,
    ou.created_at AS membership_created_at,
    ou.data ? 'is_invited' AS has_legacy_invited_flag,
    au.last_sign_in_at
  FROM public.occasion_users ou
  JOIN public.user_info ui ON ui.id = ou."user"
  LEFT JOIN auth.users au ON au.id = ou."user"
  WHERE ou.occasion = (SELECT id FROM target_occasion)
), sign_in_logs AS (
  SELECT le.recipient_user AS user_id, lower(trim(le."to")) AS delivery_email,
         le.created_at
  FROM public.log_emails le
  JOIN public.email_templates et ON et.id::text = le.template
  WHERE le.organization = ${target.organization}
    AND et.code = 'SIGN_IN_CODE'
    AND le.occasion = (SELECT id FROM target_occasion)
), participant_delivery_audit AS (
  SELECT
    r.*,
    count(l.*)::integer AS send_count,
    min(l.created_at) AS first_send_at,
    max(l.created_at) AS last_send_at
  FROM roster r
  LEFT JOIN sign_in_logs l USING (user_id)
  GROUP BY r.user_id, r.name, r.surname, r.account_email, r.delivery_email,
           r.membership_created_at, r.has_legacy_invited_flag, r.last_sign_in_at
), participant_audit AS (
  SELECT
    d.*,
    min(al.created_at) AS first_login_after_send_at,
    (array_agg(al.payload->'traits'->>'provider' ORDER BY al.created_at)
      FILTER (WHERE al.id IS NOT NULL))[1] AS login_provider
  FROM participant_delivery_audit d
  LEFT JOIN auth.audit_log_entries al
    ON al.payload->>'action' = 'login'
   AND al.payload->>'actor_id' = d.user_id::text
   AND al.created_at >= d.first_send_at
  GROUP BY d.user_id, d.name, d.surname, d.account_email, d.delivery_email,
           d.membership_created_at, d.has_legacy_invited_flag, d.last_sign_in_at,
           d.send_count, d.first_send_at, d.last_send_at
), unmatched_logs AS (
  SELECT count(*)::integer AS count
  FROM sign_in_logs l WHERE l.user_id IS NULL
)
SELECT jsonb_build_object(
  'generatedAt', clock_timestamp(),
  'target', (SELECT to_jsonb(o) FROM target_occasion o),
  'summary', jsonb_build_object(
    'participants', (SELECT count(*) FROM participant_audit),
    'sent', (SELECT count(*) FROM participant_audit WHERE send_count > 0),
    'notSent', (SELECT count(*) FROM participant_audit WHERE send_count = 0),
    'sentMoreThanOnce',
      (SELECT count(*) FROM participant_audit WHERE send_count > 1),
    'signedInAfterFirstSend',
      (SELECT count(*) FROM participant_audit
       WHERE first_login_after_send_at IS NOT NULL),
    'noSignInAfterFirstSend',
      (SELECT count(*) FROM participant_audit
       WHERE send_count > 0 AND first_login_after_send_at IS NULL),
    'notSentButSignedIn',
      (SELECT count(*) FROM participant_audit
       WHERE send_count = 0 AND last_sign_in_at IS NOT NULL),
    'notSentAndNeverSignedIn',
      (SELECT count(*) FROM participant_audit
       WHERE send_count = 0 AND last_sign_in_at IS NULL),
    'legacyInvitedFlagRows',
      (SELECT count(*) FROM participant_audit WHERE has_legacy_invited_flag),
    'acceptedLogWithoutRecipient', (SELECT count FROM unmatched_logs),
    'unmatchedOrganizationLogRows', (SELECT count FROM unmatched_logs),
    'sendMultiplicity', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.send_count)
      FROM (
        SELECT send_count, count(*) AS participants
        FROM participant_audit GROUP BY send_count
      ) x
    ), '[]'::jsonb)
  ),
  'participants', COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'userId', user_id,
      'name', name,
      'surname', surname,
      'accountEmail', account_email,
      'deliveryEmail', delivery_email,
      'membershipCreatedAt', membership_created_at,
      'invited', send_count > 0,
      'sendCount', send_count,
      'firstSendAt', first_send_at,
      'lastSendAt', last_send_at,
      'lastSignInAt', last_sign_in_at,
      'firstLoginAfterSendAt', first_login_after_send_at,
      'loginProvider', login_provider,
      'signedInAfterFirstSend',
        first_login_after_send_at IS NOT NULL
    ) ORDER BY surname, name, account_email)
    FROM participant_audit
  ), '[]'::jsonb)
) AS result;`;
}

function csvCell(value) {
  if (value == null) return '';
  let text = String(value);
  if (/^[=+\-@]/.test(text)) text = `'${text}`;
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

export function participantsToCsv(participants) {
  const columns = [
    ['name', 'name'],
    ['surname', 'surname'],
    ['account_email', 'accountEmail'],
    ['delivery_email', 'deliveryEmail'],
    ['invited', 'invited'],
    ['send_count', 'sendCount'],
    ['first_send_at', 'firstSendAt'],
    ['last_send_at', 'lastSendAt'],
    ['last_sign_in_at', 'lastSignInAt'],
    ['first_login_after_send_at', 'firstLoginAfterSendAt'],
    ['login_provider', 'loginProvider'],
    ['signed_in_after_first_send', 'signedInAfterFirstSend'],
  ];
  return [
    columns.map(([header]) => header).join(','),
    ...participants.map((participant) =>
      columns.map(([, key]) => csvCell(participant[key])).join(',')),
  ].join('\n') + '\n';
}

export function invitationConsistencyFailures(summary) {
  const failures = [];
  if ((summary.acceptedLogWithoutRecipient ?? 0) > 0) {
    failures.push(`${summary.acceptedLogWithoutRecipient} accepted sends lack recipient_user`);
  }
  if ((summary.legacyInvitedFlagRows ?? 0) > 0) {
    failures.push(`${summary.legacyInvitedFlagRows} legacy is_invited flags remain`);
  }
  return failures;
}

export async function collectCsvInviteAudit(target, { query = managementQuery } = {}) {
  const rows = await query({
    projectRef: target.projectRef,
    accessToken: target.accessToken,
    query: buildCsvInviteAuditSql(target),
  });
  const report = rows[0]?.result;
  if (!report?.target || report.target.link !== target.occasionLink ||
      report.target.organization !== target.organization) {
    throw new Error('Canonical occasion is absent or does not match project config');
  }
  return report;
}

async function main() {
  const target = loadCanonicalSupabaseTarget(projectRoot);
  const report = await collectCsvInviteAudit(target);
  const outputArgument = process.argv.indexOf('--output');
  if (outputArgument >= 0) {
    const requestedPath = process.argv[outputArgument + 1];
    if (!requestedPath) throw new Error('--output requires a file path');
    const outputPath = path.resolve(projectRoot, requestedPath);
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, participantsToCsv(report.participants), {
      mode: 0o600,
    });
  }
  console.log(JSON.stringify({ target: report.target, summary: report.summary }, null, 2));
  if (process.argv.includes('--check-invitation-consistency')) {
    const failures = invitationConsistencyFailures(report.summary);
    if (failures.length > 0) {
      throw new Error(`Invitation consistency failed: ${failures.join('; ')}`);
    }
  }
}

if (process.argv[1] &&
    path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
