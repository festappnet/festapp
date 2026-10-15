import { AppConfig } from '../app_config.js';
import { RightsService } from '../services/rights_service.js';
import { RouterService } from '../services/router_service.js';
import { LocalizationService } from '../services/localization_service.js';

// Reuse the same guest registration and signed-in administration entry as UserHeader.
export async function handleOrganizerIntent() {
    if (new URL(AppConfig.webLink).hostname !== 'vstupenky.online' ||
        window.location.pathname !== '/' || new URLSearchParams(window.location.search).get('create') !== '1') return false;
    const url = new URL(window.location.href);
    await RightsService.updateAppData();
    url.searchParams.delete('create');
    window.history.replaceState(null, '', url.pathname + url.search + url.hash);
    if (RightsService.currentUser?.id) {
        await RouterService.navigateToAdmin(RightsService.currentUnit?.id ?? RightsService.currentUser.units?.[0]?.id);
        return 'navigated';
    }
    if (RightsService.context?.organization?.IS_REGISTRATION_ENABLED === true) {
        await import('../components/users/login_modal.js');
        const modal = document.createElement('login-modal');
        modal.currentView = 'register';
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
