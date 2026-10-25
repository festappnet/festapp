// Public documentation intents carry no event identifiers or arbitrary URLs.
export function helpActionIntent(value) {
    return typeof value === 'string' && /^(forms|seating|tickets|products|orders|report|settings|scanner-settings)$/.test(value) ? value : null;
}

export function helpActionFromWebPath(value) {
    if (typeof value !== 'string' || !value.startsWith('/events?')) return null;
    const url = new URL(value, 'https://help.invalid');
    if (url.hash || [...url.searchParams.keys()].some(key => key !== 'help') || url.searchParams.getAll('help').length !== 1) return null;
    return helpActionIntent(url.searchParams.get('help'));
}

export function helpActionWebPath(intent) {
    return helpActionIntent(intent) ? '/events?help=' + encodeURIComponent(intent) : null;
}

export function helpActionFlutterPath(intent) {
    if (!helpActionIntent(intent)) return null;
    const login = '/login?redirect=' + encodeURIComponent('/help-action/' + intent);
    // The normal Flutter shell restores this internal route before bootstrap.
    // A reload returns to web sign-in, preserving the original intent.
    return '/flutter?redirect=' + encodeURIComponent(login);
}
