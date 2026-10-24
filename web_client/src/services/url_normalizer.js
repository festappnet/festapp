// Pure shared path normalization for application routing and the landing entry.
export function normalizeUrl(url, compatibleUrls = []) {
        let path = url;

        // Absolute URLs can come from any valid deployment origin, including
        // Cloudflare preview domains. Routing depends on their path, never on
        // whether the origin happens to be listed in compatibleUrls.
        try {
            const uri = new URL(url);
            path = `${uri.pathname}${uri.search}${uri.hash}`;
        } catch (_) {
            // Relative and legacy malformed paths are normalized below.
        }

        // Handle malformed paths e.g. /https://domain.com/path
        if (path.match(/^\/https?:/)) {
             const matchedBaseInternal = compatibleUrls.find(u => u && path.includes(u));
             if (matchedBaseInternal) {
                 const index = path.indexOf(matchedBaseInternal);
                 path = path.substring(index + matchedBaseInternal.length);
             }
        }

        // 2. Identify and Extract Legacy Hash /#/ regardless of preceding query params
        // Example: /?fbclid=123/#/form/slug  -> should extract /form/slug

        // Strategy: First split by # to isolate potential legacy hash
        const parts = path.split('#');
        if (parts.length > 1) {
            // Check if the part after # starts with / (Legacy Hash pattern)
            // or if it's the specific pattern we support
            const fragment = parts[1];
            if (fragment.startsWith('/')) {
                path = fragment; // Take the hash path as the new root
            } else {
                 // It's a normal fragment (e.g. #section), so we just want the path part before it.
                 // BUT wait, if we had /path#section, we want /path.
                 // If we had /?query#section, we want / (and query stripped later).
                 path = parts[0];
            }
        }

        // 2.5 Strip Query Parameters (Strict Sanitization)
        // Now that we've potentially re-rooted to the hash path, strip queries from it.
        // Also strip queries from the original path if we didn't re-root (e.g. /path?q=1)
        path = path.split('?')[0];

        // 3. Ensure leading slash
        if (!path.startsWith('/')) {
            path = '/' + path;
        }

        return path;
}

// Accept only same-origin absolute paths. Ordinary marketing anchors stay put.
export function legacyHashTarget(href, compatibleUrls = []) {
    const url = new URL(href);
    if (!url.hash.startsWith('#/') || url.hash.startsWith('#//') || /[\\]/.test(url.hash)) return null;
    const fragment = url.hash.slice(1);
    const target = new URL(fragment, url.origin);
    if (target.origin !== url.origin) return null;
    const path = normalizeUrl(href, compatibleUrls);
    if (!path.startsWith('/') || path.startsWith('//') || path.includes(':')) return null;
    return path + target.search;
}
