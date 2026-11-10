import {consentScope, sameConsentScope} from './measurement_consent_source.js';
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
// A linked visit owns a renewable source lease, never a persisted local choice.
export function requestLinkedConsent({win, policy, hasChoice, accept, revoke = () => {}, settled = () => {}}) {
    let timer, active = true, requested = false, connected = false, sequence = 0;
    let origin, peer, nonce, until, scope, visitUntil;
    const stop = () => {
        if (!active) return;
        active = false;
        win.removeEventListener('message', receive);
        win.removeEventListener('pagehide', disconnect);
        win.removeEventListener('pageshow', check);
        win.document.removeEventListener('visibilitychange', check);
        if (timer !== undefined) win.clearTimeout(timer);
        peers.delete(win);
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
            if (event.source !== peer || event.origin !== origin || data?.namespace !== namespace || data.protocol !== 1 ||
                data.nonce !== nonce || !sameConsentScope(scope, data.scope) ||
                !Number.isSafeInteger(data.sequence) || data.sequence <= sequence) return;
            if (hasChoice()) { stop(); return; }
            if (data.type === 'end') { disconnect(); return; }
            if (data.type !== 'response' || typeof data.choice?.analytics !== 'boolean' || typeof data.choice?.marketing !== 'boolean' ||
                !Number.isFinite(data.expiresAt) || data.expiresAt <= Date.now() || data.expiresAt > Date.now()+60000) return;
            sequence = data.sequence; connected = true;
            until = Math.min(visitUntil, data.expiresAt);
            win.clearTimeout(timer); timer = win.setTimeout(disconnect, until-Date.now());
            peers.delete(win);
            accept(data.choice, {origin, leaseId:nonce, expiresAt:until});
        } catch { disconnect(); }
    };
    Object.defineProperty(stop, 'pending', {get:() => requested && active && !connected});
    try {
        prepareConsentLink(win);
        peer = peers.get(win); scope = consentScope(policy);
        if (!scope || !isConsentLinkWindow(win) || win.parent !== win || !peer || policy.measurement_consent_bridge !== true || hasChoice()) { stop(); return stop; }
        origin = new URL(win.document.referrer).origin;
        if (!isConsentLinkOrigin(origin, isLocalConsentLink(win)) || !policy.approved_hosts?.includes(origin)) { stop(); return stop; }
        nonce = win.crypto.randomUUID(); until = Date.now() + 1500; visitUntil = Date.now()+24*60*60*1000;
        win.addEventListener('message', receive);
        win.addEventListener('pagehide', disconnect);
        win.addEventListener('pageshow', check);
        win.document.addEventListener('visibilitychange', check);
        requested = true;
        timer = win.setTimeout(disconnect, 1500);
        peer.postMessage({namespace, protocol:1, type:'request', nonce, scope}, origin);
    } catch { disconnect(); }
    return stop;
}
