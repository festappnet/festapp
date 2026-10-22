import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/stripe_payments/stripe_payment_api.dart';
import 'package:fstapp/components/stripe_payments/stripe_payment_page.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

Map<String, dynamic> payment(String status) => {
      'method': 'stripe',
      'status': status,
      'amount': '123.45',
      'received': status == 'paid' ? '123.45' : '0',
      'returned': '0',
      'currency': 'CZK',
      'allowedActions': ['pay', 'refresh']
    };

class PaymentGatewayFake implements StripePaymentGateway {
  final reads = <bool>[];
  int prepares = 0, handoffReads = 0, handoffPrepares = 0;
  bool handoffConsumed = false;
  String status = 'open';
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> read(String token,
      {bool returnOnly = false}) async {
    reads.add(returnOnly);
    return payment(status);
  }

  @override
  Future<Map<String, dynamic>> readHandoff(String token) async {
    handoffReads++;
    return {
      ...payment(status),
      'allowedActions': [if (!handoffConsumed) 'pay', 'refresh']
    };
  }

  @override
  Future<Map<String, dynamic>> prepareHandoff(String token) {
    handoffPrepares++;
    handoffConsumed = true;
    return pending?.future ??
        Future.value({
          'payment': {
            ...payment(status),
            'allowedActions': ['refresh']
          }
        });
  }

  @override
  Future<Map<String, dynamic>> prepare(String token) {
    prepares++;
    return pending?.future ?? Future.value({'payment': payment('paid')});
  }
}

void main() {
  WidgetEnvironmentFixture.register();
  late Map<String, dynamic> catalog;
  setUpAll(() => catalog =
      jsonDecode(File('assets/translations/cs.json').readAsStringSync()));
  WidgetEnvironmentFixture env() => WidgetEnvironmentFixture(
      locale: const Locale('cs'), translations: catalog);
  Widget page(PaymentGatewayFake gateway,
          {bool returnOnly = false,
          bool handoff = false,
          String? surface,
          Future<bool> Function(String)? open}) =>
      MaterialApp(
          home: Scaffold(
              body: StripePaymentAccessView(
                  token: 'a' * 64,
                  gateway: gateway,
                  returnOnly: returnOnly,
                  handoff: handoff,
                  paymentSurface: surface == null ? null : () => surface,
                  openCheckout: open)));
  testWidgets(
      'A08 return scope remains read only despite a pay action in a projection',
      (tester) async {
    final gateway = PaymentGatewayFake();
    await env().pumpWidget(tester, page(gateway, returnOnly: true));
    await tester.pumpAndSettle();
    expect(gateway.reads, [true]);
    expect(find.text(catalog['CardPayments']['continuePayment']), findsNothing);
    expect(gateway.prepares, 0);
  });
  testWidgets(
      'A09 two clicks prepare one attempt and a paid response cannot open Checkout',
      (tester) async {
    final gateway = PaymentGatewayFake()..pending = Completer();
    int opened = 0;
    await env().pumpWidget(
        tester,
        page(gateway, open: (_) async {
          opened++;
          return true;
        }));
    await tester.pumpAndSettle();
    final button = find.text(catalog['CardPayments']['continuePayment']);
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(gateway.prepares, 1);
    gateway.pending!.complete({'payment': payment('paid')});
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(find.text(catalog['CardPayments']['paid']), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'A11 app resume reads SQL state without preparing another payment',
      (tester) async {
    final gateway = PaymentGatewayFake();
    await env().pumpWidget(tester, page(gateway));
    await tester.pumpAndSettle();
    gateway.status = 'paid';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.reads.length, 2);
    expect(gateway.prepares, 0);
    expect(find.text(catalog['CardPayments']['paid']), findsOneWidget);
  });
  testWidgets('A10 provider URL outside Stripe cannot receive the visitor',
      (tester) async {
    final gateway = PaymentGatewayFake()..pending = Completer();
    int opened = 0;
    await env().pumpWidget(
        tester,
        page(gateway, open: (_) async {
          opened++;
          return true;
        }));
    await tester.pumpAndSettle();
    await tester.tap(find.text(catalog['CardPayments']['continuePayment']));
    gateway.pending!.complete({
      'payment': payment('open'),
      'checkoutUrl': 'https://foreign.example/collect'
    });
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(find.text(catalog['CardPayments']['unknown']), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'handoff initial/resume reads remain scoped and only explicit click consumes once',
      (tester) async {
    final gateway = PaymentGatewayFake()..pending = Completer();
    final opened = <String>[];
    await env().pumpWidget(
        tester,
        page(gateway, handoff: true, surface: 'web', open: (url) async {
          opened.add(url);
          return true;
        }));
    await tester.pumpAndSettle();
    expect(gateway.handoffReads, 1);
    expect(gateway.reads, isEmpty);
    expect(gateway.handoffPrepares, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.handoffReads, 2);
    final button = find.text(catalog['CardPayments']['continuePayment']);
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(gateway.handoffPrepares, 1);
    gateway.pending!.complete({
      'payment': {
        ...payment('open'),
        'allowedActions': ['refresh']
      },
      'checkoutUrl': 'https://checkout.stripe.com/c/pay/cs_test_handoff'
    });
    await tester.pumpAndSettle();
    expect(opened, ['https://checkout.stripe.com/c/pay/cs_test_handoff']);
    expect(gateway.prepares, 0);
    expect(find.text(catalog['CardPayments']['continuePayment']), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.handoffReads, 3);
    expect(gateway.handoffPrepares, 1);
  });

  for (final surface in ['embed', 'android', 'ios', 'unsupported']) {
    testWidgets('handoff cannot be read or consumed on $surface',
        (tester) async {
      final gateway = PaymentGatewayFake();
      await env()
          .pumpWidget(tester, page(gateway, handoff: true, surface: surface));
      await tester.pumpAndSettle();
      expect(gateway.handoffReads, 0);
      expect(gateway.reads, isEmpty);
      expect(gateway.handoffPrepares, 0);
      expect(find.text(catalog['CardPayments']['protectedPaymentLink']),
          findsOneWidget);
      expect(
          find.text(catalog['CardPayments']['continuePayment']), findsNothing);
    });
  }

  testWidgets('return route cannot upgrade a handoff into payment access',
      (tester) async {
    final gateway = PaymentGatewayFake();
    await env().pumpWidget(
        tester, page(gateway, handoff: true, returnOnly: true, surface: 'web'));
    await tester.pumpAndSettle();
    expect(gateway.handoffReads, 0);
    expect(gateway.reads, isEmpty);
    expect(find.text(catalog['CardPayments']['protectedPaymentLink']),
        findsOneWidget);
  });
}
