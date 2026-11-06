import '../connector.dart';

const stripePaymentConnector = PaymentConnector(
  id: 'stripe',
  payPath: '/stripe/pay',
  returnPath: '/stripe/return',
  checkoutHost: 'checkout.stripe.com',
  orderConnectionField: 'stripe_connection_id',
  unavailableReasonField: 'stripeUnavailableReason',
  legacyAvailability: true,
  labelKey: 'stripe',
  hintKey: 'stripeHint',
  authorizationHost: 'connect.stripe.com',
  authorizationPath: '/oauth/authorize',
  callbackEndpoint: 'stripe-connect-callback',
);
