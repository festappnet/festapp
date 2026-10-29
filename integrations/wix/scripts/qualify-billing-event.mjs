// No timer, reset, alternate target, money arguments or automatic retry.
import {readFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {wixBillingProvider} from '../billing/dispatcher.mjs';
import {qualificationTarget, inspectQualification, sendQualification} from '../billing/qualification.mjs';

try {
  const [command, approvalFile, ...extra] = process.argv.slice(2);
  if (extra.length || !['inspect', 'send'].includes(command) ||
    (command === 'inspect' ? Boolean(approvalFile) : !approvalFile)) {
    throw Error('Usage: node scripts/qualify-billing-event.mjs inspect | send <reviewed-wix-approval.json>');
  }
  // All worktrees share one attempt fence. Moving to another worktree cannot reset it.
  const common = execFileSync('git', ['rev-parse', '--path-format=absolute', '--git-common-dir'],
    {cwd: fileURLToPath(new URL('..', import.meta.url)), encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}).trim();
  const stateFile = join(common, `wix-bi-qualification-${qualificationTarget.instanceId}.jsonl`);
  if (command === 'inspect') console.log(JSON.stringify(await inspectQualification(stateFile)));
  else {
    if (!process.env.WIX_APP_SECRET?.trim()) throw Error('WIX_QUALIFICATION_APP_SECRET_REQUIRED');
    const approval = JSON.parse(await readFile(approvalFile, 'utf8'));
    console.log(JSON.stringify(await sendQualification({stateFile, approval,
      provider: wixBillingProvider({appSecret: process.env.WIX_APP_SECRET})})));
  }
} catch (error) {
  console.error(/^(WIX_QUALIFICATION_|Usage:)/.test(error.message) ? error.message : 'WIX_QUALIFICATION_FAILED');
  process.exitCode = 1;
}
