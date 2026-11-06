import 'package:festapp_core/payments.dart';
import 'package:festapp_core/forms.dart';
import 'package:test/test.dart';

void main() {
  const connector = PaymentConnector(
    id: 'other_gateway',
    payPath: '/payments/pay',
    returnPath: '/payments/return',
    checkoutHost: 'pay.example',
  );
  test('Barion sandbox redirect rejects live host, duplicate scope and arbitrary paths', () {
    expect(paymentConnectors.contains('barion'), isTrue);
    expect(barionPaymentConnector.checkoutUri('https://secure.test.barion.com/Pay?Id=${'a' * 32}').host, 'secure.test.barion.com');
    for (final url in [
      'https://secure.barion.com/Pay?Id=${'a' * 32}',
      'https://secure.test.barion.com/Other?Id=${'a' * 32}',
      'https://secure.test.barion.com/Pay?Id=${'a' * 32}&id=${'b' * 32}',
      'https://secure.test.barion.com/Pay?Id=${'a' * 32}#token',
    ]) {
      expect(() => barionPaymentConnector.checkoutUri(url), throwsStateError);
    }
    expect(stripePaymentConnector.checkoutUri('https://checkout.stripe.com/c/pay/cs_fixture').host, 'checkout.stripe.com');
  });
  test(
    'another provider has its own checkout policy and isolated availability',
    () {
      final registry = PaymentConnectorRegistry([connector]);
      expect(registry.contains('stripe'), isFalse);
      expect(
        connector.checkoutUri('https://pay.example/42').host,
        'pay.example',
      );
      expect(
        () => connector.checkoutUri('https://checkout.stripe.com/42'),
        throwsStateError,
      );
      expect(
        () => connector.checkoutUri('https://evil@pay.example/42'),
        throwsStateError,
      );
      final options = FormPaymentOptions.fromJson({
        'available': ['bank', 'other_gateway', 'uninstalled'],
        'providers': {
          'other_gateway': {
            'configured': true,
            'available': true,
            'recipient': {
              'connectionId': '12345678-1234-4234-8234-123456789abc',
            },
            'supportedSurfaces': ['web'],
          },
        },
      }, registry: registry);
      expect(options.availableFor('web'), ['bank', 'other_gateway']);
      expect(options.availableFor('embed'), ['bank']);
      expect(options.cardConfigured, isTrue);
    },
  );
  test(
    'a registry rejects duplicate providers and unknown providers never resolve',
    () {
      expect(
        () => PaymentConnectorRegistry([connector, connector]),
        throwsStateError,
      );
      expect(PaymentConnectorRegistry([connector]).get('uninstalled'), isNull);
    },
  );
}
