import { test, describe, beforeEach } from 'node:test';
import assert from 'node:assert';
import { JSDOM } from 'jsdom';
import { readFileSync } from 'fs';
import { resolve } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const AUTH_BRIDGE_HTML = readFileSync(
    resolve(__dirname, '../../public/auth_bridge.html'),
    'utf-8'
);
const SUPABASE_KEY = AUTH_BRIDGE_HTML.match(
    /const SUPABASE_KEY = '([^']+)'/
)?.[1];

assert.ok(SUPABASE_KEY, 'auth bridge must declare its Supabase storage key');

/**
 * Helper: create a JSDOM instance with the auth_bridge.html loaded,
 * injecting a custom URL (hash, query) and stubbing navigation.
 */
function createBridge({ hash = '', search = '', hostname = 'example.com', localStorage = {} } = {}) {
    const url = `https://${hostname}/auth_bridge.html${search}${hash}`;
    const dom = new JSDOM(AUTH_BRIDGE_HTML, {
        url,
        runScripts: 'dangerously',
        resources: 'usable',
        beforeParse(window) {
            // Stub location.replace so we can capture the redirect URL
            window._redirectedTo = null;
            const originalLocation = window.location;

            // We can't easily override location.replace in JSDOM,
            // so we'll capture it via setTimeout interception
            window._timeouts = [];
            const origSetTimeout = window.setTimeout;
            window.setTimeout = (fn, ms) => {
                window._timeouts.push({ fn, ms });
            };

            // Seed localStorage
            for (const [key, value] of Object.entries(localStorage)) {
                window.localStorage.setItem(key, value);
            }
        }
    });

    return dom;
}

describe('auth_bridge.html', () => {
    test('tokens from hash are stored in sessionStorage, not in redirect URL', () => {
        const hash = '#access_token=test_at&refresh_token=test_rt&token_type=bearer&type=recovery';
        const dom = createBridge({ hash });
        const { window } = dom;

        // Check sessionStorage
        const handoff = window.sessionStorage.getItem('_auth_handoff');
        assert.ok(handoff, 'sessionStorage._auth_handoff should be set');

        const parsed = JSON.parse(handoff);
        assert.strictEqual(parsed.access_token, 'test_at');
        assert.strictEqual(parsed.refresh_token, 'test_rt');
        assert.strictEqual(parsed.token_type, 'bearer');
        assert.strictEqual(parsed.type, 'recovery');

        // Check that the redirect URL does NOT contain tokens
        const manualLink = window.document.getElementById('manual-link');
        const href = manualLink.getAttribute('href');
        assert.ok(!href.includes('access_token'), `URL should not contain access_token, got: ${href}`);
        assert.ok(!href.includes('refresh_token'), `URL should not contain refresh_token, got: ${href}`);

        dom.window.close();
    });

    test('redirect param is preserved as query param', () => {
        const hash = '#access_token=test_at&refresh_token=test_rt';
        const search = '?redirect=%2Fdashboard';
        const dom = createBridge({ hash, search });
        const { window } = dom;

        const manualLink = window.document.getElementById('manual-link');
        const href = manualLink.getAttribute('href');
        assert.ok(href.includes('redirect='), `URL should contain redirect param, got: ${href}`);
        assert.ok(href.includes('%2Fdashboard'), `URL should contain encoded redirect path, got: ${href}`);
        // Still no tokens in URL
        assert.ok(!href.includes('access_token'), `URL should not contain access_token, got: ${href}`);

        dom.window.close();
    });

    test('localStorage fallback stores tokens in sessionStorage', () => {
        const sessionData = JSON.stringify({
            access_token: 'ls_at',
            refresh_token: 'ls_rt'
        });
        const dom = createBridge({
            localStorage: { [SUPABASE_KEY]: sessionData }
        });
        const { window } = dom;

        const handoff = window.sessionStorage.getItem('_auth_handoff');
        assert.ok(handoff, 'sessionStorage._auth_handoff should be set from localStorage fallback');

        const parsed = JSON.parse(handoff);
        assert.strictEqual(parsed.access_token, 'ls_at');
        assert.strictEqual(parsed.refresh_token, 'ls_rt');

        // URL should not contain tokens
        const manualLink = window.document.getElementById('manual-link');
        const href = manualLink.getAttribute('href');
        assert.ok(!href.includes('access_token'), `URL should not contain access_token, got: ${href}`);

        dom.window.close();
    });

    test('redirect param from hash fragment is preserved', () => {
        const hash = '#access_token=test_at&refresh_token=test_rt&redirect=%2Fprofile';
        const dom = createBridge({ hash });
        const { window } = dom;

        const manualLink = window.document.getElementById('manual-link');
        const href = manualLink.getAttribute('href');
        assert.ok(href.includes('redirect='), `URL should contain redirect from hash, got: ${href}`);
        assert.ok(!href.includes('access_token'), `URL should not contain access_token, got: ${href}`);

        dom.window.close();
    });
});
