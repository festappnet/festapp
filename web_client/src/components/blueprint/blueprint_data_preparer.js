import { BlueprintConfig, SeatStates } from './blueprint_config.js';

export class BlueprintDataPreparer {
    /**
     * Prepares the raw blueprint data for rendering.
     * Enriches objects with product/ticket info and calculates dimensions.
     * @param {Object} data - Raw blueprint data from API
     * @returns {Object} preparedData - Enriched data and metadata
     */
    static prepare(data) {
        if (!data) return null;

        const result = {
            ...data,
            meta: {
                productsMap: new Map(),
                ticketsMap: new Map(),
                ordersMap: new Map(),
                optMap: new Map(),
                productToOptMap: new Map(),
                spotsMap: new Map(),
                cols: 0,
                rows: 0,
                seatSize: BlueprintConfig.seatSize,
                contentWidth: 0,
                contentHeight: 0
            }
        };

        // 1. Build Lookup Maps
        if (data.products) {
            data.products.forEach(p => result.meta.productsMap.set(String(p.id), p));
        }
        if (data.tickets) {
            data.tickets.forEach(t => result.meta.ticketsMap.set(String(t.id), t));
        }
        if (data.orders) {
            data.orders.forEach(o => result.meta.ordersMap.set(String(o.id), o));
        }
        
        if (data.order_product_ticket) {
            data.order_product_ticket.forEach(opt => {
                const optId = String(opt.id);
                result.meta.optMap.set(optId, opt);
                if (opt.product) {
                    result.meta.productToOptMap.set(String(opt.product), opt);
                }
            });
        }
        
        if (data.spots) {
            data.spots.forEach(s => result.meta.spotsMap.set(String(s.id), s));
        }

        // 2. Enrich Objects
        if (data.objects) {
            data.objects.forEach(obj => {
                const spot = result.meta.spotsMap.get(String(obj.id));
                if (spot) {
                    // Merge vital info
                    if (!obj.title) obj.title = spot.title;
                    
                    // Link product
                    if (spot.product) {
                        obj.product = spot.product;
                        obj.productModel = result.meta.productsMap.get(String(spot.product));
                    } else if (spot.spot_product) {
                        obj.product = spot.spot_product;
                        obj.productModel = result.meta.productsMap.get(String(spot.spot_product));
                    }
                    
                    // Link Order
                    if (!obj.order_product_ticket) {
                        if (spot.order_product_ticket) {
                            obj.order_product_ticket = spot.order_product_ticket;
                        } else if (obj.product) {
                            const opt = result.meta.productToOptMap.get(String(obj.product));
                            if (opt) {
                                obj.order_product_ticket = opt.id;
                                obj.state = SeatStates.ORDERED; 
                            }
                        }
                    }
                    // Sync State
                    if (spot.state) obj.state = spot.state;
                }
            });
        }

        // 3. Dimensions
        if (data.configuration && data.configuration.dimensions) {
            result.meta.cols = data.configuration.dimensions.width;
            result.meta.rows = data.configuration.dimensions.height;
        } else if (data.objects) {
             data.objects.forEach(obj => {
                if (obj.x !== undefined && (obj.x + 1) > result.meta.cols) result.meta.cols = obj.x + 1;
                if (obj.y !== undefined && (obj.y + 1) > result.meta.rows) result.meta.rows = obj.y + 1;
            });
        }

        result.meta.contentWidth = result.meta.cols * result.meta.seatSize;
        result.meta.contentHeight = result.meta.rows * result.meta.seatSize;

        return result;
    }
}
