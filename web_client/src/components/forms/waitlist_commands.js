import { LocalizationService } from '../../services/localization_service.js';
import { SupabaseService } from '../../services/supabase_service.js';

// Capability and payload never enter browser storage, URLs, logs, or sync caches.
export function parseWaitlistLocation(location) {
    if (location.pathname !== '/order' || location.hash) return null;
    const p = new URLSearchParams(location.search);
    if (p.get('waitlist') !== '1') return null;
    const token = p.get('token');
    const offerId = p.get('offer_id');
    const orderId = p.get('order_id');
    if (!p.has('token')) {
        // The marker only selects session-authenticated access. The server
        // still checks the signed-in actor's occasion editor permission.
        if (p.get('admin') === '1' && p.getAll('admin').length === 1 &&
            p.getAll('offer_id').length === 1 && !p.has('order_id') &&
            /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(offerId || '')) {
            return { token: null, offerId };
        }
        throw new Error('INVALID_CAPABILITY');
    }
    if (!/^[a-f0-9]{64}$/i.test(token || '')) throw new Error('INVALID_CAPABILITY');
    if (offerId && /^[a-f0-9-]{36}$/i.test(offerId)) return { token, offerId };
    if (orderId && /^\d+$/.test(orderId)) return { token, orderId: Number(orderId) };
    throw new Error('INVALID_CAPABILITY');
}

export class WaitlistCommands {
    constructor(client) {
        this._client = client;
        this.clientId = crypto.randomUUID();
        this.pending = new Map();
    }
    get client() { return this._client || SupabaseService.getClient(); }
    async read(scope) {
        const { data, error } = await this.client.rpc('get_waitlist_offer_form', {
            p_token: scope.token || null, p_offer_id: scope.offerId || null, p_order_id: scope.orderId || null,
        });
        if (error || data?.code !== 200) throw new Error(data?.errorCode || 'INVALID_CAPABILITY');
        return data;
    }
    async overview(scope) {
        const { data, error } = await this.client.rpc('get_customer_order_overview', { p_token: scope.token, p_order_id: scope.orderId });
        if (error || data?.code !== 200) throw new Error('INVALID_CAPABILITY');
        return data;
    }
    async overviewAccess(scope) {
        const { data, error } = await this.client.functions.invoke('customer-order-access', {
            body: { ...scope, commandId: crypto.randomUUID() },
        });
        if (error || data?.code !== 200 || typeof data.url !== 'string') throw new Error('INVALID_CAPABILITY');
        return data.url;
    }
    async command(operation, payload) {
        return this._invoke('waitlist-commands', { operation, payload });
    }
    async accept(scope, ticketIds, orderDetails) {
        return this._invoke('send-ticket-order', {
            waitlistAcceptance: { ...scope, ticketIds }, orderDetails,
        });
    }
    async _invoke(endpoint, body) {
        const key = JSON.stringify([endpoint, body]);
        const commandId = this.pending.get(key) || crypto.randomUUID();
        this.pending.set(key, commandId);
        const { data, error } = await this.client.functions.invoke(endpoint, {
            body: { ...body, commandId, clientId: this.clientId },
        });
        if (error) throw new Error('WAITLIST_COMMAND_FAILED');
        const result = data?.data || data;
        this.pending.delete(key);
        if (result?.code !== 200) throw Object.assign(new Error(result?.errorCode || 'WAITLIST_COMMAND_FAILED'), { data: result });
        return result;
    }
}

export function waitlistRegistrationPayload(session) {
    const model = session.formModel;
    const payload = { form: model.key, lang: LocalizationService.currentLocale, fields: session.payload.fields, tickets: session.state.tickets.map(t => ({
        fields: (t.fields || []).map(f => {
            const def = session._getTicketSubDef(f._subFieldId);
            return { [f._subFieldId]: f[def?.type] ?? f[f._subFieldId] };
        }),
    })) };
    for (const type of ['email', 'name', 'surname', 'phone']) {
        const field = model.visibleFields.find(f => f.type === type);
        if (field) payload[type] = session.state.fields.get(String(field.id));
    }
    return payload;
}
