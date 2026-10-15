import { handleOrganizerIntent } from './startup/organizer_intent.js';
import { GoogleAuthService } from './services/google_auth_service.js';
import { LoginModal } from './components/users/login_modal.js';
const googleCallback = GoogleAuthService.takeCallback();
import './theme_config.css';
import { AppConfig } from './app_config.js';
import { SupabaseService } from './services/supabase_service.js';
import { RightsService } from './services/rights_service.js';
import { RouterService } from './services/router_service.js';
import { LocalizationService } from './services/localization_service.js';
import { ThemeService } from './services/theme_service.js';
import { UnitPage } from './components/unit/unit_page.js';
import { UserHeader } from './components/users/user_header.js';
import { FeedbackFab } from './components/feedback/feedback_fab.js';
import { ImageLoader } from './utils/image_loader.js';
import { initializeCoreServices } from './startup/initialize_core_services.js';

class Main {
    static async init() {
        try {
            ThemeService.init();
            // 1. Init Core Services
            await initializeCoreServices({
                localizationService: LocalizationService,
                supabaseService: SupabaseService,
                rightsService: RightsService,
                // Content pages need account context without a later router fetch.
                isAppSupported: AppConfig.isAppSupported && document.body.dataset.page !== 'organizers',
            });
            ImageLoader.init(); // Initialize Image Loader

            if (googleCallback) {
                const modal = new LoginModal();
                document.body.appendChild(modal);
                modal._setView('google_completing');
                try { modal.showGoogleResult(await GoogleAuthService.complete(googleCallback)); }
                catch (error) { modal.googleError = error.message; modal._setView('login'); }
            }

            // Static public content owns this document; only shared account services run.
            if (document.body.dataset.page === 'organizers') {
                window.markFestappAppReady?.();
                return;
            }

            const organizerIntent = await handleOrganizerIntent();
            if (organizerIntent === 'navigated') {
                window.markFestappAppReady?.();
                return;
            }

            // 2. Check Routing (SPA Support)
            if (!organizerIntent && await RouterService.handleInitialLoad()) {
                 RouterService.initPopStateListener();
                 window.markFestappAppReady?.();
                 return;
            }

            // 3. Init UI Components
            // UserHeader is now a web component and auto-inits via tag in HTML
            const unitPage = new UnitPage('events-grid');
            unitPage.init('event-search');
            FeedbackFab.init('feedback-fab');

            // 4. Initial Fetch
            const unitMatch = window.location.pathname.match(/^\/unit\/([1-9]\d*)\/?$/);
            await unitPage.loadOccasions(AppConfig.organization, unitMatch ? Number(unitMatch[1]) : null);

            // Complete startup after the catalogue update settles; SSR stays usable while pending.
            const app = document.getElementById('app');
            if (app) app.style.display = 'flex';

            // Init PopState forভাগে logic
            RouterService.initPopStateListener();
            window.markFestappAppReady?.();



        } catch (e) {
            console.error("Initialization Error:", e);
            window.failFestappWebClientStartup?.('web-initialization-error');
        }
    }
}

// Start
document.addEventListener('DOMContentLoaded', Main.init);
