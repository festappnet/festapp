import { FeatureService } from '../features/feature_service.js';
import { LocalizationService } from '../../services/localization_service.js';

/** Reusable UI copy; feature scope is passed by the owning form/order/page. */
export class OrderItemStrings {
    static text(key, { features, hasTickets = FeatureService.usesTicketTerminology(features), args = {}, fallback = key } = {}) {
        if (!hasTickets) {
            const application = LocalizationService.tr(`ApplicationTerminology.${key}`, args, null);
            if (typeof application === 'string') return application;
        }
        return LocalizationService.tr(key, args, fallback);
    }

    static singular(features) {
        return this.text('FeatureOrders.ticket', { features });
    }

    static plural(features) {
        return this.text('FeatureOrders.tickets', { features });
    }

    static isDefaultLabel(value) {
        return ['Tickets', 'Ticket', ...['ticket', 'tickets', 'application', 'applications']
            .map(key => LocalizationService.tr(`FeatureOrders.${key}`))].includes(value);
    }
}
