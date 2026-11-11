// Simulated public Complianz API boundary. Cookie prefix, category writes and
// event ordering model the upstream opt-in implementation; this is not a live CMP.
export const consentRevision = 'a'.repeat(32);
export const complianzConfig = {provider:'complianz', organization:1, unit:2, consentRevision, policyId:'42'};
export function complianzFixture(win, {prefix = 'cmplz_', choice = null, cookiePath = '/'} = {}) {
    win.complianz = {consenttype:'optin', current_policy_id:'42', prefix};
    win.cmplz_get_cookie = name => {
        const key = win.complianz.prefix + name + '=';
        return win.document.cookie.split(';').map(s => s.trim()).find(s => s.startsWith(key))?.slice(key.length) ?? '';
    };
    win.cmplz_get_banner_status = () => win.cmplz_get_cookie('banner-status');
    win.cmplz_has_consent = category => win.cmplz_get_cookie(category) === 'allow';
    const cookie = (name, value) => { win.document.cookie = win.complianz.prefix + name + '=' + value + ';path=' + cookiePath; };
    const event = name => win.document.dispatchEvent(new win.CustomEvent(name));
    const choose = value => {
        if (value === null) {
            for (const key of ['statistics', 'marketing', 'policy_id']) cookie(key, ';max-age=0');
            cookie('banner-status', 'show');
        } else {
            // Decline dismisses before writes; hooks may observe intermediate values.
            cookie('banner-status', 'dismissed'); event('cmplz_banner_status');
            cookie('policy_id', win.complianz.current_policy_id);
            for (const [purpose, category] of [['analytics','statistics'], ['marketing','marketing']]) {
                if (value[purpose] !== undefined) cookie(category, value[purpose] ? 'allow' : 'deny');
                event('cmplz_status_change');
            }
        }
        event('cmplz_fire_categories');
    };
    // Initial restored values precede consumers, just as on a later website page.
    choose(choice);
    return {choose, cookie, event};
}
