const key = 'festapp-scanner-return';
export function safeScannerReturn(value, origin) {
    if (!value) return null;
    try {
        const url = new URL(value, origin);
        if (url.origin !== origin || /^\/(?:scan(?:\/|$)|login-qr(?:\/|$))/.test(url.pathname)) return null;
        return url.pathname + url.search + url.hash;
    } catch { return null; }
}
export function scannerReturnPath({ location, referrer = '', returnTo, storage, session, backend } = {}) {
    const url = new URL(location.href);
    // No event has been authenticated yet, including old cached session rows.
    if (!session?.occasion_id || !session?.occasion_link) return '/';
    const eventPath = '/' + encodeURIComponent(session.occasion_link);
    const belongsToEvent = value => {
        const path = safeScannerReturn(value, url.origin);
        if (!path) return null;
        const pathname = new URL(path, url.origin).pathname;
        return pathname === eventPath || pathname.startsWith(eventPath + '/') ? path : null;
    };
    const scopedKey = key + ':' + JSON.stringify([backend?.origin || url.origin, backend?.generation ?? null,
        session.organization_id, session.occasion_id]);
    let saved;
    try { saved = storage?.getItem(scopedKey); } catch {}
    const path = belongsToEvent(returnTo || url.searchParams.get('returnTo'))
        || belongsToEvent(referrer) || belongsToEvent(saved) || eventPath;
    try { storage?.setItem(scopedKey, path); } catch {}
    return path;
}

export function scannerInputHistoryState(state) {
    if(!['camera','manual'].includes(state?.scannerInput) || !['camera','workspace'].includes(state?.scannerLevel))return null;
    return {scannerInput:state.scannerInput,scannerLevel:state.scannerLevel,...(state.scannerReview===true?{scannerReview:true}:{})};
}
