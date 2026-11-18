// Adapt the host bridge to the session's consent-source interface. The bridge
// owns scope validation, renewal and revocation; standalone cookies never apply.
export function createEmbedConsentSource({bridge}) {
    return {connect:(policy, notify) => bridge.connectConsent(policy, notify)};
}
