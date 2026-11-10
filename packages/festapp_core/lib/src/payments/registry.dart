import 'connector.dart';
import 'connectors/stripe.dart';
import 'connectors/barion.dart';

class PaymentConnectorRegistry {
  PaymentConnectorRegistry(Iterable<PaymentConnector> connectors) {
    for (final connector in connectors) {
      if (!RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(connector.id) ||
          _connectors.containsKey(connector.id)) {
        throw StateError('payment_connector_registration_invalid');
      }
      _connectors[connector.id] = connector;
    }
  }
  final _connectors = <String, PaymentConnector>{};
  PaymentConnector? get(dynamic id) => _connectors[id];
  PaymentConnector? getHosted(dynamic id) => containsHosted(id) ? get(id) : null;
  bool containsHosted(dynamic id) => get(id)?.hostedCheckout != null;
  Iterable<PaymentConnector> get hosted => values.where((c) => c.hostedCheckout != null);
  bool contains(dynamic id) => get(id) != null;
  Iterable<PaymentConnector> get values => _connectors.values;
}

/// Composition root. Domain views select a connector from the server projection.
final paymentConnectors = PaymentConnectorRegistry([
  const PaymentConnector(id: 'bank', labelKey: 'bank', hintKey: 'bankHint', confirmation: PaymentConfirmation.bankEvent,
    currencies: ['CZK', 'EUR', 'USD']),
  const PaymentConnector(id: 'cash', labelKey: 'cash', hintKey: 'cashHint', confirmation: PaymentConfirmation.localCommit),
  stripePaymentConnector, barionPaymentConnector,
]);
