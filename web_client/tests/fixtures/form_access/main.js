// Only backend transport and the final Flutter handoff are simulated. The HTML
// shell, Main startup, routing, rights interpretation and all visible UI are real.
import { AppConfig } from '../../../src/app_config.js';
import { SupabaseService } from '../../../src/services/supabase_service.js';
import { RouterService } from '../../../src/services/router_service.js';
const scenario = new URLSearchParams(location.search).get('scenario') || sessionStorage.getItem('fixtureUpdateScenario');
AppConfig.isAppSupported = false;
AppConfig.organization = 3;
AppConfig.forceOccasionLink = null;
SupabaseService._backend = { supabaseUrl: location.origin };
async function request(name, args) {
    return (await fetch('/__form_access_rpc', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, args, scenario }),
    })).json();
}
const client = {
    auth: { getSession: async () => ({ data: { session: null }, error: null }) },
    rpc(name, args) { const response = request(name, args); response.abortSignal = () => response; return response; },
    functions: { invoke: (name, { body }) => request(name, body) },
};
SupabaseService.initialize = async () => { SupabaseService._client = client; };
RouterService.navigateToFlutterRoute = async path => { window.__adminDestination = path; };
if (scenario?.startsWith('embed-')) {
    const readyAtFocus = window.__FESTAPP_APP_READY__ === true;
    window.addEventListener('message', async event => {
        if (event.data === 'fixture-inspect-update') {
            event.source.postMessage({fixtureUpdateReport:{inspection:true,
                banner:!!document.getElementById('festapp-update-banner'),
                draft:document.querySelector('input[type=email]')?.value}}, event.origin);
            return;
        }
        if (event.data === 'fixture-start-update') {
            window.__fixtureReleaseVersion?.();
            window.dispatchEvent(new Event('focus'));
            return;
        }
        if (event.data === 'fixture-release-worker') {
            (await navigator.serviceWorker.ready).active.postMessage('fixture-release-worker');
            return;
        }
        if (event.data === 'fixture-check-validation') {
            const shown = [...document.querySelectorAll('.form-field-error')]
                .some(el => {
                    const rect = el.getBoundingClientRect();
                    if (!el.textContent.trim() || rect.width <= 0 || rect.height <= 0) return false;
                    for (let node = el; node; node = node.parentElement) {
                        const style = getComputedStyle(node);
                        if (style.display === 'none' || style.visibility === 'hidden') return false;
                    }
                    return true;
                });
            event.source.postMessage({fixtureUpdateReport:{validationShown:shown}}, event.origin);
            return;
        }
        if (event.data !== 'fixture-check-update') return;
        const versionWasPending = window.__fixtureVersionPending === true;
        window.__fixtureReleaseVersion?.();
        window.dispatchEvent(new Event('focus'));
        document.dispatchEvent(new Event('visibilitychange'));
        window.dispatchEvent(new CustomEvent('festapp-update-available', {detail:{version:'new'}}));
        setTimeout(() => event.source.postMessage({fixtureUpdateReport:{ready:window.__FESTAPP_APP_READY__, readyAtFocus, versionWasPending, draft:document.querySelector('input[type=email]')?.value, banner:!!document.getElementById('festapp-update-banner')}}, event.origin), 100);
    });
    window.dispatchEvent(new Event('focus'));
    await new Promise(resolve => setTimeout(resolve, 500));
}
await import('../../../src/main.js');
// Dynamic import completes after the browser's initial DOMContentLoaded.
document.dispatchEvent(new Event('DOMContentLoaded'));
