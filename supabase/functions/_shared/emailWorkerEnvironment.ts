/** Provider and bank-control credentials belong only to their authenticated workers. */
export function emailWorkerEnvironment(
  service: string,
  environment: Record<string, string>,
): Array<[string, string]> {
  const control = ['bank-sync-manage', 'bank-sync-reconcile'].includes(service);
  return Object.entries(environment).filter(([name]) => {
    if (name.startsWith('FESTAPP_MONITORING_')) return false;
    if (name.startsWith('EMAIL_SES_')) return service === 'process-email-queue';
    if (name.startsWith('BANKSYNC_CONTROL_KEY')) return control;
    if (name === 'BANKSYNC_TENANT_ADMIN_KEY') return control || service === 'fetch-transactions';
    if (name === 'BANKSYNC_WEBHOOK_SECRET') return service === 'bank-sync-webhook';
    return true;
  });
}
