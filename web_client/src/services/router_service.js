import { normalizeUrl, legacyHashTarget } from './url_normalizer.js';
import { isEmbed } from './embed_context.js';
import { resolveScannerRoute } from './scanner_routes.js';
import { formLinkFromPath, replaceResolvedPublicLink } from './public_link.js';
import { AppConfig } from '../app_config.js';
import { prepareFlutterRuntime } from './flutter_runtime_handoff.js';


export class RouterService {

    static FORM_PATH_PREFIX = '/form/';

    static getFormLink(path) { return formLinkFromPath(path); }

    static openExternalUrl(url, { inCurrentWindow = false } = {}) {
        if (inCurrentWindow) {
            window.location.href = url;
            return;
        }
        window.open(url, '_blank', 'noopener,noreferrer');
    }

    static canonicalizePublicLink(kind, requested, canonical) {
        replaceResolvedPublicLink(kind, requested, canonical);
        RouterService._lastPath = window.location.pathname;
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

    
    static async navigateToForm(link) {
        const cleanLink = link.split('?')[0];
        const path = `${RouterService.FORM_PATH_PREFIX}${cleanLink}${isEmbed() ? window.location.search + window.location.hash : ''}`;
        RouterService._lastPath = `${RouterService.FORM_PATH_PREFIX}${cleanLink}`;
        RouterService.pushState(path);
        await RouterService.mountForm(cleanLink);
    }

    static async mountForm(link) {
        const { FormPage } = await import('../components/forms/form_page.js');
        RouterService._formPage?.clear();
        RouterService._formPage = new FormPage('form-page-container');
        await RouterService._formPage.init(link, { onBack: RouterService.goBackProgrammatically });
    }

    static getLoginUrl() {
        let baseUrl = AppConfig.flutterAppUrl || '';
        if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.slice(0, -1);
        }
        return `${baseUrl}/login`;
    }

    static getAdminUrl(unitId = null) {
        const normalizedUnitId = Number(unitId);
        if (Number.isInteger(normalizedUnitId) && normalizedUnitId > 0) {
            return `/unit/${normalizedUnitId}/edit`;
        }
        return '/admin';
    }

    static async navigateToAdmin(unitId = null) {
        const url = RouterService.getAdminUrl(unitId);
        await RouterService.navigateToFlutterRoute(url);
    }
    
    static async navigateToHandover() {
        const url = RouterService.getHandoverUrl();
        await RouterService.navigateToFlutterRoute(url);
    }

    static async navigateToFlutterRoute(url) {
        if (isEmbed()) return;
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
        // Personal capabilities must survive reload while an overlay is open.
        // The browser owns the fragment; keep only the overlay name in state.
        if ((window.location.hash.startsWith('#waitlist?') || window.location.hash.startsWith('#order?'))) {
            window.history.pushState({ overlay: hash }, '', window.location.href);
        } else {
            window.history.pushState({}, '', `${window.location.pathname}${window.location.search}#${hash}`);
        }
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
        '/transfer'
    ];

