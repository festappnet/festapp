import { SupabaseService } from '../../services/supabase_service.js';
import { claimTicketOrderIdentity, terminalOrderResponse } from './ticket_order_identity.js';

export class DbOrders {
    static async sendOrder(orderData) {
        const client = SupabaseService.getClient();
        if (!client) throw new Error('Supabase client not initialized');
        const session = await client.auth.getSession();
        if (session.error) throw session.error;
        const intent = await claimTicketOrderIdentity(SupabaseService.endpoint, orderData, session.data?.session?.user?.id);
        const { data, error } = await client.functions.invoke('send-ticket-order', {
            body: { orderDetails: orderData, commandId: intent.commandId, clientId: intent.clientId },
        });
        if (error) return { success: false, message: error.message };
        if (terminalOrderResponse(data)) intent.complete();
        const code = data?.code ?? 503;
        if (code === 200) return { success: true, data };
        return { success: false, code, errorCode: data?.errorCode, message: data?.message || 'Unknown error', product: data?.product };
    }
}
