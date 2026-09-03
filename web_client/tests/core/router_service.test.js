import { test } from 'node:test';
import assert from 'node:assert';

test('RouterService.normalizeUrl', async (t) => {

    // Mock window and location BEFORE importing RouterService
    global.window = {
        location: {
            pathname: '/',
            href: 'https://vstupenky.online/',
            hash: '',
            origin: 'https://vstupenky.online',
            replace: () => {},
        },
        history: {
            replaceState: () => {},
            pushState: () => {}
        },
        addEventListener: () => {},
        removeEventListener: () => {}
    };

    // Dynamic import to ensure global.window is set before module evaluation
    const { RouterService } = await import('../../src/services/router_service.js');
    const { AppConfig } = await import('../../src/app_config.js');
    
    // Setup Mock Config
    const originalLink = AppConfig.webLink;
    const originalCompatible = AppConfig.compatibleUrls;

    AppConfig.webLink = "https://vstupenky.online";
    AppConfig.compatibleUrls = ["https://vstupenky.online"];

    await t.test('should strip configured base URL', () => {
        const input = "https://vstupenky.online/form/test";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/form/test");
    });

    await t.test('should strip query params in normalizeUrl', () => {
        const input = "https://vstupenky.online/form/test?fbclid=123";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/form/test");
    });

    await t.test('should handle localhost dynamic origin', () => {
        // Mocking URL behavior for localhost is tricky in node unless we pass it specifically
        // But our logic uses `new URL(url).origin`.
        const input = "http://localhost:8080/form/custom";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/form/custom");
    });

    await t.test('should use the path from an unconfigured deployment origin', () => {
        const route = '/form/preview';
        const unconfiguredOrigin = new URL(AppConfig.webLink);
        unconfiguredOrigin.hostname = `preview-${process.pid}.${unconfiguredOrigin.hostname}`;

        const result = RouterService.normalizeUrl(new URL(route, unconfiguredOrigin).toString());

        assert.strictEqual(result, route);
    });

    await t.test('should handle malformed path starting with https prefix (stripped by browser but left in path)', () => {
        // Case: /https://vstupenky.online/form/test
        const input = "/https://vstupenky.online/form/test";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/form/test");
    });

    await t.test('should handle legacy hash', () => {
        const input = "/#/form/legacy";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/form/legacy");
    });

    await t.test('should return input if no match', () => {
        const input = "/simple/path";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/simple/path");
    });

    await t.test('should strip generic hash', () => {
        const input = "/form/test#some-setting";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/form/test");
    });

    await t.test('should handle user specific legacy hash case', () => {
        const input = "https://vstupenky.online/#/form/farni-ples-2026-cernobily";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/form/farni-ples-2026-cernobily");
    });

    await t.test('should handle combined legacy hash AND query params (in hash)', () => {
        const input = "https://vstupenky.online/#/form/slug?fbclid=123&other=456";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/form/slug");
    });

    await t.test('should handle combined legacy hash AND query params (before hash)', () => {
        const input = "https://vstupenky.online/?fbclid=123#/form/slug";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/form/slug");
    });

    await t.test('should handle legacy hash AND fragment', () => {
        const input = "https://vstupenky.online/#/form/slug#section";
        const result = RouterService.normalizeUrl(input);
        assert.strictEqual(result, "/form/slug");
    });

    // Cleanup
    AppConfig.webLink = originalLink;
    AppConfig.compatibleUrls = originalCompatible;
});

test('admin is a canonical Flutter root route', async () => {
    global.window = {
        location: { pathname: '/', href: 'https://vstupenky.online/', hash: '' },
        history: { replaceState: () => {}, pushState: () => {} },
        addEventListener: () => {},
        removeEventListener: () => {}
    };
    const { RouterService } = await import('../../src/services/router_service.js');
    assert.ok(RouterService.flutterRoutes.includes('/admin'));
});

