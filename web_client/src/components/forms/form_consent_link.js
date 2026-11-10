const namespace = 'festapp-consent-link';
const peers = new WeakMap();
export const hasConsentLinkPeer = win => !!peers.get(win);
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
// Policy approved_hosts is the public projection of the Unit's parent_origins.
export function requestLinkedConsent({win, policy, hasChoice, accept, settled = () => {}}) {
    let timer, active = true, requested = false;
    const stop = () => {
        if (!active) return;
        active = false;
        win.removeEventListener('message', receive);
        if (timer !== undefined) win.clearTimeout(timer);
        if (isConsentLinkWindow(win)) {
            peers.delete(win);
            try { win.opener = null; } catch { /* Restricted WindowProxy. */ }
        }
        if (requested) settled();
    };
    let origin, peer, nonce, until;
    const receive = event => {
        const data = event.data;
        try {
            if (!active || Date.now() >= until) { stop(); return; }
            if (event.source !== peer || event.origin !== origin || data?.namespace !== namespace || data.protocol !== 1 ||
                data.type !== 'response' || data.nonce !== nonce) return;
            if (data.choice === null) { stop(); return; }
            if (typeof data.analytics !== 'boolean' || typeof data.marketing !== 'boolean') return;
            if (hasChoice()) { stop(); return; }
            try { accept({analytics:data.analytics, marketing:data.marketing}, {origin, importedAt:Date.now(), session:true}); }
            finally { stop(); }
        } catch { stop(); /* The normal CMP remains available. */ }
    };
    try {
        prepareConsentLink(win);
        peer = peers.get(win);
        if (!isConsentLinkWindow(win) || win.parent !== win || !peer || policy.measurement_consent_bridge !== true || hasChoice()) { stop(); return stop; }
        origin = new URL(win.document.referrer).origin;
        if (!isConsentLinkOrigin(origin, isLocalConsentLink(win)) || !policy.approved_hosts?.includes(origin)) { stop(); return stop; }
        nonce = win.crypto.randomUUID();
        until = Date.now() + 1500;
        win.addEventListener('message', receive);
        requested = true;
        timer = win.setTimeout(stop, 1500);
        peer.postMessage({namespace, protocol:1, type:'request', nonce, processing_revision:policy.processing_revision,
            organization:policy.organization, unit:policy.unit}, origin);
    } catch { stop(); }
    stop.pending = requested && active;
    return stop;
}
