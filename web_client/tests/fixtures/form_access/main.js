// Only backend transport and the final Flutter handoff are simulated. The HTML
// shell, Main startup, routing, rights interpretation and all visible UI are real.
import { AppConfig } from '../../../src/app_config.js';
import { SupabaseService } from '../../../src/services/supabase_service.js';
import { RouterService } from '../../../src/services/router_service.js';
const scenario = new URLSearchParams(location.search).get('scenario');
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
await import('../../../src/main.js');
// Dynamic import completes after the browser's initial DOMContentLoaded.
document.dispatchEvent(new Event('DOMContentLoaded'));
