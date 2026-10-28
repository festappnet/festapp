import { SupabaseService } from '../../services/supabase_service.js';
import { claimTicketOrderIdentity, terminalOrderResponse } from './ticket_order_identity.js';
import { withCheckoutOrigin } from '../../services/checkout_origin.js';

export class DbOrders {
    static async sendOrder(orderData) {
        orderData = withCheckoutOrigin(orderData);
        const client = SupabaseService.getClient();
        if (!client) throw new Error('Supabase client not initialized');
        const session = await client.auth.getSession();
        if (session.error) throw session.error;
        const intent = await claimTicketOrderIdentity(SupabaseService.endpoint, orderData, session.data?.session?.user?.id);
        // A lost response cannot prove that the server rejected the order.
        // Preserve the pending identity so an in-page retry replays this intent.
        let response;
        try {
            response = await client.functions.invoke('send-ticket-order', {
                body: { orderDetails: intent.orderDetails, commandId: intent.commandId, clientId: intent.clientId },
            });
        } catch {
            return { success: false, code: 503, errorCode: 'ORDER_OUTCOME_UNKNOWN' };
        }
        const { data, error } = response || {};
        if (error || !Number.isInteger(data?.code) || data.code >= 500 && data.code < 1000) {
            return { success: false, code: 503, errorCode: 'ORDER_OUTCOME_UNKNOWN' };
        }
        if (terminalOrderResponse(data)) intent.complete();
        const code = data?.code ?? 503;
        if (code === 200) return { success: true, data };
        return { success: false, code, errorCode: data?.errorCode, message: data?.message || 'Unknown error', product: data?.product };
    }
}
