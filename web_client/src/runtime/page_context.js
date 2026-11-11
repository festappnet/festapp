// Presentation only. This classification never grants identity or permissions.
export function pageContext(location) {
    return location && (/^\/order$/.test(location.pathname) || /^\/form\/[^/]+\/?$/.test(location.pathname)) &&
        new URLSearchParams(location.search).get('embed') === '1' ? 'public-embed' : 'full-page';
}
