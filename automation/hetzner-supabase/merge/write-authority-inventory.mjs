#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { assertNewEvidencePaths, assertPrivateOutput, REPOSITORY_ROOT, sha256, stableJson } from './lib.mjs';

const INCLUDED_ROOTS = ['lib', 'web_client/src', 'web_client/scripts', 'supabase/functions', 'database', 'automation', 'workers'];
const EXTENSIONS = new Set(['.dart', '.js', '.mjs', '.ts', '.sql', '.sh', '.rb', '.py']);
const SKIP_NAMES = new Set(['node_modules', '.dart_tool', 'build', '.git', 'fixtures', 'test', 'tests']);
const SKIP_FILES = new Set([
  'automation/hetzner-supabase/merge/write-authority-inventory.mjs',
]);

const CONTROL_BY_LANE = Object.freeze({
  application: 'maintenance-mode-and-source-database-role-revocation',
  'auth-refresh': 'source-auth-refresh-deny-and-active-session-drain',
  cron: 'unschedule-and-drain-running-jobs',
  'edge-functions': 'disable-source-functions-and-revoke-service-role',
  manual: 'operator-lock-and-revoke-source-operator-credentials',
  storage: 'deny-source-storage-mutations-and-drain-uploads',
  webhooks: 'block-ingress-and-pause-provider-callback-delivery',
});

