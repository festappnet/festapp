// Shared by marketplace readiness and report preparation. A local declaration
// is admissible only when its references identify actual approved terms.
export function billingApprovalBlockers(approval) {
  const present = value => typeof value === 'string' && Boolean(value.trim()) &&
    value.length <= 1000 && !/[\u0000-\u001f]/.test(value);
  const blockers = [];
  if (!present(approval?.reference)) blockers.push('Missing written billing approval reference');
  for (const key of ['serviceFeeOnly', 'grossTicketValueExcluded', 'externalTicketCheckoutApproved',
    'partnerBillingApproved', 'refundTreatmentConfirmed']) {
    if (approval?.[key] !== true) blockers.push(`Unconfirmed billing condition: ${key}`);
  }
  if (!present(approval?.attributionPolicyReference)) blockers.push('Missing billing attribution policy reference');
  if (!present(approval?.refundPolicyReference)) blockers.push('Missing refund policy reference');
  return blockers;
}
