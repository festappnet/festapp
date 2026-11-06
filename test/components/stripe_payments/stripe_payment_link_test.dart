import 'package:festapp_core/payments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/payments/payment_link_service.dart';

void main() {
  const origin = 'https://tickets.example';
  final pay = 'a' * 64, read = 'b' * 64;
  PaymentLinkInbox inbox() => PaymentLinkInbox(Uri.parse(origin));

  test('initial payment and alias capture returns only sanitized route and consumes once', () {
    for (final path in ['/stripe/pay', '/app/stripe/pay']) {
      final links = inbox();
      expect(links.capture(Uri.parse('$origin$path#pay=$pay')), isTrue);
      expect(links.pendingRoute, '/stripe/pay');
      expect(links.consume(expectedKind: 'return'), isNull);
      expect(links.consume(expectedKind: 'pay'), {
        'provider': 'stripe',
        'kind': 'pay',
        'token': pay,
      });
      expect(links.consume(), isNull);
      expect(links.pendingRoute, isNull);
      // Reopening an emailed capability after leaving the page is valid.
      expect(links.capture(Uri.parse('$origin$path#pay=$pay')), isTrue);
      expect(links.consume(), {
        'provider': 'stripe',
        'kind': 'pay',
        'token': pay,
      });
    }
  });
  test(
    'return has read scope and never becomes payment on initial or resume',
    () {
      for (final path in ['/stripe/return', '/app/stripe/return']) {
        final links = inbox();
        expect(
          links.capture(Uri.parse('$origin$path?return_handle=$read')),
          isTrue,
        );
        expect(links.pendingRoute, '/stripe/return');
        expect(links.consume(expectedKind: 'pay'), isNull);
        expect(links.consume(expectedKind: 'return'), {
          'provider': 'stripe',
          'kind': 'return',
          'token': read,
        });
        expect(links.capture(Uri.parse('$origin/stripe/pay#pay=$pay')), isTrue);
        expect(links.consume(), {
          'provider': 'stripe',
          'kind': 'pay',
          'token': pay,
        });
      }
    },
  );
  test('foreign, malformed, mixed-scope and handoff links cannot replace a pending capability', () {
    final links = inbox();
    expect(links.capture(Uri.parse('$origin/stripe/pay#pay=$pay')), isTrue);
    for (final value in [
      'http://tickets.example/stripe/pay#pay=$read',
      'https://other.example/stripe/pay#pay=$read',
      'https://tickets.example:444/stripe/pay#pay=$read',
      'https://user@tickets.example/stripe/pay#pay=$read',
      '$origin/unowned/stripe/pay#pay=$read',
      '$origin/stripe/pay/#pay=$read',
      '$origin/stripe/pay#handoff=$read',
      '$origin/stripe/pay?pay=$read',
      '$origin/stripe/pay?return_handle=$read#pay=$read',
      '$origin/stripe/pay#pay=$read&pay=$pay',
      '$origin/stripe/return#pay=$read',
      '$origin/stripe/return?return_handle=$read#pay=$pay',
      '$origin/stripe/return?return_handle=$read&return_handle=$pay',
      '$origin/stripe/return?return_handle=short',
      '$origin/app/google-auth?google_code=$read',
    ]) {
      expect(
        links.capture(Uri.parse(value)),
        isFalse,
        reason: 'Reject invalid link shape',
      );
    }
    expect(links.consume(), {
      'provider': 'stripe',
      'kind': 'pay',
      'token': pay,
    });
  });
  test(
    'pending duplicates coalesce but a consumed return link can be reopened',
    () {
      final links = inbox();
      links.capture(Uri.parse('$origin/stripe/pay#pay=$pay'));
      links.capture(Uri.parse('$origin/stripe/return?return_handle=$read'));
      final alias = Uri.parse('$origin/app/stripe/return?return_handle=$read');
      expect(links.capture(alias), isFalse);
      expect(links.consume(), {
        'provider': 'stripe',
        'kind': 'return',
        'token': read,
      });
      expect(links.capture(alias), isTrue);
      expect(links.consume(), {
        'provider': 'stripe',
        'kind': 'return',
        'token': read,
      });
      expect(links.consume(), isNull);
    },
  );
  test(
    'another connector captures a generic link without crossing provider scope',
    () {
      const connector = PaymentConnector(
        id: 'other_gateway',
        payPath: '/payments/other_gateway/pay',
        returnPath: '/payments/other_gateway/return',
        checkoutHost: 'pay.example',
      );
      final links = PaymentLinkInbox(
        Uri.parse(origin),
        registry: PaymentConnectorRegistry([connector]),
      );
      expect(
        links.capture(Uri.parse('$origin/payments/other_gateway/pay#pay=$pay')),
        isTrue,
      );
      expect(links.pendingRoute, '/payments/other_gateway/pay');
      expect(links.consume(expectedProvider: 'stripe'), isNull);
      expect(links.consume(expectedProvider: 'other_gateway'), {
        'provider': 'other_gateway',
        'kind': 'pay',
        'token': pay,
      });
    },
  );
}
