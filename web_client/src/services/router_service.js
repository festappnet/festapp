import { AppConfig } from '../app_config.js';
import { prepareFlutterRuntime } from './flutter_runtime_handoff.js';


export class RouterService {

    static FORM_PATH_PREFIX = '/form/';

    static openExternalUrl(url, { inCurrentWindow = false } = {}) {
        if (inCurrentWindow) {
            window.location.href = url;
            return;
        }
        window.open(url, '_blank', 'noopener,noreferrer');
    }

    static async navigateToOccasionApp(link) {
        await RouterService.navigateToFlutterRoute(
            RouterService.getOccasionAppPath(link),
        );
    }

    static getOccasionAppPath(link) {
        const cleanLink = link.split('?')[0].replace(/^\/+|\/+$/g, '');
        return `/${cleanLink}/event`;
    }

    static isPublicOccasionProgramPath(path) {
        return /^\/[^/]+\/event(?:\/.*)?$/.test(path);
    }

    static navigateToOccasion(link) {
        // For backwards compatibility or default behavior
        return RouterService.navigateToForm(link);
    }
    
    static async navigateToForm(link) {
        const cleanLink = link.split('?')[0];
        const path = `${RouterService.FORM_PATH_PREFIX}${cleanLink}`;
        RouterService._lastPath = path; // Update tracker
        RouterService.pushState(path);
        const { FormPage } = await import('../components/forms/form_page.js');
        // Instantiate using correct container (legacy id preserved)
        // Ensure to remove old instance if tracked via singleton in FormPage (which we removed)
        // Since we are moving to instance based, the Router should probably hold the current page reference
        // but for now, we just create new one which cleans up previous by id.
        new FormPage('form-page-container').init(link, { onBack: RouterService.goBackProgrammatically });
    }

