import '../connector.dart';

/// Sandbox-only. Server policy keeps this unavailable for public sales.
const barionPaymentConnector = PaymentConnector(
  id: 'barion',
  payPath: '/payments/barion/pay',
  returnPath: '/payments/barion/return',
  checkoutHost: 'secure.test.barion.com',
  checkoutPath: '/pay',
  checkoutGuidParameter: 'id',
);
