import { DbOrders } from '../eshop/db_orders.js';

export class FormNetwork {
    
    /**
     * Submits the order payload to the backend.
     * @returns {Promise<{success: boolean, data: any, code: number}>}
     */
    static async submitOrder(payload) {
        try {
            const result = await DbOrders.sendOrder(payload);
            
            let resultData = {};
            if (result.success) {
                resultData = result.data || {};
            } else {
                resultData = { 
                    code: result.code,
                    errorCode: result.errorCode,
                    message: result.message, 
                    product: result.product 
                };
            }

            // Logic: Parse code to int
            const rawCode = resultData.code ? String(resultData.code) : (result.success ? '200' : '0');
            const code = parseInt(rawCode.replace(/\D/g, ''), 10) || 0;
            resultData.code = code;

            const isSuccess = code === 200;

            return {
                success: isSuccess,
                data: resultData
            };

        } catch (e) {
            console.error("FormNetwork Submit Error:", e);
            throw e; 
        }
    }
}
