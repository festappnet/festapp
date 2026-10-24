import { isEmbed, applyEmbedContext } from './services/embed_context.js';
import './embed.css';
import { resolveScannerRoute } from './services/scanner_routes.js';
import { handleOrganizerIntent } from './startup/organizer_intent.js';
import { GoogleAuthService } from './services/google_auth_service.js';
import { LoginModal } from './components/users/login_modal.js';
applyEmbedContext();
const googleCallback = isEmbed() ? null : GoogleAuthService.takeCallback();
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
            // Scanner shell starts locally before optional rights/network startup.
            const scannerRoute = resolveScannerRoute(RouterService.normalizeUrl(window.location.href));
            if (scannerRoute) {
                ThemeService.init();
                await LocalizationService.init();
                SupabaseService.initializeScannerOffline();
                await RouterService.handleInitialLoad();
                RouterService.initPopStateListener();
                window.markFestappAppReady?.();
                return;
            }
            // 1. Init Core Services
            await initializeCoreServices({
                localizationService: LocalizationService,
                supabaseService: SupabaseService,
                rightsService: RightsService,
                isAppSupported: AppConfig.isAppSupported,
                publicEmbed: isEmbed(),
            });
            ThemeService.init();
            ImageLoader.init(); // Initialize Image Loader

            if (googleCallback) {
                const modal = new LoginModal();
                document.body.appendChild(modal);
                modal._setView('google_completing');
                try { modal.showGoogleResult(await GoogleAuthService.complete(googleCallback)); }
                catch (error) { modal.googleError = error.message; modal._setView('login'); }
            }

            const organizerIntent = isEmbed() ? null : await handleOrganizerIntent();
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
            await unitPage.loadOccasions(AppConfig.organization);

            // Reveal the catalogue after the styled cards or retry state are ready.
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
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', Main.init, { once: true });
} else {
    Main.init();
}
