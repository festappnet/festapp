import { browserStorage } from '../../services/browser_storage.js';
import { SupabaseService } from '../../services/supabase_service.js';

export class DbOrders {
    
    static async sendOrder(orderData) {
        const client = SupabaseService.getClient();
        if (!client) throw new Error("Supabase client not initialized");

        // Calls the Supabase Edge Function "send-ticket-order"
        // Flutter: final edgeResponse = await _supabase.functions.invoke("send-ticket-order", body: {"orderDetails": orderDetails});
        const clientIdKey = 'client_command_client_id';
        let clientId = browserStorage.getItem(clientIdKey);
        if (!clientId) {
            clientId = crypto.randomUUID();
            browserStorage.setItem(clientIdKey, clientId);
        }
        const pendingKey = 'client_command_pending:ticket_order';
        const serializedOrder = JSON.stringify(orderData);
        const pending = JSON.parse(browserStorage.getItem(pendingKey) || 'null');
        const commandId = pending?.payload === serializedOrder
            ? pending.commandId
            : crypto.randomUUID();
        browserStorage.setItem(pendingKey, JSON.stringify({
            payload: serializedOrder,
            commandId,
        }));
        const { data, error } = await client.functions.invoke('send-ticket-order', {
            body: {
                orderDetails: orderData,
                commandId,
                clientId,
            }
        });

        if (error) {
            console.error("Error sending order:", error);
            return { success: false, message: error.message };
        }
        browserStorage.removeItem(pendingKey);

        // Edge Functions return data directly in `data` (if successful HTTP status), 
        // but sometimes we wrap it. 
        // Flutter checks: if (edgeResponse.status != 200) ...
        // JS Client `invoke` resolves to { data, error }. 
        // The `data` property contains the JSON response body.
        
        // Check if the response body contains our standard { code, message, ... } structure
        const responseCode = data?.code || 200; // Assume 200 if not specified in body but no error? 
        // Actually, if the function returns JSON, `data` IS that JSON.
        
        if (responseCode === 200) {
            return { success: true, data: data };
        } else {
             return { success: false, code: responseCode, message: data?.message || "Unknown error", product: data?.product };
        }
    }
}
