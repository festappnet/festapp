// This intent selects a workflow. The administration boundary checks identity
// and current create capability; no resource ID or arbitrary return URL is accepted.
export const ORGANIZER_CREATE_ACTION = '/organizer-action/create';

export function organizerCreatePath(value) {
    if (typeof value !== 'string' || !value.startsWith('/') || value.startsWith('//') || value.includes('\\')) return null;
    const url = new URL(value, 'https://organizer.invalid');
    if (!['/', '/events', '/login', '/login/'].includes(url.pathname) || url.hash) return null;
    const keys = [...url.searchParams.keys()];
    const create = url.searchParams.getAll('create');
    const redirect = url.searchParams.getAll('redirect');
    const explicitCreate = create.length === 1 && create[0] === '1' &&
        keys.every(key => key === 'create' || /^utm_(source|medium|campaign|term|content)$/.test(key));
    const handoffReload = ['/login', '/login/'].includes(url.pathname) &&
        keys.length === 1 && redirect.length === 1 && redirect[0] === ORGANIZER_CREATE_ACTION;
    return explicitCreate || handoffReload ? '/login?create=1' : null;
}

export function organizerCreateFlutterPath() {
    const login = '/login?redirect=' + encodeURIComponent(ORGANIZER_CREATE_ACTION);
    return '/flutter?redirect=' + encodeURIComponent(login);
}
