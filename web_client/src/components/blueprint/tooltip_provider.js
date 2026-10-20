
import { formatPrice } from '../../utils/formatters.js';
import { CommonStrings } from '../shared/common_strings.js';
import { LocalizationService } from '../../services/localization_service.js';

export class TooltipProvider {
    /**
     * Generates tooltip content for a seat object.
     * @param {Object} obj - The seat object.
     * @param {Object} context - Data context containing maps and raw data.
     * @param {Map} context.productsMap
     * @param {Map} context.ticketsMap
     * @param {Map} context.ordersMap
     * @param {Map} context.optMap
     * @param {Object} context.data - The full blueprint data object.
     * @returns {string|null} The tooltip text or null if no content.
     */
    static getContent(obj, context) {
         // Based on BlueprintObjectModel.blueprintTooltip logic (Flutter)
        
        // 1. Resolve Product
        // Normalized: obj.product should hold the correct ID after enrichment
        let productId = obj.product; 
        
        // Lookup using String ID
        const product = (context.productsMap && productId) ? context.productsMap.get(String(productId)) : null;
        
        const productTitle = product ? product.title : '';
        const seatTitle = obj.title || '';
        const seatPrice = product ? product.price : 0; 
        
        // Helper: Render Order Customer Data (mimic OrderModel.toCustomerData)
        const getCustomerData = (order) => {
            const data = order.data || {};
            const name = data.name;
            const surname = data.surname;
            const email = data.email;

            const hasName = name && name.trim().length > 0;
            const hasSurname = surname && surname.trim().length > 0;

            if (hasName || hasSurname) {
                const parts = [];
                if (hasName) parts.push(name);
                if (hasSurname) parts.push(surname);
                return parts.join(" ");
            } else {
                 if (email && email.trim().length > 0) return email;
            }
            return "";
        };

        // 2. Check for Order (Ordered Seat)
        if (obj.order_product_ticket) {
            const opt = context.optMap ? context.optMap.get(obj.order_product_ticket) : null;
            
            if (opt) {
                const ticket = context.ticketsMap ? context.ticketsMap.get(opt.ticket) : null; // opt.ticket is ticket ID
                
                if (ticket) {
                    // Find other products in the same ticket (bundle)
                    let productsString = "";
                    if (context.data.order_product_ticket && context.data.products) {
                         // Find all OPTs with same ticketId
                         const otherOPTs = context.data.order_product_ticket.filter(o => o.ticket === ticket.id);
                         
                         // Map to Product IDs
                         const otherProductIds = otherOPTs.map(o => o.product);
                         
                         // Filter out current product and map to titles
                         const otherProductTitles = otherProductIds
                            .filter(id => id !== productId)
                            .map(id => context.productsMap.get(id)?.title)
                            .filter(Boolean);
                            
                         if (otherProductTitles.length > 0) {
                             productsString = otherProductTitles.join("\n");
                         }
                    }
                    
                    // Order Details
                    const order = context.ordersMap ? context.ordersMap.get(opt.order) : null; // opt.order is order ID
                    let orderString = "";
                    if (order) {
                         const customerData = getCustomerData(order);
                         const orderNote = (order.data && order.data.note) ? `\n${order.data.note}` : "";
                         orderString = `\n${customerData}${orderNote}`;
                    }

                    const ticketNote = (ticket.note && ticket.note.trim().length > 0) ? `\n${ticket.note}` : "";
                    const ticketSymbol = ticket.ticket_symbol || "";
                    
                    const itemSingular = CommonStrings.itemSingular || "Item"; // Fallback
                    
                    let tooltip = `${productTitle} ${seatTitle}\n${itemSingular} ${ticketSymbol}${ticketNote}`;
                    
                    if (productsString) tooltip += `\n${productsString}`;
                    if (orderString) tooltip += `${orderString}`; 
                    
                    return tooltip;
                }
            }
        }
        
        // Fallback / Available
        const priceLabel = CommonStrings.price || "Price";
        
        // Use shared utility for inconsistent currency display
        // User requested whole numbers (0 decimals)
        const currencyCode = product?.currency_code || 'CZK';
        const priceFormatted = formatPrice(seatPrice, currencyCode, 0, LocalizationService.currentLocale);
        
        if (productTitle && seatTitle) {
             return `${productTitle} ${seatTitle}\n${priceLabel}: ${priceFormatted}`;
        } else if (productTitle) {
             return `${productTitle}\n${priceLabel}: ${priceFormatted}`;
        }
        
        return `${seatTitle}\n${priceLabel}: ${priceFormatted}`;
    }
}
