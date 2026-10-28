// Operator/server process only. Credentials are injected by the protected
// backend runtime environment, never command arguments, browser code or files.
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import registration from '../wix-app.json' with {type:'json'};
import {prepareReporting} from '../reporting/prepare.mjs';
import {stageBillingReport, dispatchBillingReceipt, rpcBillingJournal, wixBillingProvider} from '../billing/dispatcher.mjs';

try {
  const [command, ...args] = process.argv.slice(2);
  const endpoint = new URL(process.env.SUPABASE_URL), key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key || (endpoint.protocol !== 'https:' && !['127.0.0.1', 'localhost'].includes(endpoint.hostname)) ||
    endpoint.pathname !== '/' || endpoint.username || endpoint.password || endpoint.search || endpoint.hash) throw Error('INVALID_SERVER_RUNTIME');
  const rpc = async (name, input) => {
    const response = await fetch(new URL(`/rest/v1/rpc/${name}`, endpoint), {method:'POST',
      headers:{apikey:key, Authorization:`Bearer ${key}`, 'Content-Type':'application/json'},
      body:JSON.stringify(input), redirect:'error', signal:AbortSignal.timeout(15000)});
    if (!response.ok) throw Error(`BILLING_RPC_FAILED_${response.status}`);
    return response.status === 204 ? null : response.json();
  };
  const app = registration.appId, journal = rpcBillingJournal(rpc);
  const [receipt, kind] = args;
  let result;
  if (command === 'inspect' && args.length === 2) {
    const row = await rpc('inspect_wix_billing_delivery', {p_app:app,p_receipt:receipt,p_kind:kind});
    result = {state:row.state,attemptId:row.attempt_id,digest:row.payload_digest,attemptCount:row.attempts.length};
  } else if (command === 'dispatch' && args.length === 2) {
    result = await dispatchBillingReceipt({journal,provider:wixBillingProvider({appSecret:process.env.WIX_APP_SECRET}),receiptId:receipt,kind});
  } else if (command === 'reconcile' && args.length === 7) {
    const [receipt,kind,attempt,digest,resolution,evidence,operator] = args;
    result = await rpc('reconcile_wix_billing_delivery', {p_app:app,p_receipt:receipt,p_kind:kind,p_attempt:attempt,
      p_digest:digest,p_resolution:resolution,p_evidence_reference:evidence,p_operator_reference:operator});
  } else if (command === 'export' || command === 'stage') {
    // Export only from the canonical database, with actual approved terms.
    // The approval file contains references/conditions, never payment amounts.
    const [organization,period,approvalFile,destination] = args;
    if (args.length !== (command === 'export' ? 4 : 3) || !/^[1-9]\d*$/.test(organization || '')) throw Error('INVALID_EXPORT_ARGUMENTS');
    const {readFile} = await import('node:fs/promises');
    const agreement = JSON.parse(await readFile(approvalFile,'utf8'));
    const receipts = await rpc('export_wix_service_fee_receipts', {p_organization:organization,p_partner_terms:agreement.reference});
    const input = {schemaVersion:1,period,agreement,receipts};
    const report = prepareReporting(input);
    if (command === 'stage') result = await stageBillingReport(input,journal);
    else {
      const target = resolve(destination), root = resolve('.private');
      if (!target.startsWith(root + '/')) throw Error('OUTPUT_MUST_BE_INSIDE_PRIVATE_DIRECTORY');
      await writeFile(target,JSON.stringify(input,null,2)+'\n',{mode:0o600,flag:'wx'});
      result = {status:'exported-not-submitted',count:report.events.length,digest:report.digest};
    }
  } else throw Error('Usage: billing:operations export <organization> <YYYY-MM> <approval.json> <.private/output.json> | stage <organization> <YYYY-MM> <approval.json> | dispatch/inspect <receipt> <CHARGE|REFUND> | reconcile <receipt> <kind> <attempt> <digest> <accepted|proven-not-accepted> <provider-evidence-reference> <operator-reference>');
  console.log(JSON.stringify(result));
} catch (error) {
  // Network/parsing exceptions can include credentials or private body content.
  console.error(/^(BILLING_RPC_FAILED_|INVALID_|OUTPUT_|Usage:|WIX_|UNAPPROVED_|NO_FEE_)/.test(error.message) ? error.message : 'BILLING_OPERATION_FAILED');
  process.exitCode = 1;
}
