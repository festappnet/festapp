// Self-contained so generated workers use this exact policy as the web client.
export function isPublicOccasionAppPath(pathname) {
    let path;
    try { path = decodeURIComponent(pathname); } catch { return false; }
    const segments = path.split('/').filter(Boolean);
    if (segments.length === 0) return false;
    const reservedRoots = new Set([
        'form', 'order', 'login', 'login-qr', 'admin', 'transfer', 'organizationEdit', 'unit', 'signup',
        'settings', 'install', 'instanceInstall', 'scan', 'check', 'map-editor',
        'resetPassword', 'forgotPassword', 'reset-password', 'forgot-password',
        'google-auth', 'app', 'privacy', 'terms', 'support', 'delete-account',
        'flutter', 'webclient', 'auth_bridge', 'assets', 'web-assets', 'canvaskit',
        'pro-poradatele', 'organizers-page', 'events', 'napoveda',
    ]);
    if (reservedRoots.has(segments[0]) || segments[0].includes('.')) return false;
    if (segments.length === 1) return true;
    return new Set([
        'event', 'news', 'newsForm', 'map', 'user', 'info', 'unit',
        'timetable', 'myschedule', 'counseling', 'game', 'songbook', 'userstay',
    ]).has(segments[1]);
}

// Called only for tenants without the festival application. Keep an old
// administration link in the same occasion, with the ticketing access checks.
export function unsupportedOccasionAppRedirect(pathname) {
    let path;
    try { path = decodeURIComponent(pathname); } catch { return null; }
    const segments = path.split('/').filter(Boolean);
    if (segments[0] === 'map-editor') return '/';
    if (segments.length >= 2 && isPublicOccasionAppPath('/' + encodeURIComponent(segments[0]))) {
        if (segments[1] === 'admin') return '/' + encodeURIComponent(segments[0]) + '/reservations';
        if (['eventEdit', 'reception', 'cleaning'].includes(segments[1])) return '/';
    }
    return isPublicOccasionAppPath(pathname) ? '/' : null;
}
