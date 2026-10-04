import { assertEquals, assertRejects } from 'https://deno.land/std@0.177.0/testing/asserts.ts';
import { openBankSyncToken, sealBankSyncToken } from './bankSyncToken.ts';
Deno.test('control credentials are encrypted, versioned, and bound to their operation intent', async () => {
  Deno.env.set('BANKSYNC_CONTROL_KEY_VERSION','1');
  Deno.env.set('BANKSYNC_CONTROL_KEY_1',btoa('a'.repeat(32)));
  try {
    const cipher = await sealBankSyncToken('fixture-token','operation-a','digest-a');
    assertEquals(JSON.stringify(cipher).includes('fixture-token'),false);
    assertEquals(await openBankSyncToken(cipher,'operation-a','digest-a'),'fixture-token');
    await assertRejects(()=>openBankSyncToken(cipher,'operation-b','digest-a'));
    await assertRejects(()=>openBankSyncToken(cipher,'operation-a','digest-b'));
    Deno.env.set('BANKSYNC_CONTROL_KEY_VERSION','2');
    Deno.env.set('BANKSYNC_CONTROL_KEY_2',btoa('b'.repeat(32)));
    assertEquals(await openBankSyncToken(cipher,'operation-a','digest-a'),'fixture-token');
  } finally {
    for (const name of ['BANKSYNC_CONTROL_KEY_VERSION','BANKSYNC_CONTROL_KEY_1','BANKSYNC_CONTROL_KEY_2']) Deno.env.delete(name);
  }
});
