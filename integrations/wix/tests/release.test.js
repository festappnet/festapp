import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {releaseBlockers} from '../scripts/check-release.mjs';

test('checked-in release inputs cannot claim a fabricated registered or approved app', () => {
  const input=JSON.parse(readFileSync(new URL('../release-inputs.example.json',import.meta.url),'utf8'));
  const blockers=releaseBlockers(input);
  assert.ok(blockers.some(item=>item.includes('wixAppId')));
  assert.ok(blockers.some(item=>item.includes('grossTicketValueExcluded')));
  assert.ok(blockers.some(item=>item.includes('Harmony')));
});
