import { initDemoPlayers } from './demo_player.js';
import { initMotion } from './motion.js';
import { initReferenceCarousels } from './reference_carousel.js';
import { ThemeService } from '../services/theme_service.js';
import { LocalizationService } from '../services/localization_service.js';
import { SupabaseService } from '../services/supabase_service.js';
import { RightsService } from '../services/rights_service.js';
import { AppConfig } from '../app_config.js';
import { initializeCoreServices } from '../startup/initialize_core_services.js';
import '../components/users/user_header.js';

async function initAccountHeader() {
    ThemeService.init();
    const fallback = document.querySelector('.site-header');
    try {
        await initializeCoreServices({
            localizationService: LocalizationService,
            supabaseService: SupabaseService,
            rightsService: RightsService,
            isAppSupported: AppConfig.isAppSupported,
        });
        if (!RightsService.context) await RightsService.updateAppData();
        if (!RightsService.context) throw new Error('Account context unavailable');
        const header = document.createElement('user-header');
        header.setAttribute('data-marketing', '');
        fallback?.replaceWith(header);
    } catch (error) {
        fallback?.classList.remove('auth-pending');
        console.warn('Account header unavailable', error);
    }
}

// Legacy app/scanner hash links still enter through the marketing root.
const current = new URL(window.location.href);
const legacy = current.hash.startsWith('#/') ? new URL(current.hash.slice(1), current.origin) : null;
const target = legacy?.origin === current.origin && legacy.pathname !== '/' ? legacy.pathname + legacy.search + legacy.hash : null;
if (target) {
    window.location.replace(target);
} else {
    void initAccountHeader();
    initDemoPlayers();
    initMotion();
    initReferenceCarousels();
}
