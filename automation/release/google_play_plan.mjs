#!/usr/bin/env node

import fs from 'node:fs';

const inputPath = process.argv[2];
if (!inputPath) throw new Error('Usage: google_play_plan.mjs <requests.json>');

const requests = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
if (!Array.isArray(requests) || requests.length < 1 || requests.length > 30) {
  throw new Error('Expected 1 to 30 Google Play requests');
}

const operations = new Set([
  'app.inspect',
  'listing.update',
  'reviews.list',
  'review.reply',
  'users.inspect',
  'grant.update',
]);
const seen = new Set();
const matrix = requests.map((request) => {
  const tenant = String(request.tenant ?? '');
  const operation = String(request.operation ?? '');
  const packageName = String(request.packageName ?? '');
  const requestSha256 = String(request.requestSha256 ?? '').toLowerCase();
  if (!/^[a-z0-9][a-z0-9-]*$/.test(tenant)) throw new Error(`Invalid tenant: ${tenant}`);
  if (!operations.has(operation)) throw new Error(`Unsupported operation: ${operation}`);
  if (!/^[A-Za-z][A-Za-z0-9_.]*$/.test(packageName)) throw new Error(`Invalid package: ${packageName}`);
  if (!/^[a-f0-9]{64}$/.test(requestSha256)) throw new Error(`Invalid request SHA-256 for ${tenant}`);
  const identity = `${tenant}|${operation}|${packageName}|${requestSha256}`;
  if (seen.has(identity)) throw new Error(`Duplicate request: ${identity}`);
  seen.add(identity);
  return { tenant, operation, packageName, requestSha256 };
});

process.stdout.write(JSON.stringify({ include: matrix }));
