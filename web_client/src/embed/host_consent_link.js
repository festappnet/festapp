import {isConsentLinkOrigin, isLocalConsentLink} from '../components/forms/form_consent_link.js';
import {readHostConsentMode} from './host_consent_mode.js';

export const consentLinkNamespace = 'festapp-consent-link';
// Only explicitly opted-in, ordinary new-tab clicks retain an opener. Keeping
// the actual WindowProxy also excludes iframe and unsolicited popup requests.
export function installHostConsentLink(win, productOrigin) {
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
            for (const [old, timer] of opened) if (old.closed) { win.clearTimeout(timer); opened.delete(old); }
            opened.set(child, win.setTimeout(() => opened.delete(child), 60000));
            event.preventDefault();
        } catch { /* Links remain usable if the optional bridge fails. */ }
    };
    const receive = event => {
        try {
            const data = event.data;
            if (event.origin !== productOrigin || event.source === win || !opened.has(event.source) ||
                data?.namespace !== consentLinkNamespace || data.protocol !== 1 || data.type !== 'request' ||
                typeof data.nonce !== 'string' || !/^[a-f0-9-]{36}$/.test(data.nonce)) return;
            win.clearTimeout(opened.get(event.source));
            opened.delete(event.source);
            const choice = readHostConsentMode(win, {unknownAsNull:true});
            if (!choice) {
                event.source.postMessage({namespace:consentLinkNamespace, protocol:1, type:'response', nonce:data.nonce, choice:null}, event.origin);
                return;
            }
            event.source.postMessage({namespace:consentLinkNamespace, protocol:1, type:'response', nonce:data.nonce,
                analytics:choice.analytics, marketing:choice.marketing}, event.origin);
        } catch { /* Consent never changes navigation or checkout. */ }
    };
    win.document.addEventListener('click', click);
    win.addEventListener('message', receive);
    return () => { win.document.removeEventListener('click', click); win.removeEventListener('message', receive); for (const timer of opened.values()) win.clearTimeout(timer); opened.clear(); };
}
