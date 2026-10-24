import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/stripe_payments/stripe_connection_api.dart';
import 'package:fstapp/components/stripe_payments/unit_card_payments_page.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

class FakeConnectionApi implements StripeConnectionApi {
  final calls = <int>[];
  Map<String, dynamic>? connection;
  Completer<Map<String, dynamic>?>? pending;
  int starts = 0;
  int disconnections = 0;
  int openAttempts = 0;
  bool uncertainDisconnect = false;
  @override
  Future<Map<String, dynamic>> disconnectImpact(int unitId) async => {
        'connectionId': connection?['connectionId'],
        'openAttempts': openAttempts,
        'historyCount': 1
      };
  @override
  Future<Map<String, dynamic>> disconnect(
      int unitId, String connectionId) async {
    disconnections++;
    if (uncertainDisconnect) {
      connection = {
        ...?connection,
        'disconnectState': 'uncertain',
        'paused': true
      };
      return {'disconnected': false, 'uncertain': true};
    }
    connection = {...?connection, 'state': 'revoked', 'paused': true};
    return {'disconnected': true};
  }

  @override
  Future<Map<String, dynamic>?> status(int unitId) {
    calls.add(unitId);
    return pending?.future ?? Future.value(connection);
  }

  @override
  Future<Uri> start(int unitId, {bool replace = false}) async {
    starts++;
    return Uri.parse(
        'https://connect.stripe.com/oauth/authorize?state=fixture');
  }

  @override
  Future<void> pause(int unitId, bool paused) async {
    connection = {...?connection, 'paused': paused};
  }

  @override
  Future<Map<String, dynamic>> complete(Map<String, String> callback) =>
      throw UnimplementedError();
}

void main() {
  WidgetEnvironmentFixture.register();
  late Map<String, dynamic> catalog;
  setUpAll(() {
    catalog =
        jsonDecode(File('assets/translations/cs.json').readAsStringSync());
  });
  WidgetEnvironmentFixture environment() => WidgetEnvironmentFixture(
      locale: const Locale('cs'), translations: catalog);
  Widget page(FakeConnectionApi api,
          {bool canManage = true,
          bool connectSupported = true,
          int unit = 1,
          Future<bool> Function(String)? open}) =>
      MaterialApp(
          home: Scaffold(
              body: UnitCardPaymentsView(
                  unitId: unit,
                  canManage: canManage,
                  connectSupported: connectSupported,
                  api: api,
                  openExternal: open)));
  testWidgets('native Connect is unavailable without starting an OAuth flow',
      (tester) async {
    final api = FakeConnectionApi();
    final env = environment();
    await env.pumpWidget(tester, page(api, connectSupported: false));
    await tester.pumpAndSettle();
    final connect = find.widgetWithText(
        FilledButton, catalog['CardPaymentConnection']['connect']);
    expect(tester.widget<FilledButton>(connect).onPressed, isNull);
    expect(
        find.text(catalog['CardPaymentConnection']['nativeConnectUnavailable']),
        findsOneWidget);
    expect(api.starts, 0);
  });
  testWidgets(
      'A25 disconnect explains impact, blocks unresolved payments and preserves explicit confirmation',
      (tester) async {
    final api = FakeConnectionApi()
      ..openAttempts = 1
      ..connection = {
        'connectionId': '00000000-0000-4000-8000-000000000002',
        'state': 'connected',
        'modelVerified': true,
        'chargesEnabled': true,
        'cardPaymentsActive': true,
        'paused': false
      };
    await environment().pumpWidget(tester, page(api));
    await tester.pumpAndSettle();
    final label = catalog['CardPaymentConnection']['disconnect'] as String;
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(find.text(catalog['CardPaymentConnection']['disconnectBlocked']),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, label), findsNothing);
    expect(api.disconnections, 0);
    await tester
        .tap(find.widgetWithText(TextButton, catalog['Common']['close']));
    await tester.pumpAndSettle();
    api.openAttempts = 0;
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(find.text(catalog['CardPaymentConnection']['disconnectExplanation']),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
    expect(api.disconnections, 1);
    expect(
        find.text(catalog['CardPaymentConnection']['revoked']), findsOneWidget);
  });
  testWidgets(
      'A25 uncertain disconnect leaves Dashboard available and blocks resume and replacement',
      (tester) async {
    final api = FakeConnectionApi()
      ..uncertainDisconnect = true
      ..connection = {
        'connectionId': '00000000-0000-4000-8000-000000000002',
        'state': 'connected',
        'modelVerified': true,
        'chargesEnabled': true,
        'cardPaymentsActive': true,
        'paused': false,
        'dashboardUrl':
            'https://dashboard.stripe.com/acct_fixture/test/dashboard'
      };
    await environment().pumpWidget(tester, page(api));
    await tester.pumpAndSettle();
    final label = catalog['CardPaymentConnection']['disconnect'] as String;
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
    expect(find.text(catalog['CardPaymentConnection']['disconnectUncertain']),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(
                FilledButton, catalog['CardPaymentConnection']['resume']))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(
                TextButton, catalog['CardPaymentConnection']['replace']))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(
                OutlinedButton, catalog['CardPaymentConnection']['dashboard']))
            .onPressed,
        isNotNull);
  });
  testWidgets('A03 editor cannot load status or initiate connection',
      (tester) async {
    final api = FakeConnectionApi();
    await environment().pumpWidget(tester, page(api, canManage: false));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });
  testWidgets(
      'A04 payouts warning is separate from accepting payments and pause is durable',
      (tester) async {
    final api = FakeConnectionApi()
      ..connection = {
        'state': 'connected',
        'modelVerified': true,
        'chargesEnabled': true,
        'cardPaymentsActive': true,
        'payoutsEnabled': false,
        'paused': false
      };
    await environment().pumpWidget(tester, page(api));
    await tester.pumpAndSettle();
    expect(find.text(catalog['CardPaymentConnection']['receiving']),
        findsOneWidget);
    expect(find.text(catalog['CardPaymentConnection']['payoutsAttention']),
        findsOneWidget);
    await tester.tap(find.text(catalog['CardPaymentConnection']['pause']));
    await tester.pumpAndSettle();
    expect(api.connection!['paused'], isTrue);
    expect(
        find.text(catalog['CardPaymentConnection']['paused']), findsOneWidget);
  });
  testWidgets(
      'A02 changing unit cannot display late response from another recipient',
      (tester) async {
    final api = FakeConnectionApi()..pending = Completer();
    final env = environment();
    await env.pumpWidget(tester, page(api));
    final old = api.pending!;
    api.pending = Completer();
    await env.pumpWidget(tester, page(api, unit: 2));
    old.complete({'businessName': 'Wrong recipient', 'state': 'connected'});
    await tester.pump();
    expect(find.text('Wrong recipient'), findsNothing);
    api.pending!.complete(null);
    await tester.pumpAndSettle();
    expect(api.calls, [1, 2]);
    expect(tester.takeException(), isNull);
  });
}
