import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {releaseBlockers} from '../scripts/check-release.mjs';
import {billingApprovalBlockers} from '../billing/approval.mjs';

test('checked-in release inputs cannot claim a fabricated registered or approved app', () => {
  const input=JSON.parse(readFileSync(new URL('../release-inputs.example.json',import.meta.url),'utf8'));
  const blockers=releaseBlockers(input);
  assert.ok(blockers.some(item=>item.includes('wixAppId')));
  assert.ok(blockers.some(item=>item.includes('grossTicketValueExcluded')));
  assert.ok(blockers.some(item=>item.includes('Harmony')));
});

test('fixed publisher charges cannot be hidden behind free installation or sales commissions', () => {
  const input=JSON.parse(readFileSync(new URL('../release-inputs.example.json',import.meta.url),'utf8'));
  input.publisherFees={upfrontAmount:0,recurringAmount:0,currency:'USD',evidence:'Confirmed terms receipt'};
  const feeBlockers=value=>releaseBlockers(value).filter(item=>/fee|currency/.test(item));
  assert.deepEqual(feeBlockers(input),[]);
  for (const field of ['upfrontAmount','recurringAmount']) {
    for (const value of [1,-1,'0',null]) {
      assert.ok(feeBlockers({...input,publisherFees:{...input.publisherFees,[field]:value}}).length);
    }
  }
  assert.ok(feeBlockers({...input,publisherFees:{...input.publisherFees,evidence:' '}}).length);
  assert.deepEqual(releaseBlockers(null),['Missing release input object']);
});

test('submission uses the same commercial approval gate as report preparation', () => {
  const input=JSON.parse(readFileSync(new URL('../release-inputs.example.json',import.meta.url),'utf8'));
  const approval={reference:'Wix approved amended terms',serviceFeeOnly:true,grossTicketValueExcluded:true,
    externalTicketCheckoutApproved:true,partnerBillingApproved:true,refundTreatmentConfirmed:true,
    attributionPolicyReference:'Approved app-instance mapping',refundPolicyReference:'Approved refund treatment'};
  assert.deepEqual(billingApprovalBlockers(approval),[]);
  for (const field of ['attributionPolicyReference','refundPolicyReference','grossTicketValueExcluded']) {
    const changed={...approval,[field]:null};
    const expected=billingApprovalBlockers(changed);
    assert.ok(expected.length);
    for(const blocker of expected)assert.ok(releaseBlockers({...input,billingApproval:changed}).includes(blocker));
  }
});
