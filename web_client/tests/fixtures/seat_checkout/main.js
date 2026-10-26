import { FormPage } from '../../../src/components/forms/form_page.js';
import { SupabaseService } from '../../../src/services/supabase_service.js';
import { LocalizationService } from '../../../src/services/localization_service.js';
import { RightsService } from '../../../src/services/rights_service.js';
import '../../../src/theme_config.css';

// Only transport and unrelated administrator discovery are test adapters.
// Form rendering, seat gestures, state, payload, preview and result are real.
window.__seatCheckoutRpcResults = new Map();
async function request(name, args) {
    const response = await fetch('/__seat_checkout_rpc', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, args }),
    });
    const result = await response.json();
    window.__seatCheckoutRpcResults.set(name, result);
    return result;
}
SupabaseService._backend = { supabaseUrl: location.origin };
SupabaseService.getClient = () => ({
    auth: { getSession: async () => ({ data: { session: null }, error: null }) },
    rpc(name, args) {
        const result = request(name, args);
        result.abortSignal = () => result;
        return result;
    },
    functions: { invoke: (name, { body }) => request(name, body) },
});
RightsService.updateAppData = async () => {};
RightsService.canSeeReservations = () => false;
LocalizationService.currentLocale = 'cs';
await LocalizationService.loadTranslations('cs');
await new FormPage('form-page-container').init('seat-checkout-regression');
