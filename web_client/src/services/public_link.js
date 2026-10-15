export function publicFormPath(slug) { return `/form/${encodeURIComponent(slug)}`; }
export function publicOccasionPath(slug) { return `/${encodeURIComponent(slug)}/event`; }
export function canonicalPublicPath(path, kind, requested, canonical) {
    if (!requested || !canonical || requested === canonical) return path;
    const match = /^(\/[^?#]*)([?#].*)?$/.exec(path);
    if (!match) return path;
    const parts = match[1].split('/');
    const index = kind === 'form' ? (parts[1] === 'form' ? 2 : -1) : 1;
    if (index < 0) return path;
    try { if (decodeURIComponent(parts[index]) !== requested) return path; } catch { return path; }
    parts[index] = encodeURIComponent(canonical);
    return parts.join('/') + (match[2] || '');
}

export function formLinkFromPath(path) {
    if (!path.startsWith('/form/')) return null;
    const segment = path.substring('/form/'.length).split('/')[0];
    try { return segment ? decodeURIComponent(segment) : null; }
    catch { return null; }
}
export function replaceResolvedPublicLink(kind, requested, canonical) {
    const current = window.location.pathname + window.location.search + window.location.hash;
    const path = canonicalPublicPath(current, kind, requested, canonical);
    if (path !== current) window.history.replaceState(window.history.state, '', path);
}
