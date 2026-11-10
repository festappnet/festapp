import {isConsentLinkOrigin, isLocalConsentLink} from '../components/forms/form_consent_link.js';
import {consentScope, sameConsentScope} from '../components/forms/measurement_consent_source.js';

export const consentLinkNamespace = 'festapp-consent-link';
// Only explicitly opted-in, ordinary new-tab clicks retain an opener. Keeping
// the actual WindowProxy also excludes iframe and unsolicited popup requests.
export function installHostConsentLink(win, productOrigin, source) {
    const opened = new Map();
    const click = event => {
        try {
            const link = event.target.closest('a[data-festapp-consent-link]');
            if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey ||
                link.target !== '_blank' || link.hasAttribute('download') ||  /(?:^|\s)(?:noopener|noreferrer)(?:\s|$)/i.test(link.rel) ||
                // Any explicit referrer policy (on the link or the page) keeps native
                // navigation: window.open() would not carry the link's own policy.
                link.hasAttribute('referrerpolicy') ||
                [...win.document.querySelectorAll('meta[name]')].some(meta => meta.name.toLowerCase() === 'referrer')) return;
            const url = new URL(link.href, win.document.baseURI);
            if (!isConsentLinkOrigin(url.origin, isLocalConsentLink(win)) || !isConsentLinkOrigin(win.location.origin, isLocalConsentLink(win)) || url.origin !== productOrigin || !/^\/form\/[^/]+\/?$/.test(url.pathname)) return;
            const child = win.open(url.href, `festapp-consent-link-${win.crypto.randomUUID()}`);
            if (!child) return; // Popup blocked: keep native navigation.
            for (const [old, record] of opened) if (old.closed || Date.now() >= record.until) { win.clearTimeout(record.timer); opened.delete(old); }
            opened.set(child, {until:Date.now()+60000, timer:win.setTimeout(() => opened.delete(child), 60000)});
            event.preventDefault();
        } catch { /* Links remain usable if the optional bridge fails. */ }
    };
    const sessions = new Map();
    const end = child => {
        const session = sessions.get(child);
        if (!session) return;
        sessions.delete(child);
        win.clearInterval(session.timer); session.unsubscribe?.();
        try { child.postMessage({...session.envelope, type:'end', sequence:++session.sequence}, productOrigin); } catch { /* Closed peer. */ }
    };
    const receive = event => {
        try {
            const data = event.data;
            if (event.origin !== productOrigin || event.source === win || data?.namespace !== consentLinkNamespace || data.protocol !== 1) return;
            const existing = sessions.get(event.source);
            if (existing && data.type === 'detach' && data.nonce === existing.envelope.nonce) { end(event.source); return; }
            if (!opened.has(event.source) || data.type !== 'request' ||
                typeof data.nonce !== 'string' || !/^[a-f0-9-]{36}$/.test(data.nonce)) return;
            const record = opened.get(event.source);
            win.clearTimeout(record.timer); opened.delete(event.source);
            if (Date.now() >= record.until) return;
            const scope = consentScope(data.scope);
            if (!sameConsentScope(scope, data.scope)) return;
            const child = event.source;
            const session = {sequence:0, until:Date.now()+24*60*60*1000, generation:source?.generation,
                envelope:{namespace:consentLinkNamespace, protocol:1, nonce:data.nonce, scope}};
            sessions.set(child, session);
            const send = () => {
                if (sessions.get(child) !== session) return;
                const choice = source?.generation === session.generation ? source?.read(scope) : null;
                if (child.closed || Date.now() >= session.until || !choice) { end(child); return; }
                try { child.postMessage({...session.envelope, type:'response', sequence:++session.sequence,
                    choice, expiresAt:Math.min(session.until, Date.now()+60000)}, productOrigin); }
                catch { end(child); }
            };
            session.unsubscribe = source?.subscribe(send);
            session.timer = win.setInterval(send, 20000);
            send();
        } catch { /* Consent never changes navigation or checkout. */ }
    };
    const suspend = () => {
        for (const child of [...sessions.keys()]) end(child);
        for (const record of opened.values()) win.clearTimeout(record.timer);
        opened.clear();
    };
    win.addEventListener('pagehide', suspend);
    win.document.addEventListener('click', click);
    win.addEventListener('message', receive);
    return () => { suspend(); win.removeEventListener('pagehide', suspend); win.document.removeEventListener('click', click); win.removeEventListener('message', receive); for (const record of opened.values()) win.clearTimeout(record.timer); opened.clear(); };
}
