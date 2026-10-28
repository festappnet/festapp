import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {prepareReporting} from '../reporting/prepare.mjs';

// Preparation only. No network, OAuth secrets, send/retry or paid operations.
// A receipt file is not an installation verifier or an authoritative fee ledger.
try {
  const [source, destination] = process.argv.slice(2);
  if (!source || !destination) throw new Error('Usage: pnpm run billing:prepare <private-fee-export.json> <new-private-output-directory>');
  const root = resolve('.private');
  const target = resolve(destination);
  if (!target.startsWith(root + '/')) throw new Error('OUTPUT_MUST_BE_INSIDE_PRIVATE_DIRECTORY');
  const report = prepareReporting(JSON.parse(await readFile(source, 'utf8')));
  await mkdir(target, {mode: 0o700}); // refuse overwrite of an existing batch
  await writeFile(resolve(target, 'report.csv'), report.csv, {mode: 0o600, flag: 'wx'});
  await writeFile(resolve(target, 'events.json'), JSON.stringify(report.events, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
  await writeFile(resolve(target, 'manifest.json'), JSON.stringify({schemaVersion: report.schemaVersion,
    period: report.period, appId: report.appId, eventCount: report.events.length, digest: report.digest,
    status: 'prepared-not-submitted'}, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
  console.log(`Prepared ${report.events.length} fee events and one CSV from the same receipts; nothing sent.`);
} catch (error) {
  console.error(error instanceof SyntaxError ? 'INVALID_JSON_INPUT' : error.message);
  process.exitCode = 1;
}
