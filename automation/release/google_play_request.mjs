#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';

const [inputPath, outputPath] = process.argv.slice(2);
if (!inputPath || !outputPath) {
  throw new Error('Usage: google_play_request.mjs <input.json> <protected-output.json>');
}

const stable = (value) => {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
};
const encode = (value) => JSON.stringify(stable(value));
const hash = (value) => crypto.createHash('sha256').update(value).digest('hex');

const request = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
const operation = String(request.operation ?? '');
const packageName = String(request.packageName ?? '');
if (!/^[A-Za-z][A-Za-z0-9_.]*$/.test(packageName)) throw new Error('Invalid packageName');

if (operation === 'listing.update') {
  const language = String(request.language ?? '');
  if (!language) throw new Error('listing.update requires language');
  const listing = Object.fromEntries(
    ['title', 'shortDescription', 'fullDescription', 'video']
      .filter((key) => Object.hasOwn(request.listing ?? {}, key))
      .map((key) => [key, request.listing[key]]),
  );
  if (Object.keys(listing).length === 0) throw new Error('listing.update requires at least one listing field');
  request.confirmation = `listing.update|${packageName}|${language}|${hash(encode(listing))}`;
} else if (operation === 'review.reply') {
  const reviewId = String(request.reviewId ?? '');
  const replyText = String(request.replyText ?? '');
  if (!reviewId || !replyText) throw new Error('review.reply requires reviewId and replyText');
  request.confirmation = `review.reply|${packageName}|${reviewId}|${hash(encode({ replyText }))}`;
} else if (operation === 'grant.update') {
  const developerId = String(request.developerId ?? '');
  const email = String(request.email ?? '');
  const appLevelPermissions = [...new Set(request.appLevelPermissions ?? [])].map(String).sort();
  if (!developerId || !email || appLevelPermissions.length === 0) throw new Error('grant.update requires developerId, email and permissions');
  request.appLevelPermissions = appLevelPermissions;
  request.confirmation = `grant.update|${developerId}|${email}|${packageName}|${hash(encode({ appLevelPermissions }))}`;
} else if (!['app.inspect', 'reviews.list', 'users.inspect'].includes(operation)) {
  throw new Error(`Unsupported operation: ${operation}`);
}

const bytes = encode(request);
fs.writeFileSync(outputPath, bytes, { mode: 0o600 });
console.log(JSON.stringify({ operation, packageName, requestSha256: hash(bytes) }));
