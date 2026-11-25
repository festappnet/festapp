import '../connector.dart';

/// Browser link receiver for the organizer's GoPay sandbox checkout.
const goPayPaymentConnector = PaymentConnector(
  id: 'gopay',
  payPath: '/payments/gopay/pay',
  returnPath: '/payments/gopay/return',
  checkoutHost: 'gw.sandbox.gopay.com',
  checkoutTokenPathPrefix: '/gw/v3/',
  currencies: ['CZK'],
);
