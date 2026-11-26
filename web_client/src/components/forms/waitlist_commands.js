import {canonicalCommandPayload,terminalOrderResponse} from '../eshop/ticket_order_identity.js';
import { LocalizationService } from '../../services/localization_service.js';
import { SupabaseService } from '../../services/supabase_service.js';
import { randomUuid } from '../../utils/random_uuid.js';

export {parseWaitlistLocation} from './customer_order_location.js';

export class WaitlistCommands {
    constructor(client) {
        this._client = client;
        this.clientId = randomUuid();
        this.pending = new Map();
    }
    get client() { return this._client || SupabaseService.getClient(); }
    clientFor(scope) {
        if (this._client) return this._client;
        return scope?.token && scope.admin !== true ? SupabaseService.getGuestClient() : this.client;
    }
    async read(scope) {
        const { data, error } = await this.clientFor(scope).rpc('get_waitlist_offer_form', {
            p_token: scope.token || null, p_offer_id: scope.offerId || null, p_order_id: scope.orderId || null,
        });
        if (error || data?.code !== 200) throw new Error(data?.errorCode || 'INVALID_CAPABILITY');
        return data;
    }
    async overview(scope) {
        const { data, error } = await this.clientFor(scope).rpc('get_customer_order_overview', { input_data: {token: scope.token, order_id: scope.orderId, client_capabilities:['cash_reservations','no_payment_deadline']} });
        if (error) throw new Error('OVERVIEW_LOAD_FAILED');
        if ([403, 404, 410].includes(data?.code)) throw new Error('OVERVIEW_UNAVAILABLE');
        if (data?.code !== 200) throw new Error('OVERVIEW_LOAD_FAILED');
        return data;
    }
    async downloadTicket(scope, ticketId) {
        const { data, error } = await this.clientFor(scope).functions.invoke('download-ticket', {
            body: { token: scope.token, orderId: scope.orderId, ticketId },
        });
        if (error || typeof data?.file !== 'string' || !data.file) throw new Error('TICKET_DOWNLOAD_FAILED');
        return data.file;
    }
    async overviewAccess(scope) {
        const { data, error } = await this.clientFor(scope).functions.invoke('customer-order-access', {
            body: { ...scope, commandId: randomUuid() },
        });
        if (error || data?.code !== 200 || typeof data.url !== 'string') throw new Error('INVALID_CAPABILITY');
        return data.url;
    }
    async command(operation, payload) {
        const scope = operation === 'decline' || operation === 'withdraw' ? payload : null;
        return this._invoke('waitlist-commands', { operation, payload }, {}, scope);
    }
    async accept(scope, ticketIds, orderDetails, options = {}) {
        return this._invoke('send-ticket-order', {
            waitlistAcceptance: { ...scope, ticketIds }, orderDetails,
        }, options, scope);
    }
    async _invoke(endpoint, body, {reusePendingOnly = false} = {}, scope) {
        const key = JSON.stringify(canonicalCommandPayload([endpoint, body]));
        if (reusePendingOnly && !this.pending.has(key)) throw Object.assign(new Error('PAYMENT_RECOVERY_REQUIRED'), {data:{code:409,errorCode:'ORDER_RECOVERY_REQUIRED'}});
        const commandId = this.pending.get(key) || randomUuid();
        this.pending.set(key, commandId);
        const { data, error } = await this.clientFor(scope).functions.invoke(endpoint, {
            body: { ...body, commandId, clientId: this.clientId },
        });
        if (error) throw new Error('WAITLIST_COMMAND_FAILED');
        const result = data?.data || data;
        if (terminalOrderResponse(result)) this.pending.delete(key);
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