    // Initial Load Check
    static async handleInitialLoad() {
        // The callback owns its continuation dialog until the user finishes or
        // cancels. App-supported tenants must not hand it off to Flutter.
        if (window.location.pathname === '/google-auth') return true;
        let path = window.location.pathname;
        const legacyTarget = legacyHashTarget(window.location.href, AppConfig.compatibleUrls);
        if (legacyTarget) window.history.replaceState(null, '', legacyTarget);
        const fullUrl = legacyTarget ? new URL(legacyTarget, window.location.origin).href : window.location.href;

        // 0. Normalize URL
        path = RouterService.normalizeUrl(fullUrl);

        const scannerRoute = resolveScannerRoute(path);
        if (scannerRoute) {
            const requestedOccasion = new URL(fullUrl).searchParams.get('occasion');
            if (/^[1-9][0-9]*$/.test(requestedOccasion || '')) scannerRoute.occasion = requestedOccasion;
            const target = scannerRoute.canonical || path;
            if (!scannerRoute.code) window.history.replaceState(null, '', target);
            this._lastPath = target;
            await this.mountScanner(scannerRoute);
            return true;
        }

        // The root shell must see scanner hashes before the tenant home handoff.
        if (path === '/' && AppConfig.forceOccasionLink) {
            await RouterService.navigateToFlutterRoute(`/${encodeURIComponent(AppConfig.forceOccasionLink)}/event`);
            return true;
        }

        // 1. Identify Route Type
        // Web Client Routes: / (Home), /index.html, /form/...
        const isWebClientRoute = path === '/' ||
                                 (path === '/events' && new URL(AppConfig.webLink).hostname === 'vstupenky.online') ||
                                 path === '/index.html' ||
                                 path.startsWith(RouterService.FORM_PATH_PREFIX);

        const isFlutterRoute = RouterService.flutterRoutes.some(r => path.startsWith(r)) ||
            /^\/[^/]+\/(?:admin|reservations)(?:\/|$)/.test(path);

        let shouldRedirectToFlutter = false;
        const requested = new URL(fullUrl);
        const legacyRoute = requested.hash.startsWith('#/')
            ? new URL(requested.hash.slice(1), requested.origin) : null;
        const query = legacyRoute?.search || requested.search;
        let redirectPath = `${path}${query}`;

        // 2. Data-Driven Decision Logic (Mirrors Flutter AppRouter.getDefaultLink)
        if (AppConfig.isAppSupported && !isEmbed()) {
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
                             redirectPath = `${defaultLink}${query}`;
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

             if (!legacyTarget && !isEmbed() && !hasPreview && !hasSearch && !(window.location.hash.startsWith('#waitlist?') || window.location.hash.startsWith('#order?')) && (window.location.search || window.location.hash || fullUrl.includes('?'))) {
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
            const cleanLink = RouterService.getFormLink(path);
            if (cleanLink) {
                await RouterService.mountForm(cleanLink);
                return true; // Handled
            }
        }

        return false;
    }

    static async mountScanner(route) {
        this._scannerPage?.clear();
        document.getElementById('app')?.style.setProperty('display', 'none');
        const host = document.getElementById('form-page-container');
        host.style.display = 'block';
        const { SupabaseService } = await import('./supabase_service.js');
        const domain = ['program','reception'].includes(route.page);
        if (domain) await SupabaseService.initialize();
        // Ticket shell and IDB mount without waiting for Auth refresh. The first
        // online RPC still resolves/validates the normal backend before use.
        const client = domain ? SupabaseService.getClient() : {
            get supabaseUrl() { return SupabaseService._backend.supabaseUrl; },
            get scannerBackendContext() {
                const b=SupabaseService._backend;
                return { generation:b.isCanonical?1:0,origin:b.supabaseUrl,organization:b.organizationId };
            },
            async rpc(...args) { await SupabaseService.initialize(); return SupabaseService.getClient().rpc(...args); },
        };
        const { ScanPage } = await import('../components/scan/scan_page.js');
        const { ScannerDomainPage } = await import('../components/scan/scanner_domain_page.js');
        this._scannerPage = ['program','reception'].includes(route.page)
            ? new ScannerDomainPage(host, { client }) : new ScanPage(host, { client });
        await this._scannerPage.init(route);
    }

    static normalizeUrl(url) {
        return normalizeUrl(url, AppConfig.compatibleUrls);
    }

    // Listen for PopState
    static _lastPath = window.location.pathname;

    static initPopStateListener() {
        window.addEventListener('hashchange', (event) => {
            const previous = new URL(event.oldURL);
            const current = new URL(event.newURL);
            if (current.pathname.startsWith(RouterService.FORM_PATH_PREFIX) &&
                previous.hash !== current.hash &&
                ([previous.hash, current.hash].some(hash => hash.startsWith('#waitlist?') || hash.startsWith('#order?')))) {
                // A different personal capability is a fresh form session.
                window.location.reload();
            }
        });
        window.addEventListener('popstate', async (event) => {
            const path = window.location.pathname;
            
            // Ignore hash changes (SPA overlays)
            if (path === RouterService._lastPath) {
                return;
            }
            RouterService._lastPath = path;

            const scannerRoute = resolveScannerRoute(path);
            if (scannerRoute) { await RouterService.mountScanner(scannerRoute); return; }
            RouterService._scannerPage?.clear(); RouterService._scannerPage = null;
            if (path.startsWith(RouterService.FORM_PATH_PREFIX)) {
                 const link = RouterService.getFormLink(path);
                 await RouterService.mountForm(link); 
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
