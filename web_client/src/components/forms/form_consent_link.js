import {randomUuid} from '../../utils/random_uuid.js';
import {consentScope, sameConsentScope} from './measurement_consent_source.js';
import {hasCurrentPurchaseConsent, samePurchaseDecision, validMetaBrowserMatching} from './meta_purchase_consent.js';
const namespace = 'festapp-consent-link';
const peers = new WeakMap();
export const hasConsentLinkPeer = win => !!peers.get(win);
const matchingCollectors = new WeakMap();
// Checkout asks the live opener for Meta browser IDs once, like an embed host.
export const collectLinkedMetaMatching = (win, snapshot) => matchingCollectors.get(win)?.(snapshot) ?? Promise.resolve({});
export const isConsentLinkWindow = win => /^festapp-consent-link-[a-f0-9-]{36}$/.test(win.name || '');
// Capture only helper windows, before policy loading or any optional CMP work.
export function prepareConsentLink(win) {
    if (!isConsentLinkWindow(win) || peers.has(win)) return;
    peers.set(win, win.opener);
    try { win.opener = null; } catch { /* Restricted WindowProxy. */ }
}

export const isLocalConsentLink = win => win.location.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(win.location.hostname);
export function isConsentLinkOrigin(origin, local = false) {
    try {
        const url = new URL(origin);
        return url.origin === origin && (url.protocol === 'https:' ||
            (local && url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname)));
    } catch { return false; }
}
// A linked visit owns a renewable source lease, never a persisted local choice.
export function requestLinkedConsent({win, policy, hasChoice, accept, includePurchaseConsent = false, revoke = () => {}, settled = () => {}}) {
    let timer, watch, active = true, requested = false, connected = false, sequence = 0;
    let origin, peer, nonce, until, scope, visitUntil, latestChoice;
    const matching = new Map();
    const stop = () => {
        if (!active) return;
        active = false;
        win.removeEventListener('message', receive);
        win.removeEventListener('pagehide', disconnect);
        win.removeEventListener('pageshow', check);
        win.document.removeEventListener('visibilitychange', check);
        if (timer !== undefined) win.clearTimeout(timer);
        if (watch !== undefined) win.clearInterval(watch);
        peers.delete(win);
        if (matchingCollectors.get(win) === collect) matchingCollectors.delete(win);
        for (const {finish} of matching.values()) finish({});
        if (requested) {
            try { peer.postMessage({namespace, protocol:1, type:'detach', nonce}, origin); } catch { /* Closed source. */ }
            settled();
        }
    };
    const disconnect = () => { const wasConnected = connected; stop(); if (wasConnected) revoke(); };
    const check = () => { if (active && Date.now() >= until) disconnect(); };
    const receive = event => {
        const data = event.data;
        try {
            if (!active) return;
            if (Date.now() >= until) { disconnect(); return; }
            // An unloading website (reload or navigation) posts its terminal end
            // with a different source. End only revokes, so origin, nonce, scope
            // and sequence suffice for it; every grant needs the exact peer.
            if ((event.source !== peer && data?.type !== 'end') || event.origin !== origin || data?.namespace !== namespace || data.protocol !== 1 ||
                data.nonce !== nonce || !sameConsentScope(scope, data.scope) ||
                !Number.isSafeInteger(data.sequence) || data.sequence <= sequence) return;
            if (hasChoice()) { stop(); return; }
            if (data.type === 'end') { disconnect(); return; }
            if (data.type === 'matching') {
                const pending = connected && matching.get(data.requestId);
                if (pending) {
                    sequence = data.sequence;
                    pending.finish(Date.now() < pending.expiresAt && canCollect(pending.snapshot)
                        ? validMetaBrowserMatching(data.matching) : {});
                }
                return;
            }
            if (data.type !== 'response' || typeof data.choice?.analytics !== 'boolean' || typeof data.choice?.marketing !== 'boolean' ||
                !Number.isFinite(data.expiresAt) || data.expiresAt <= Date.now() || data.expiresAt > Date.now()+60000) return;
            sequence = data.sequence; connected = true;
            // A closed website tab may never deliver pagehide or its end message.
            watch ??= win.setInterval(() => { try { if (peer.closed) disconnect(); } catch { disconnect(); } }, 1000);
            until = Math.min(visitUntil, data.expiresAt);
            win.clearTimeout(timer); timer = win.setTimeout(disconnect, until-Date.now());
            peers.delete(win);
            const {purchaseConsent,...ordinary}=data.choice;
            latestChoice = {...ordinary, ...(scope.binding && purchaseConsent ? {purchaseConsent:{...purchaseConsent, binding:scope.binding, websiteOrigin:origin}} : {})};
            if (includePurchaseConsent && hasCurrentPurchaseConsent(latestChoice)) matchingCollectors.set(win, collect);
            else if (matchingCollectors.get(win) === collect) matchingCollectors.delete(win);
            for (const {snapshot,finish} of matching.values()) if (!canCollect(snapshot)) finish({});
            accept(latestChoice, {origin, leaseId:nonce, expiresAt:until});
        } catch { disconnect(); }
    };
    function canCollect(snapshot) {
        return active && connected && !hasChoice() && Date.now() < until &&
            hasCurrentPurchaseConsent(latestChoice) && samePurchaseDecision(latestChoice.purchaseConsent, snapshot);
    }
    function collect(snapshot) {
        if (!canCollect(snapshot)) return Promise.resolve({});
        const requestId = randomUuid(win.crypto);
        return new Promise(resolve => {
            const finish = value => { win.clearTimeout(timeout); matching.delete(requestId); resolve(value); };
            const timeout = win.setTimeout(() => finish({}), 400);
            matching.set(requestId, {snapshot, finish, expiresAt:Date.now()+400});
            try {
                peer.postMessage({namespace, protocol:1, type:'matching-request', nonce, scope, requestId,
                    revision:snapshot.revision, consentRevision:snapshot.consentRevision, binding:snapshot.binding}, origin);
            } catch { finish({}); }
        });
    }
    Object.defineProperty(stop, 'pending', {get:() => requested && active && !connected});
    try {
        prepareConsentLink(win);
        peer = peers.get(win);
        origin = new URL(win.document.referrer).origin;
        scope = consentScope(policy, origin);
        if (!scope || !isConsentLinkWindow(win) || win.parent !== win || !peer || policy.measurement_consent_bridge !== true || hasChoice()) { stop(); return stop; }
        origin = new URL(win.document.referrer).origin;
        if (!isConsentLinkOrigin(origin, isLocalConsentLink(win)) ||
            !(scope.binding && scope.websiteOrigin === origin) && !policy.approved_hosts?.includes(origin)) { stop(); return stop; }
        nonce = randomUuid(win.crypto); until = Date.now() + 1500; visitUntil = Date.now()+24*60*60*1000;
        win.addEventListener('message', receive);
        win.addEventListener('pagehide', disconnect);
        win.addEventListener('pageshow', check);
        win.document.addEventListener('visibilitychange', check);
        requested = true;
        timer = win.setTimeout(disconnect, 1500);
        peer.postMessage({namespace, protocol:1, type:'request', nonce, scope, ...(includePurchaseConsent ? {includePurchaseConsent:true} : {})}, origin);
    } catch { disconnect(); }
    return stop;
}