    static getLoginUrl() {
        let baseUrl = AppConfig.flutterAppUrl || '';
        if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.slice(0, -1);
        }
        return `${baseUrl}/login`;
    }

    static getAdminUrl(occasionLink = '') {
        let baseUrl = AppConfig.flutterAppUrl || '';
        if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.slice(0, -1);
        }
        const cleanLink = occasionLink
            .split('?')[0]
            .replace(/^\/+|\/+$/g, '');
        const adminPath = cleanLink ? `/${cleanLink}/admin` : '/admin';
        return `${baseUrl}${adminPath}`;
    }

    static async navigateToLogin() {
        const url = RouterService.getLoginUrl();
        await RouterService.navigateToFlutterRoute(url);
    }

    static async navigateToAdmin(occasionLink = '') {
        const url = RouterService.getAdminUrl(occasionLink);
        await RouterService.navigateToFlutterRoute(url);
    }
    
    static async navigateToHandover() {
        const url = RouterService.getHandoverUrl();
        await RouterService.navigateToFlutterRoute(url);
    }

    static async navigateToFlutterRoute(url) {
        await prepareFlutterRuntime();
        RouterService.openExternalUrl(url, { inCurrentWindow: true });
    }

    static getHandoverUrl() {
        let baseUrl = AppConfig.flutterAppUrl || '';
        if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.slice(0, -1);
        }
        return `${baseUrl}/transfer`;
    }

    // History Management
    static pushState(path) {
        window.history.pushState({}, '', path);
    }
    
    static pushOverlayState(hash) {
        window.history.pushState({}, '', `${window.location.pathname}#${hash}`);
    }
    
    static goBackProgrammatically() {
        window.history.back();
    }
    
    static flutterRoutes = [
        '/reset-password',
        '/forgot-password',
        '/resetPassword',
        '/forgotPassword',
        '/login',
        '/signup',
        '/settings',
        '/install',
        '/unit',
        '/admin',
        // '/form', // Handled by Web Client
        '/scan',
        '/transfer'
    ];

    // Initial Load Check
    static async handleInitialLoad() {
        let path = window.location.pathname;
        const fullUrl = window.location.href;

        // 0. Normalize URL
        path = RouterService.normalizeUrl(fullUrl);

        // 1. Identify Route Type
        // Web Client Routes: / (Home), /index.html, /form/...
        const isWebClientRoute = path === '/' ||
                                 path === '/index.html' ||
                                 path.startsWith(RouterService.FORM_PATH_PREFIX);

        const isFlutterRoute = RouterService.flutterRoutes.some(r => path.startsWith(r));

        let shouldRedirectToFlutter = false;
        let redirectPath = path;

        // 2. Data-Driven Decision Logic (Mirrors Flutter AppRouter.getDefaultLink)
        if (AppConfig.isAppSupported) {
            // Need to fetch data to make a decision
            const { RightsService } = await import('./rights_service.js'); // Lazy load to avoid cycle
            await RightsService.updateAppData();

            const currentLink = RightsService.currentLink;
            const currentUnit = RightsService.currentUnit;

            let defaultLink = "/";
            // Logic mirroring Flutter:
            // if (!AppConfig.isAppSupported) { return "/"; } // Handled by outer if
            // if (RightsService.useOfflineVersion) ... // Skipped for Web

            // An all-unit deployment owns a catalogue at `/`. Its database
            // still has a representative/default occasion for native clients,
            // but that occasion must not replace the web catalogue root.
            if (AppConfig.isAllUnit && path === '/') {
                 defaultLink = '/';
            } else if (currentLink) {
                 defaultLink = RouterService.getOccasionAppPath(currentLink);
            } else if (currentUnit?.id) {
                 // return "/${UnitPage.ROUTE}/${RightsService.currentUnit()?.id}";
                 defaultLink = `/unit/${currentUnit.id}`;
            }

            // Decision:
            if (isFlutterRoute) {
                // Explicit Flutter route -> Redirect
                shouldRedirectToFlutter = true;
            } else if (isWebClientRoute) {
                 // We are on a Web Client Route (Home, Form)
                 // If we are at root /, we might want to "redirect" (SPA navigate) to the default link
                 // BUT ONLY if the default link itself is ALSO a Web Client Route.

                 if (path === '/') {
                     if (defaultLink !== '/') {
                         const targetIsWebClient = defaultLink.startsWith(RouterService.FORM_PATH_PREFIX);

                         if (targetIsWebClient) {
                             // SPA Navigate (Stay in Web Client)
                             window.history.replaceState(null, '', defaultLink);
                             RouterService._lastPath = defaultLink; // Critical: Sync tracker to prevent re-init on popstate
                             path = defaultLink; // Update path for subsequent loading logic
                             shouldRedirectToFlutter = false;
                         } else {
                             // Target is (likely) an Event Occasion link (e.g. /my-fest) or Unit -> Redirect to Flutter
                             shouldRedirectToFlutter = true;
                             redirectPath = defaultLink;
                         }
                     } else {
                         // Stay at root
                         shouldRedirectToFlutter = false;
                     }
                 } else {
                     // We are at /form/xyz -> Stay.
                     shouldRedirectToFlutter = false;
                 }

            } else {
                 // Unknown deep link (e.g. /my-fest) -> Redirect
                 shouldRedirectToFlutter = true;
            }

        } else {
            // Web Client Only Mode
             if (isWebClientRoute) {
                shouldRedirectToFlutter = false;
            } else if (isFlutterRoute) {
                shouldRedirectToFlutter = true;
            } else {
                // Unknown route -> Home
                window.history.replaceState(null, '', '/');
                RouterService._lastPath = '/';
                return true;
            }
        }

        // 3. Execute Redirect Purpose
        if (shouldRedirectToFlutter) {
             await prepareFlutterRuntime();
             // 1. Handover Strategy:
             // If we are at /transfer in the Web Client, it means we need to perform the handover to Flutter.
             // (In Production, the server handles this, but in Localhost/SPA navigation, we handle it here).
             
             // Special Case: Reset Password via Email Link
             // Links look like: .../resetPassword?token=...
             if (path.startsWith('/reset-password') || fullUrl.includes('reset-password') || 
                 path.startsWith('/resetPassword') || fullUrl.includes('resetPassword')) {
                 
                 // Flutter Parity: Use Regex to extract exact token string as Flutter does.
                 // Regex: token=(?<token>[^&]+)
                 const tokenMatch = fullUrl.match(/token=([^&]+)/);
                 
                 if (tokenMatch && tokenMatch[1]) {
                     // 1. Split hash if present (Flutter's regex captures it if not & terminated, but UUIDs don't have it)
                     // 2. Trim whitespace just in case
                     const rawToken = tokenMatch[1].split('#')[0].trim();
                     
                     
                     const { LoginModal } = await import('../components/users/login_modal.js'); 
                     
                     const modal = document.createElement('login-modal');
                     document.body.appendChild(modal);
                     // Set directly
                     modal.resetToken = rawToken;
                     
                     return true; 
                 }
             }

             // The public program shares the same origin and stable Supabase
             // auth-storage namespace as Flutter. Sending it through the
             // authenticated /transfer flow can replace the requested event
             // route with a unit dashboard (or login for anonymous visitors).
             // Navigate directly; any existing session remains available.
             if (RouterService.isPublicOccasionProgramPath(redirectPath)) {
                 window.location.replace(redirectPath);
                 return true;
             }

             if (!path.endsWith('auth_bridge.html')) {
                 // Fetch session to pass fresh tokens
                 const { SupabaseService } = await import('./supabase_service.js');
                 const { data } = await SupabaseService.getClient().auth.getSession();
                 let sessionFragment = '';
                 
                 if (data?.session) {
                     const { access_token, refresh_token } = data.session;
                     if (access_token && refresh_token) {
                         sessionFragment = `#access_token=${access_token}&refresh_token=${refresh_token}&token_type=bearer&type=recovery`;
                     }
                 }

                 let redirectUrl = `${window.location.origin}/auth_bridge.html`;
                 if (sessionFragment) {
                     redirectUrl += sessionFragment;
                 }
                 // pass the target path as a query param so auth_bridge.html can append it.
                 // The deep link callback in Flutter will handle the session.
                 const separator = redirectUrl.includes('#') ? '&' : '?';
                 redirectUrl += `${separator}redirect=${encodeURIComponent(redirectPath)}`;

                 window.location.replace(redirectUrl);
                 return true; // Stop SPA load
             }
        }

        // 4. Handle normalized path updates (UX polish)
        if (!shouldRedirectToFlutter) {
             // Clean URL if it contains query parameters or hash
             const hasPreview = window.location.search && window.location.search.includes('preview=true');
             const hasSearch = window.location.search && (window.location.search.includes('?q=') || window.location.search.includes('&q='));

             if (!hasPreview && !hasSearch && (window.location.search || window.location.hash || fullUrl.includes('?'))) {
                  window.history.replaceState(null, '', path);
                  RouterService._lastPath = path; // Sync tracker
             }
             if (fullUrl.includes('https://') && window.location.pathname.startsWith('/https:')) {
                  window.history.replaceState(null, '', path);
                  RouterService._lastPath = path; // Sync tracker
             }
        }

        // 5. Load Component
        if (path.startsWith(RouterService.FORM_PATH_PREFIX)) {
            const link = path.substring(RouterService.FORM_PATH_PREFIX.length);
            const cleanLink = link.split('/')[0];
            if (cleanLink) {
                const { FormPage } = await import('../components/forms/form_page.js');
                new FormPage('form-page-container').init(cleanLink, { onBack: RouterService.goBackProgrammatically });
                return true; // Handled
            }
        }

        return false;
    }

    static normalizeUrl(url) {
        let path = url;

        // Absolute URLs can come from any valid deployment origin, including
        // Cloudflare preview domains. Routing depends on their path, never on
        // whether the origin happens to be listed in compatibleUrls.
        try {
            const uri = new URL(url);
            path = `${uri.pathname}${uri.search}${uri.hash}`;
        } catch (_) {
            // Relative and legacy malformed paths are normalized below.
        }

        // Handle malformed paths e.g. /https://domain.com/path
        if (path.match(/^\/https?:/)) {
             const matchedBaseInternal = AppConfig.compatibleUrls.find(u => u && path.includes(u));
             if (matchedBaseInternal) {
                 const index = path.indexOf(matchedBaseInternal);
                 path = path.substring(index + matchedBaseInternal.length);
             }
        }

        // 2. Identify and Extract Legacy Hash /#/ regardless of preceding query params
        // Example: /?fbclid=123/#/form/slug  -> should extract /form/slug

        // Strategy: First split by # to isolate potential legacy hash
        const parts = path.split('#');
        if (parts.length > 1) {
            // Check if the part after # starts with / (Legacy Hash pattern)
            // or if it's the specific pattern we support
            const fragment = parts[1];
            if (fragment.startsWith('/')) {
                path = fragment; // Take the hash path as the new root
            } else {
                 // It's a normal fragment (e.g. #section), so we just want the path part before it.
                 // BUT wait, if we had /path#section, we want /path.
                 // If we had /?query#section, we want / (and query stripped later).
                 path = parts[0];
            }
        }

        // 2.5 Strip Query Parameters (Strict Sanitization)
        // Now that we've potentially re-rooted to the hash path, strip queries from it.
        // Also strip queries from the original path if we didn't re-root (e.g. /path?q=1)
        path = path.split('?')[0];

        // 3. Ensure leading slash
        if (!path.startsWith('/')) {
            path = '/' + path;
        }

        return path;
    }

    // Listen for PopState
    static _lastPath = window.location.pathname;

    static initPopStateListener() {
        window.addEventListener('popstate', async (event) => {
            const path = window.location.pathname;
            
            // Ignore hash changes (SPA overlays)
            if (path === RouterService._lastPath) {
                return;
            }
            RouterService._lastPath = path;

            if (path.startsWith(RouterService.FORM_PATH_PREFIX)) {
                 const link = path.substring(RouterService.FORM_PATH_PREFIX.length).split('/')[0];
                 const { FormPage } = await import('../components/forms/form_page.js');
                 new FormPage('form-page-container').init(link, { onBack: RouterService.goBackProgrammatically }); 
            } else {
                 window.location.reload(); 
            }
        });
    }
    
    static get onPopState() {
        return {
            listen: (callback) => {
                window.addEventListener('popstate', callback);
                return { cancel: () => window.removeEventListener('popstate', callback) };
            }
        };
    }
}
