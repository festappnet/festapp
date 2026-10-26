import { AppConfig } from '../app_config.js';
import { RightsService } from '../services/rights_service.js';
import { RouterService } from '../services/router_service.js';
import { LocalizationService } from '../services/localization_service.js';
import { organizerCreatePath, organizerCreateFlutterPath } from '../services/organizer_entry.js';

// Public login links from any page or tenant use the web client.
// Organizer creation keeps the existing tenant and registration restrictions.
export async function handleOrganizerIntent() {
    const current = new URL(window.location.href);
    if (/^#\/login\/?(?:\?|$)/.test(current.hash)) {
        const legacy = new URL(current.hash.slice(1), current.origin);
        window.history.replaceState(null, '', legacy.pathname + legacy.search);
    }
    const intent = new URLSearchParams(window.location.search);
    const create = organizerCreatePath(window.location.pathname + window.location.search) !== null;
    const loginRoute = ['/login', '/login/'].includes(window.location.pathname);
    const login = loginRoute || intent.get('login') === '1';
    const organizerRoute = new URL(AppConfig.webLink).hostname === 'vstupenky.online' &&
        ['/', '/events'].includes(window.location.pathname) && (create || login);
    if (!loginRoute && !organizerRoute) return false;
    const url = new URL(window.location.href);
    await RightsService.updateAppData();
    if (create) {
        // Keep the workflow through registration, password sign-in and reload.
        url.searchParams.delete('redirect');
        url.searchParams.set('create', '1');
    }
    url.searchParams.delete('login');
    window.history.replaceState(null, '', url.pathname + url.search + url.hash);
    if (RightsService.currentUser?.id) {
        if (create) {
            await RouterService.navigateToFlutterRoute(organizerCreateFlutterPath());
            return 'navigated';
        }
        const unitId = RightsService.currentUnit?.id ?? RightsService.currentUser.units?.[0]?.id;
        if (unitId) await RouterService.navigateToAdmin(unitId);
        return unitId ? 'navigated' : 'catalog';
    }
    if (login || RightsService.context?.organization?.IS_REGISTRATION_ENABLED === true) {
        await import('../components/users/login_modal.js');
        const modal = document.createElement('login-modal');
        modal.currentView = create && RightsService.context?.organization?.IS_REGISTRATION_ENABLED === true
            ? 'register' : login ? 'login' : 'register';
        document.body.appendChild(modal);
    } else {
        const notice = document.createElement('p');
        notice.setAttribute('role', 'status');
        notice.textContent = LocalizationService.currentLocale === 'en'
            ? 'Registration is currently unavailable. To create an event, contact info@festapp.net.'
            : 'Registrace nyní není dostupná. Pro založení akce kontaktujte info@festapp.net.';
        document.querySelector('#app main')?.prepend(notice);
    }
    return 'catalog';
}
