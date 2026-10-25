import { ThemeService } from '../services/theme_service.js';
import { LocalizationService } from '../services/localization_service.js';
import { SupabaseService } from '../services/supabase_service.js';
import { RightsService } from '../services/rights_service.js';
import { AppConfig } from '../app_config.js';
import { initializeCoreServices } from '../startup/initialize_core_services.js';
import '../components/users/user_header.js';

export async function initAccountHeader() {
    const marketingLocale = document.documentElement.lang;
    ThemeService.init();
    document.body.dataset.publicTheme = "initialized";
    const fallback = document.querySelector('.site-header');
    try {
        await initializeCoreServices({
            localizationService: {init: () => LocalizationService.init({locale: marketingLocale, persist: false})},
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

