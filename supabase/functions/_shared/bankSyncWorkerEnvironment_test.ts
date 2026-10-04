import {assertEquals} from 'https://deno.land/std@0.177.0/testing/asserts.ts';
import {emailWorkerEnvironment} from './emailWorkerEnvironment.ts';
Deno.test('bank consumer credentials and recovery keys are confined to their owning workers',()=>{
  const input={PUBLIC:'yes',EMAIL_SES_SECRET:'ses',BANKSYNC_CONTROL_KEY_VERSION:'1',BANKSYNC_CONTROL_KEY_1:'cipher-key',
    BANKSYNC_TENANT_ADMIN_KEY:'tenant',BANKSYNC_WEBHOOK_SECRET:'signature'};
  for(const service of ['bank-sync-manage','bank-sync-reconcile','fetch-transactions','bank-sync-webhook','process-email-queue','send-tickets']) {
    const output=Object.fromEntries(emailWorkerEnvironment(service,input));
    assertEquals('EMAIL_SES_SECRET' in output,service==='process-email-queue');
    assertEquals('BANKSYNC_CONTROL_KEY_1' in output,['bank-sync-manage','bank-sync-reconcile'].includes(service));
    assertEquals('BANKSYNC_CONTROL_KEY_VERSION' in output,['bank-sync-manage','bank-sync-reconcile'].includes(service));
    assertEquals('BANKSYNC_TENANT_ADMIN_KEY' in output,['bank-sync-manage','bank-sync-reconcile','fetch-transactions'].includes(service));
    assertEquals('BANKSYNC_WEBHOOK_SECRET' in output,service==='bank-sync-webhook');
    assertEquals(output.PUBLIC,'yes');
  }
});
