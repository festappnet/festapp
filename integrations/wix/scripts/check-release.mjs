import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
export function releaseBlockers(input) {
  const blockers=[];
  if (!input || typeof input !== 'object' || Array.isArray(input)) return ['Missing release input object'];
  const uuid=value=>typeof value==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
  const https=value=>{try {const url=new URL(value);return url.protocol==='https:' && !url.username && !url.password && !url.search && !url.hash;}catch{return false;}};
  if(input.schemaVersion!==1)blockers.push('Unsupported release input schema');
  if(input.publisherFees?.upfrontAmount!==0 || input.publisherFees?.recurringAmount!==0)blockers.push('Publisher registration/listing/retention must have zero fixed upfront and recurring fees');
  if(typeof input.publisherFees?.currency!=='string' || !/^[A-Z]{3}$/.test(input.publisherFees.currency) || typeof input.publisherFees?.evidence!=='string' || !input.publisherFees.evidence.trim())blockers.push('Missing verified publisher fee terms and currency');
  for(const key of ['wixAppId','widgetExtensionId'])if(!uuid(input[key]))blockers.push(`Missing assigned Wix ${key}`);
  for(const key of ['widgetScriptUrl','settingsUrl'])if(!https(input.hosting?.[key]))blockers.push(`Missing verified HTTPS hosting ${key}`);
  if(typeof input.billingApproval?.reference!=='string' || !input.billingApproval.reference.trim())blockers.push('Missing written billing approval reference');
  for(const key of ['serviceFeeOnly','grossTicketValueExcluded','externalTicketCheckoutApproved','partnerBillingApproved','refundTreatmentConfirmed'])if(input.billingApproval?.[key]!==true)blockers.push(`Unconfirmed billing condition: ${key}`);
  for(const editor of ['Harmony','Editor','Studio'])if(typeof input.editorReceipts?.[editor]!=='string' || !input.editorReceipts[editor].trim())blockers.push(`Missing real ${editor} checkout/lifecycle receipt`);
  if(typeof input.billingImplementationReceipt!=='string' || !input.billingImplementationReceipt.trim())blockers.push('Missing approved billing/reporting implementation receipt');
  if(input.publicStoreAssetsVerified!==true)blockers.push('Store assets/test credentials/privacy/support not verified');
  return blockers;
}
if (process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const file=process.argv[2] || 'release-inputs.example.json';
  const blockers=releaseBlockers(JSON.parse(readFileSync(file,'utf8')));
  if(blockers.length) {console.error('NOT READY FOR WIX SUBMISSION\n'+blockers.map(item=>'- '+item).join('\n'));process.exitCode=1;}
  else console.log('Release input declarations complete; independently verify evidence and assigned app before public submission.');
}
