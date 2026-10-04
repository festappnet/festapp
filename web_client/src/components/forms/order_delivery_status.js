import { SupabaseService } from '../../services/supabase_service.js';
/** List-scoped bounded observation, no order creation or resend. */
export function observeOrderDelivery(capability, onState, {invoke, visible, alive, delay, now} = {}) {
    invoke ??= token => SupabaseService.getEmailConfirmationStatus(token);
    visible ??= () => document.visibilityState !== 'hidden';
    alive ??= () => true;
    delay ??= ms => new Promise(resolve => setTimeout(resolve, ms));
    now ??= Date.now;
    let stopped = false;
    let lastState;
    const started = now();
    const done = (async () => {
        if (!capability) return;
        for (let attempt = 0; attempt < 5 && !stopped && now() - started < 15000; attempt++) {
            if (!visible() || !alive()) break;
            try {
                const result = await invoke(capability);
                if (stopped || !alive()) break;
                if (result?.state === 'accepted' && lastState !== 'accepted') { onState('accepted'); lastState = 'accepted'; }
                if (['delivered', 'invalid_email', 'failed', 'unknown', 'dead', 'suppressed', 'expired', 'cancelled', 'retry_wait'].includes(result?.state)) {
                    onState(result.state);
                    break;
                }
            } catch { break; }
            if (attempt < 4) await delay(2500);
        }
    })();
    return { stop: () => { stopped = true; }, done };
}
