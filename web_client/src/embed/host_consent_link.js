import {randomUuid} from '../utils/random_uuid.js';
import {isConsentLinkOrigin, isLocalConsentLink} from '../components/forms/form_consent_link.js';
import {consentScope, sameConsentBinding, sameConsentScope} from '../components/forms/measurement_consent_source.js';
import {hasCurrentPurchaseConsent, metaBrowserMatching} from '../components/forms/meta_purchase_consent.js';
import {openConsentCheckoutDialog} from './host_consent_dialog.js';

export const consentLinkNamespace = 'festapp-consent-link';

function focusLinkedFrame(win, frame, url) {
    if (!frame?.matches('iframe[data-festapp-embed][src]:not([srcdoc], [sandbox])') ||
        frame.closest('[inert], [hidden]') ||
        win.getComputedStyle(frame).visibility !== 'visible' ||
        frame.checkVisibility?.({checkOpacity: true, checkVisibilityCSS: true}) === false) return false;
    const {width, height} = frame.getBoundingClientRect();
    if (!width || !height) return false;

    let embedded;
    try {
        embedded = new URL(frame.src);
    } catch {
        return false;
    }
    const modes = embedded.searchParams.getAll('embed');
    if (modes.length !== 1 || modes[0] !== '1') return false;
    embedded.searchParams.delete('embed');
    const target = new URL(url);
    target.search = target.searchParams.toString();
    if (embedded.href !== target.href) return false;

    frame.focus({preventScroll: true});
    frame.scrollIntoView({block: 'start', behavior: 'instant'});
    return true;
}

function focusLinkedEmbed(win, link, url) {
    const id = link.getAttribute('data-festapp-consent-link-embed');
    return Boolean(id && focusLinkedFrame(win, win.document.getElementById(id), url));
}

function suspendsOpener(win) {
    const agent = win.navigator.userAgent;
    // Messenger on Android can identify itself as FB4A. Its new visible page
    // has an opener object, but the previous page immediately receives pagehide.
    return /\bAndroid\b/i.test(agent) && /[\[;](?:FB_IAB\/(?:FB4A|MESSENGER)|FBAN\/Orca-Android)(?=[;\]])/i.test(agent);
}

// Only explicitly opted-in, ordinary new-tab clicks retain an opener. Keeping
// the actual WindowProxy also excludes iframe and unsolicited popup requests.
// Standalone links require an actual scoped CMP record; GCM defaults and updates
// alone do not establish a saved decision or its coverage.
// The data-festapp-consent-link marker is the explicit opt-in. A bare noopener
// is not an opt-out: browsers imply it for target=_blank and CMS/SEO plugins
// (e.g. Rank Math) inject it into every external link. Opting out means
// removing the marker; noreferrer and referrer policies still keep native
// navigation because the child needs the referrer to identify its source.
export function installHostConsentLink(win, productOrigin, source) {
    const opened = new Map();
    const click = event => {
        try {
            const link = event.target.closest('a[data-festapp-consent-link]');
            if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey ||
                link.target !== '_blank' || link.hasAttribute('download') ||  /(?:^|\s)noreferrer(?:\s|$)/i.test(link.rel) ||
                // Any explicit referrer policy (on the link or the page) keeps native
                // navigation: window.open() would not carry the link's own policy.
                link.hasAttribute('referrerpolicy') ||
                [...win.document.querySelectorAll('meta[name]')].some(meta => meta.name.toLowerCase() === 'referrer')) return;
            const url = new URL(link.href, win.document.baseURI);
            if (!isConsentLinkOrigin(url.origin, isLocalConsentLink(win)) || !isConsentLinkOrigin(win.location.origin, isLocalConsentLink(win)) || url.origin !== productOrigin || !/^\/form\/[^/]+\/?$/.test(url.pathname)) return;
            if (!url.searchParams.has('embed') && focusLinkedEmbed(win, link, url)) {
                event.preventDefault();
                return;
            }
            if (!url.searchParams.has('embed') && source?.configured && suspendsOpener(win) &&
                ([...win.document.querySelectorAll('iframe[data-festapp-embed]')].some(frame => focusLinkedFrame(win, frame, url)) ||
                    openConsentCheckoutDialog(win, link, url))) {
                event.preventDefault();
                return;
            }
            const child = win.open(url.href, `festapp-consent-link-${randomUuid(win.crypto)}`);
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
            if (existing && data.type === 'matching-request' && data.nonce === existing.envelope.nonce) {
                // Same checks as an embed host: live session, current saved advertising
                // decision for this binding and revision, read only at checkout.
                const {scope} = existing.envelope;
                if (!existing.includePurchaseConsent || !scope.binding || Date.now() >= existing.until ||
                    source?.generation !== existing.generation || typeof data.requestId !== 'string' ||
                    !/^[a-f0-9-]{36}$/.test(data.requestId) || !/^[0-9a-f]{32}$/.test(data.revision || '') ||
                    !sameConsentBinding(scope.binding, data.binding)) return;
                const choice = source?.read({...scope, includePurchaseConsent:true});
                const decision = choice?.purchaseConsent ? {...choice.purchaseConsent, binding:scope.binding, websiteOrigin:win.location.origin} : null;
                if (!hasCurrentPurchaseConsent({purchaseConsent:decision}) || decision.consentRevision !== data.consentRevision) return;
                event.source.postMessage({...existing.envelope, type:'matching', sequence:++existing.sequence,
                    requestId:data.requestId, matching:metaBrowserMatching(decision, win)}, productOrigin);
                return;
            }
            if (!opened.has(event.source) || data.type !== 'request' ||
                typeof data.nonce !== 'string' || !/^[a-f0-9-]{36}$/.test(data.nonce)) return;
            const record = opened.get(event.source);
            win.clearTimeout(record.timer); opened.delete(event.source);
            if (Date.now() >= record.until) return;
            const scope = consentScope(data.scope);
            if (!sameConsentScope(scope, data.scope)) return;
            const includePurchaseConsent = data.includePurchaseConsent === true;
            const child = event.source;
            const session = {sequence:0, until:Date.now()+24*60*60*1000, generation:source?.generation, includePurchaseConsent,
                envelope:{namespace:consentLinkNamespace, protocol:1, nonce:data.nonce, scope}};
            sessions.set(child, session);
            const send = () => {
                if (sessions.get(child) !== session) return;
                const choice = source?.generation === session.generation ? source?.read({...scope,includePurchaseConsent}) : null;
                if (child.closed || Date.now() >= session.until || !choice || (!includePurchaseConsent && choice.ordinaryValid === false)) { end(child); return; }
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
