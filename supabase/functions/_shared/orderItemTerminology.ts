/** Occasion-level wording only. Field visibility and delivery are separate. */
export function usesTicketTerminology(features: unknown): boolean {
  return Array.isArray(features) && features.some(feature =>
    feature?.code === 'ticket' &&
    (feature.is_enabled === true || feature.isEnabled === true));
}
