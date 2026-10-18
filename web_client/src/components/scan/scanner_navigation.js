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
