import {managedConsentOrigin} from './measurement_consent_source.js';
import {measurementConsent} from './form_measurement_contract.js';

// Managed iframe imports share the local Klaro choice controller. A local save
// ends import ownership, while the existing helper still owns transport liveness.
export function createEmbedConsentSource({bridge, model, host,
    loadNotice = () => import('./form_measurement_cmp.js')}) {
    return {connect(policy, notify) {
        if (bridge.dataLayer || policy?.visitor_role === 'staff' || !managedConsentOrigin(policy, bridge.origin))
            return bridge.connectConsent(policy, notify);
        let disposed = false, noticeCleanup, transportCleanup;
        loadNotice().then(({startMeasurementConsent}) => {
            if (disposed) return;
            noticeCleanup = startMeasurementConsent({model, host,
                setConsent: value => notify(bridge.leaseId ? {...measurementConsent(value),
                    leaseId:bridge.leaseId, expiresAt:bridge.leaseUntil} : false),
                remoteSource: {connect(options) {
                    transportCleanup = bridge.connectConsent(policy, value => {
                        if (options.hasChoice()) return;
                        if (value?.leaseId) options.accept(value, value);
                        else { options.revoke(); options.settled(); }
                    });
                    // Local saves must keep renewal alive. Only this outer
                    // connection's disposer retires the helper transport.
                    return () => {};
                }},
            });
        }).catch(() => { if (!disposed) notify(null); });
        return () => { disposed = true; noticeCleanup?.(); transportCleanup?.(); };
    }};
}
