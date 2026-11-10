import {bankPaymentConnector, cashPaymentConnector} from './connectors/builtin.js';
import {barionPaymentConnector} from './connectors/barion.js';
import {stripePaymentConnector} from './connectors/stripe.js';

/** Composition root. Register a connector here rather than branching in views. */
export class PaymentConnectorRegistry {
    #connectors = new Map();
    constructor(connectors) {
        for (const connector of connectors) {
            if (!/^[a-z][a-z0-9_-]{0,31}$/.test(connector.id) || this.#connectors.has(connector.id) ||
                typeof connector.quote !== 'function' || typeof connector.availability !== 'function')
                throw new Error('payment_connector_registration_invalid');
            this.#connectors.set(connector.id, Object.freeze({...connector, hostedCheckout: typeof connector.validateCheckoutUrl === 'function' ? Object.freeze({payPath: connector.payPath, returnPath: connector.returnPath, validateCheckoutUrl: connector.validateCheckoutUrl}) : null}));
        }
    }
    get(id) { return this.#connectors.get(id) ?? null; }
    values() { return [...this.#connectors.values()]; }
}
export const paymentConnectors = new PaymentConnectorRegistry([bankPaymentConnector, cashPaymentConnector, stripePaymentConnector, barionPaymentConnector]);
export const isCardPaymentMethod = method => paymentConnectors.get(method)?.hostedCheckout != null;
