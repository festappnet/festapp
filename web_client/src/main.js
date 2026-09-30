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
            // 1. Init Core Services
            await initializeCoreServices({
                localizationService: LocalizationService,
                supabaseService: SupabaseService,
                rightsService: RightsService,
                isAppSupported: AppConfig.isAppSupported,
            });
            ThemeService.init();
            ImageLoader.init(); // Initialize Image Loader

            // 2. Check Routing (SPA Support)
            if (await RouterService.handleInitialLoad()) {
                 RouterService.initPopStateListener();
                 window.markFestappAppReady?.();
                 return; 
            }
            
            // Not a form page, show the home app
            const app = document.getElementById('app');
            if (app) app.style.display = 'flex';
            
            // 3. Init UI Components
            // UserHeader is now a web component and auto-inits via tag in HTML
            const unitPage = new UnitPage('events-grid');
            unitPage.init('event-search');
            FeedbackFab.init('feedback-fab');
    
            // 4. Initial Fetch
            unitPage.loadOccasions(AppConfig.organization);
            
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