test('RouterService.Sanitization', async (t) => {
    // Mock window
    global.window = {
        location: { href: '' },
        open: () => {},
        history: { pushState: () => {} }
    };
    const { RouterService } = await import('../../src/services/router_service.js');

    await t.test('should PRESERVE query params in a new window', () => {
        let opened;
        global.window.open = (url, target, features) => {
            opened = { url, target, features };
        };

        RouterService.openExternalUrl('https://example.com?foo=bar');
        assert.deepStrictEqual(opened, {
            url: 'https://example.com?foo=bar',
            target: '_blank',
            features: 'noopener,noreferrer'
        });

        RouterService.openExternalUrl('https://example.com?foo=bar&baz=1');
        assert.strictEqual(opened.url, 'https://example.com?foo=bar&baz=1');
    });

    await t.test('should PRESERVE query params in the current window', () => {
        let locationHref = '';
        // Mock setter
        Object.defineProperty(global.window.location, 'href', {
            set: (v) => locationHref = v,
            configurable: true
        });

        RouterService.openExternalUrl('/some/path?query=1', { inCurrentWindow: true });
        assert.strictEqual(locationHref, '/some/path?query=1');
    });

    await t.test('should strip query params in navigateToOccasionApp', async () => {
        let locationHref = '';
        Object.defineProperty(global.window.location, 'href', {
            set: (v) => locationHref = v,
            configurable: true
        });

        await RouterService.navigateToOccasionApp('my-event?source=fb');
        assert.strictEqual(locationHref, '/my-event/event');
    });

    await t.test('should canonicalize occasion app roots to program', () => {
        assert.strictEqual(
            RouterService.getOccasionAppPath('/my-event/'),
            '/my-event/event',
        );
        assert.strictEqual(
            RouterService.isPublicOccasionProgramPath('/my-event/event/42'),
            true,
        );
        assert.strictEqual(
            RouterService.isPublicOccasionProgramPath('/admin'),
            false,
        );
    });

    await t.test('should strip query params in navigateToForm', async () => {
        let pushedPath = '';
        global.window.history.pushState = (state, title, url) => { pushedPath = url; };

        try {
            await RouterService.navigateToForm('my-event?param=1');
        } catch (e) {
            // Ignore CSS import errors and similar in Node environment
            if (e.code !== 'ERR_UNKNOWN_FILE_EXTENSION' && !e.message.includes('css')) {
                // If we want to be strict, we could log, but for now we expect this failure
                // due to FormPage import.
            }
        }
        assert.strictEqual(pushedPath, '/form/my-event');
    });
});


