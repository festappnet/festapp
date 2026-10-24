// Explicit public presentation context. Never changes the checkout principal.
export function isEmbed(location = globalThis.location ?? globalThis.window?.location) {
    return Boolean(location && /^\/form\/[^/]+\/?$/.test(location.pathname) &&
        new URLSearchParams(location.search).get('embed') === '1');
}

export function applyEmbedContext() {
    if (isEmbed()) document.documentElement.classList.add('festapp-embed');
}