export function scanWriteSignals(text) {
  const signals = new Set();
  const patterns = [
    ['direct-dml', /(?:\b\w*supabase\w*|\badmin|\bclient)\s*\.from\s*\([\s\S]{0,160}?\)\s*\.(?:insert|update|upsert|delete)\s*\(/gi],
    ['rpc', /\.rpc\s*\(/g],
    ['storage-mutation', /\.storage\s*\.from\s*\([\s\S]{0,160}?\)[\s\S]{0,160}?\.(?:upload|uploadBinary|update|move|copy|remove)\s*\(/g],
    ['object-storage-mutation', /\b(?:R2Bucket|bucket|env\.[A-Z0-9_]+)\s*\.\s*(?:put|delete)\s*\(/g],
    ['auth-mutation', /\.auth(?:\.admin)?\s*\.\s*(?:signUp|signInWithPassword|signInWithOtp|exchangeCodeForSession|refreshSession|resetPasswordForEmail|updateUser|deleteUser|inviteUserByEmail|generateLink|signOut)\s*\(/g],
    ['sql-cron', /cron\.schedule\s*\(/gi],
    ['database-webhook', /net\.http_post\s*\(/gi],
    ['direct-sql-client', /\b(?:psql|managementQuery)\b/g],
    ['deployment-mutation', /\b(?:supabase\s+(?:db\s+(?:push|reset)|functions\s+deploy)|wrangler\s+deploy|terraform\s+apply)\b/g],
    ['email-side-effect', /(?:\b(?:deliverEmail|sendEmail|send_email|sendTickets|send_tickets|sendMail)\s*\(|nodemailer\.|resend\.emails|smtpClient)/g],
    ['bank-api-side-effect', /https:\/\/fioapi\.fio\.cz/g],
    ['invoicing-side-effect', /https:\/\/app\.fakturoid\.cz/gi],
    ['provider-callback', /(?:SNS_TYPE_(?:NOTIFICATION|CONFIRMATION)|SubscriptionConfirmation)/g],
    ['payment-side-effect', /(?:\b(?:stripe|gopay|comgate)\s*\.|payment_intent|\bcharge\s*\()/gi],
    ['push-side-effect', /(?:https:\/\/(?:api\.)?onesignal\.com|\bOneSignal\.|\bsendPush\s*\(|push_notification)/gi],
  ];
  for (const [name, pattern] of patterns) if (pattern.test(text)) signals.add(name);
  return [...signals].sort();
}

function filesUnder(root) {
  const values = [];
  if (!fs.existsSync(root)) return values;
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (SKIP_NAMES.has(entry.name)) continue;
    const absolute = path.join(root, entry.name);
    if (entry.isDirectory()) values.push(...filesUnder(absolute));
    else if (EXTENSIONS.has(path.extname(entry.name))) values.push(absolute);
  }
  return values;
}

export function classifyWriteEntry(relativePath, signals) {
  const lanes = new Set();
  let writeOwner = null;

  if (relativePath.startsWith('lib/') || relativePath.startsWith('web_client/src/')) {
    lanes.add('application');
    writeOwner = relativePath.startsWith('lib/') ? 'flutter-client' : 'web-client';
  } else if (relativePath.startsWith('supabase/functions/')) {
    lanes.add('edge-functions');
    writeOwner = 'supabase-edge-runtime';
  } else if (relativePath.startsWith('workers/')) {
    lanes.add('webhooks');
    writeOwner = 'cloudflare-worker-runtime';
  } else if (relativePath.startsWith('automation/') ||
      relativePath.startsWith('web_client/scripts/')) {
    lanes.add('manual');
    writeOwner = 'release-or-cutover-operator';
  } else if (relativePath.startsWith('database/')) {
    writeOwner = 'postgres-runtime';
  }

  if (signals.includes('auth-mutation')) lanes.add('auth-refresh');
  if (signals.includes('sql-cron')) lanes.add('cron');
  if (signals.includes('database-webhook')) lanes.add('webhooks');
  if (signals.includes('storage-mutation') || signals.includes('object-storage-mutation')) {
    lanes.add('storage');
  }
  if (signals.includes('edge-function-entrypoint')) lanes.add('edge-functions');
  if (signals.includes('worker-entrypoint')) lanes.add('webhooks');

  const freezeLanes = [...lanes].sort();
  const complete = writeOwner !== null && freezeLanes.length > 0 &&
    freezeLanes.every((lane) => CONTROL_BY_LANE[lane]);
  return {
    write_owner: writeOwner,
    freeze_lanes: freezeLanes,
    required_controls: freezeLanes.map((lane) => CONTROL_BY_LANE[lane]),
    status: complete ? 'classified' : 'unreviewed',
  };
}

export function buildWriteInventory(root = REPOSITORY_ROOT) {
  const entries = [];
  for (const relativeRoot of INCLUDED_ROOTS) {
    for (const filePath of filesUnder(path.join(root, relativeRoot))) {
      const text = fs.readFileSync(filePath, 'utf8');
      const relativePath = path.relative(root, filePath);
      if (SKIP_FILES.has(relativePath)) continue;
      const signals = scanWriteSignals(text);
      if (/^supabase\/functions\/[^/]+\/index\.ts$/.test(relativePath)) {
        signals.push('edge-function-entrypoint');
      }
      if (/^workers\/[^/]+\/src\/(?:index|worker)\.ts$/.test(relativePath)) {
        signals.push('worker-entrypoint');
      }
      signals.sort();
      if (signals.length === 0) continue;
      const classification = classifyWriteEntry(relativePath, signals);
      entries.push({
        path: relativePath,
        signals,
        ...classification,
        cutover_mode: 'full-freeze',
      });
    }
  }
  entries.sort((left, right) => left.path.localeCompare(right.path));
  const counts = {};
  for (const entry of entries) for (const signal of entry.signals) counts[signal] = (counts[signal] ?? 0) + 1;
  const unreviewed = entries.filter((entry) => entry.status !== 'classified');
  const laneCounts = {};
  for (const entry of entries) for (const lane of entry.freeze_lanes) {
    laneCounts[lane] = (laneCounts[lane] ?? 0) + 1;
  }
  return {
    inventory_version: 1,
    roots: INCLUDED_ROOTS,
    entries,
    counts,
    freeze_lane_counts: laneCounts,
    validation: {
      status: entries.length > 0 && unreviewed.length === 0 ? 'pass' : 'blocked',
      inventory_status: entries.length > 0 && unreviewed.length === 0 ? 'complete' : 'incomplete',
      unreviewed: unreviewed.length,
      unknown_writers: unreviewed.length,
      direct_dml_candidates: entries.filter((entry) => entry.signals.includes('direct-dml')).length,
      notes: [
        'regex discovery is a reachability candidate list, not proof of complete runtime traffic',
        'production branches, deployed versions, provider callbacks and manual operator paths require separate reconciliation',
        'classification defines required full-freeze controls; live evidence must prove those controls active before snapshot acquisition',
      ],
    },
  };
}

async function main() {
  const outputIndex = process.argv.indexOf('--output');
  if (outputIndex < 0 || !process.argv[outputIndex + 1]) {
    throw new Error('usage: write-authority-inventory.mjs --output /private/path/write-authority.json');
  }
  const output = assertPrivateOutput(process.argv[outputIndex + 1]);
  assertNewEvidencePaths([output]);
  const inventory = buildWriteInventory();
  inventory.generated_at = new Date().toISOString();
  inventory.inventory_sha256 = sha256(stableJson(inventory));
  fs.mkdirSync(path.dirname(output), { recursive: true, mode: 0o700 });
  fs.writeFileSync(output, `${JSON.stringify(inventory, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
  process.stdout.write(`write authority inventory: entries=${inventory.entries.length}, unreviewed=${inventory.validation.unreviewed}, sha256=${inventory.inventory_sha256}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
