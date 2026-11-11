const key = 'festapp-scanner-return';
export function safeScannerReturn(value, origin) {
    if (!value) return null;
    try {
        const url = new URL(value, origin);
        if (url.origin !== origin || /^\/(?:scan(?:\/|$)|login-qr(?:\/|$))/.test(url.pathname)) return null;
        return url.pathname + url.search + url.hash;
    } catch { return null; }
}
export function scannerReturnPath({ location, referrer = '', returnTo, storage } = {}) {
    const url = new URL(location.href);
    let saved;
    try { saved = storage?.getItem(key); } catch {}
    const path = safeScannerReturn(returnTo || url.searchParams.get('returnTo'), url.origin)
        || safeScannerReturn(referrer, url.origin)
        || safeScannerReturn(saved, url.origin) || '/';
    try { storage?.setItem(key, path); } catch {}
    return path;
}

// Only scanner-owned presentation metadata may survive route normalization.
export function scannerInputHistoryState(state) {
    if(!['camera','manual'].includes(state?.scannerInput) || !['camera','workspace'].includes(state?.scannerLevel))return null;
    return {scannerInput:state.scannerInput,scannerLevel:state.scannerLevel,...(state.scannerReview===true?{scannerReview:true}:{})};
}