test('RouterService.handleInitialLoad', async (t) => {
    // Reset window for this block
    global.window = {
        location: {
            pathname: '/',
            href: 'https://vstupenky.online/',
            hash: '',
            origin: 'https://vstupenky.online',
            replace: () => {},
        },
        history: {
            replaceState: () => {},
            pushState: () => {}
        },
        addEventListener: () => {},
        removeEventListener: () => {}
    };

    // Dynamic import inside each test block if we need fresh mocks,
    // but modules are cached. We will just use the imported classes and mock global state.
    
    // Ensure we have the classes
    const { RouterService } = await import('../../src/services/router_service.js');
    const { AppConfig } = await import('../../src/app_config.js');
    const { RightsService } = await import('../../src/services/rights_service.js');
    const { SupabaseService } = await import('../../src/services/supabase_service.js');
    const originalGetClient = SupabaseService.getClient;
    SupabaseService.getClient = () => ({
        auth: { getSession: async () => ({ data: { session: null }, error: null }) },
    });
    t.after(() => { SupabaseService.getClient = originalGetClient; });

    // SETUP CONFIG FOR ALL TESTS
    AppConfig.webLink = "https://vstupenky.online";
    AppConfig.compatibleUrls = ["https://vstupenky.online"];
    AppConfig.flutterAppUrl = "https://vstupenky.online/flutter.html";

    await t.test('should build an occasion-scoped Flutter admin URL', () => {
        AppConfig.flutterAppUrl = '';
        assert.strictEqual(
            RouterService.getAdminUrl('/hvezdamorska/?preview=true'),
            '/hvezdamorska/admin',
        );
        AppConfig.flutterAppUrl = "https://vstupenky.online/flutter.html";
    });

    await t.test('should stay on Home / when isAppSupported=false (Web Client Only)', async () => {
        AppConfig.isAppSupported = false;
        global.window.location.pathname = '/';
        global.window.location.href = 'https://vstupenky.online/';
        
        let redirected = false;
        global.window.location.replace = (url) => { redirected = true; };
        
        const handled = await RouterService.handleInitialLoad();
        
        assert.strictEqual(redirected, false);
        assert.strictEqual(handled, false); 
    });

    await t.test('should redirect /login to flutter.html always', async () => {
        AppConfig.isAppSupported = false;
        global.window.location.pathname = '/login';
        global.window.location.href = 'https://vstupenky.online/login';
        
        let redirectUrl = '';
        global.window.location.replace = (url) => { redirectUrl = url; };
        
        const handled = await RouterService.handleInitialLoad();
        
        assert.strictEqual(handled, true);
        assert.ok(redirectUrl.includes('auth_bridge.html'));
        assert.ok(redirectUrl.includes('redirect=%2Flogin'));
    });

    await t.test('should redirect unknown path to Home when isAppSupported=false', async () => {
        AppConfig.isAppSupported = false;
        global.window.location.pathname = '/unknown-path';
        global.window.location.href = 'https://vstupenky.online/unknown-path';
        
        let historyReplaced = false;
        let replacePath = '';
        global.window.history.replaceState = (_, __, p) => { 
            historyReplaced = true; 
            replacePath = p; 
        };
        
        const handled = await RouterService.handleInitialLoad();
        
        // Should handle it by returning true (stopping main app load)
        assert.strictEqual(handled, true);
        assert.strictEqual(historyReplaced, true);
        assert.strictEqual(replacePath, '/');
    });

    // --- DATA DRIVEN TESTS ---

    await t.test('should keep the catalogue root for an all-unit deployment', async () => {
        AppConfig.isAppSupported = true;
        AppConfig.isAllUnit = true;
        RightsService.updateAppData = async () => {};

        const originalCurrentLink = Object.getOwnPropertyDescriptor(RightsService, 'currentLink');
        const originalCurrentUnit = Object.getOwnPropertyDescriptor(RightsService, 'currentUnit');
        Object.defineProperty(RightsService, 'currentLink', { get: () => 'default' });
        Object.defineProperty(RightsService, 'currentUnit', { get: () => ({ id: 5 }) });

        global.window.location.pathname = '/';
        global.window.location.href = 'https://hvezdamorska.festapp.net/';
        let redirectUrl = '';
        global.window.location.replace = (url) => { redirectUrl = url; };

        const handled = await RouterService.handleInitialLoad();

        assert.strictEqual(handled, false);
        assert.strictEqual(redirectUrl, '');

        AppConfig.isAllUnit = false;
        if (originalCurrentLink) Object.defineProperty(RightsService, 'currentLink', originalCurrentLink);
        if (originalCurrentUnit) Object.defineProperty(RightsService, 'currentUnit', originalCurrentUnit);
    });

    await t.test('should redirect Root to Occasion Link (conference2024) even if Unit ID (9) exists', async () => {
        AppConfig.isAppSupported = true;
        
        RightsService.updateAppData = async () => {};
        
        // Mock Data reflecting RPC result
        const originalCurrentLink = Object.getOwnPropertyDescriptor(RightsService, 'currentLink');
        Object.defineProperty(RightsService, 'currentLink', { get: () => 'conference2024' });

        const originalCurrentUnit = Object.getOwnPropertyDescriptor(RightsService, 'currentUnit');
        Object.defineProperty(RightsService, 'currentUnit', { get: () => ({ id: 9 }) });

        global.window.location.pathname = '/';
        global.window.location.href = 'https://vstupenky.online/';
        
        let redirectUrl = '';
        global.window.location.replace = (url) => { redirectUrl = url; };

        const handled = await RouterService.handleInitialLoad();

        assert.strictEqual(handled, true);
        assert.strictEqual(redirectUrl, '/conference2024/event');

        // Cleanup
        if (originalCurrentLink) Object.defineProperty(RightsService, 'currentLink', originalCurrentLink);
        if (originalCurrentUnit) Object.defineProperty(RightsService, 'currentUnit', originalCurrentUnit);
    });

    await t.test('should redirect Root to Occasion Link when AppSupported=true and Link found', async () => {
        AppConfig.isAppSupported = true;
        
        // Mock RightsService Update
        RightsService.updateAppData = async () => {};
        // Mock Getters
        const originalCurrentLink = Object.getOwnPropertyDescriptor(RightsService, 'currentLink');
        Object.defineProperty(RightsService, 'currentLink', { get: () => 'my-occasion' });

        global.window.location.pathname = '/';
        global.window.location.href = 'https://vstupenky.online/';
        
        let redirectUrl = '';
        global.window.location.replace = (url) => { redirectUrl = url; };

        const handled = await RouterService.handleInitialLoad();

        // Occasion Link is NOT a Web Client route -> Redirect to Flutter
        assert.strictEqual(handled, true);
        assert.strictEqual(redirectUrl, '/my-occasion/event');

        // Cleanup
        if (originalCurrentLink) Object.defineProperty(RightsService, 'currentLink', originalCurrentLink);
    });

    await t.test('should redirect Root to Unit ID when AppSupported=true, No Link, but Unit found', async () => {
        AppConfig.isAppSupported = true;
        
        RightsService.updateAppData = async () => {};
        
        const originalCurrentLink = Object.getOwnPropertyDescriptor(RightsService, 'currentLink');
        Object.defineProperty(RightsService, 'currentLink', { get: () => null });

        const originalCurrentUnit = Object.getOwnPropertyDescriptor(RightsService, 'currentUnit');
        Object.defineProperty(RightsService, 'currentUnit', { get: () => ({ id: 123 }) });

        global.window.location.pathname = '/';
        global.window.location.href = 'https://vstupenky.online/';
        
        let redirectUrl = '';
        global.window.location.replace = (url) => { redirectUrl = url; };

        const handled = await RouterService.handleInitialLoad();

        assert.strictEqual(handled, true);
        assert.ok(redirectUrl.includes('auth_bridge.html'));
        assert.ok(redirectUrl.includes('redirect=%2Funit%2F123')); // defaultLink is /unit/123

        // Cleanup
        if (originalCurrentLink) Object.defineProperty(RightsService, 'currentLink', originalCurrentLink);
        if (originalCurrentUnit) Object.defineProperty(RightsService, 'currentUnit', originalCurrentUnit);
    });

    await t.test('should Redirect to Flutter at /unit/123 when AppSupported=true', async () => {
        AppConfig.isAppSupported = true;
        
        global.window.location.pathname = '/unit/123';
        global.window.location.href = 'https://vstupenky.online/unit/123';
        
        let redirectUrl = '';
        global.window.location.replace = (url) => { redirectUrl = url; };

        // Expect it to redirect because /unit/ is in flutterRoutes know
        const handled = await RouterService.handleInitialLoad();
        
        assert.strictEqual(handled, true);
        assert.ok(redirectUrl.includes('auth_bridge.html'));
        assert.ok(redirectUrl.includes('redirect=%2Funit%2F123'));
    });

    await t.test('should sanitize incoming URL with query params on load', async () => {
        AppConfig.isAppSupported = false; // Web Client mode

        global.window.location.pathname = '/form/slug';
        global.window.location.search = '?fbclid=IwAR2...';
        global.window.location.href = 'https://vstupenky.online/form/slug?fbclid=IwAR2...';

        let replacedPath = '';
        global.window.history.replaceState = (_, __, p) => { replacedPath = p; };

        try {
            const handled = await RouterService.handleInitialLoad();
            assert.strictEqual(handled, true); // Handled by Web Client (loading form)
        } catch (e) {
             if (e.code !== 'ERR_UNKNOWN_FILE_EXTENSION' && !e.message.includes('css')) {
                 throw e;
            }
            // Even if it failed to load component (css), it should have sanitized BEFORE loading
        }

        assert.strictEqual(replacedPath, '/form/slug'); // Should receive clean path
    });

    await t.test('should strict hash from URL in handleInitialLoad', async () => {
        // Mock Config
        // Ideally this should be reset/handled but we are appending to the end of the block
        // where AppConfig is already imported.
        // We reused the imports from top of block.
        AppConfig.isAppSupported = false;

        global.window.location.pathname = '/form/slug';
        global.window.location.hash = '#some-setting';
        global.window.location.href = 'https://vstupenky.online/form/slug#some-setting';

        let replacedPath = '';
        global.window.history.replaceState = (_, __, p) => { replacedPath = p; };

        try {
             await RouterService.handleInitialLoad();
        } catch (e) {
             // ignore component load errors
        }

        assert.strictEqual(replacedPath, '/form/slug');
    });

    await t.test('should PRESERVE preview=true query param (skip sanitization)', async () => {
        AppConfig.isAppSupported = false;

        global.window.location.pathname = '/form/slug';
        global.window.location.search = '?preview=true';
        global.window.location.href = 'https://vstupenky.online/form/slug?preview=true';

        let replaceStateCalled = false;
        global.window.history.replaceState = () => { replaceStateCalled = true; };

        try {
             await RouterService.handleInitialLoad();
        } catch (e) {
             // ignore component load errors
        }

        assert.strictEqual(replaceStateCalled, false, 'Should NOT sanitize URL if preview=true is present');
    });

    await t.test('should PRESERVE preview=true even if mixed with other params (skip sanitization)', async () => {
        AppConfig.isAppSupported = false;

        global.window.location.pathname = '/form/slug';
        global.window.location.search = '?preview=true&fbclid=123';
        global.window.location.href = 'https://vstupenky.online/form/slug?preview=true&fbclid=123';

        let replaceStateCalled = false;
        global.window.history.replaceState = () => { replaceStateCalled = true; };

        try {
             await RouterService.handleInitialLoad();
        } catch (e) {
             // ignore component load errors
        }

        assert.strictEqual(replaceStateCalled, false, 'Should NOT sanitize URL if preview=true is present mixed with others');
    });
});
