import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/stripe_payments/card_refund_decision_api.dart';
import 'package:fstapp/components/stripe_payments/card_refund_decision_dialog.dart';
import 'package:fstapp/components/stripe_payments/card_refund_decision_panel.dart';
import 'package:fstapp/components/stripe_payments/card_refund_decision_strings.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

CardRefundDetail detail(
        {int refunded = 400,
        bool canDecide = true,
        bool pending = false,
        String? dashboardUrl,
        Map<String, dynamic>? decision}) =>
    CardRefundDetail.fromJson({
      'orderId': 10,
      'refundedMinor': refunded,
      'amountMinor': 1000,
      'currency': 'CZK',
      'canDecide': canDecide,
      'reconciliationPending': pending,
      'dashboardUrl': dashboardUrl,
      'decision': decision,
      'tickets': [
        {'id': 1, 'label': 'Unused ticket', 'state': 'paid'},
        {'id': 2, 'label': 'Used ticket', 'state': 'used'},
        {'id': 3, 'label': 'Cancelled ticket', 'state': 'storno'},
      ],
    });

class FakeRefundApi implements CardRefundDecisionApi {
  CardRefundDetail current = detail();
  final calls = <Map<String, dynamic>>[];
  Object? error;
  Completer<void>? pending;
  @override
  Future<CardRefundDetail?> read(int orderId) async => current;
  @override
  Future<void> decide(
      {required CardRefundDetail detail,
      required String action,
      required List<int> ticketIds,
      required String note}) async {
    calls.add({
      'order': detail.orderId,
      'refunded': detail.refundedMinor,
      'action': action,
      'tickets': ticketIds,
      'note': note
    });
    if (error != null) throw error!;
    if (pending != null) await pending!.future;
  }
}

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() => environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())));
  String t(String key) => CardRefundDecisionStrings.text(key);
  Future<void> open(WidgetTester tester, FakeRefundApi api) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
            home: Builder(
                builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => CardRefundDecisionDialog(
                                  detail: api.current, api: api)),
                          child: const Text('Open')),
                    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgetsWithEnvironment(() => environment,
      'requires explicit action and audit reason; never selects used tickets',
      (tester) async {
    final api = FakeRefundApi();
    await open(tester, api);
    await tester.tap(find.text(t('save')));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    await tester.tap(find.text(t('cancelSelected')));
    await tester.pumpAndSettle();
    final used = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('refund-ticket-2')));
    final cancelled = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('refund-ticket-3')));
    expect(used.onChanged, isNull);
    expect(cancelled.onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('refund-ticket-1')));
    await tester.enterText(
        find.byType(TextFormField), '  Customer requested cancellation  ');
    await tester.tap(find.text(t('save')));
    await tester.pumpAndSettle();
    expect(api.calls.single, {
      'order': 10,
      'refunded': 400,
      'action': 'cancel_selected',
      'tickets': [1],
      'note': 'Customer requested cancellation'
    });
    expect(find.byType(CardRefundDecisionDialog), findsNothing);
  });

  testWidgetsWithEnvironment(() => environment,
      'keep submits no tickets and blocks duplicate submissions while pending',
      (tester) async {
    final api = FakeRefundApi()..pending = Completer<void>();
    await open(tester, api);
    await tester.tap(find.text(t('cancelSelected')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('refund-ticket-1')));
    await tester.tap(find.text(t('keep')));
    await tester.enterText(find.byType(TextFormField), 'Goodwill refund');
    await tester.tap(find.text(t('save')));
    await tester.pump();
    expect(api.calls.single['tickets'], isEmpty);
    expect(api.calls.single['action'], 'keep');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    api.pending!.complete();
    await tester.pumpAndSettle();
    expect(api.calls, hasLength(1));
  });

  testWidgetsWithEnvironment(() => environment,
      'changed refund requires refreshed snapshot and explicit new action',
      (tester) async {
    final api = FakeRefundApi()
      ..error = StateError('STRIPE_REFUND_REVISION_CHANGED');
    await open(tester, api);
    await tester.tap(find.text(t('keep')));
    await tester.enterText(find.byType(TextFormField), 'Goodwill refund');
    await tester.tap(find.text(t('save')));
    await tester.pumpAndSettle();
    expect(find.text(t('revisionChanged')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    api.current = detail(refunded: 600);
    api.error = null;
    await tester.tap(find.text(t('refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('save')));
    await tester.pumpAndSettle();
    expect(api.calls, hasLength(1));
    await tester.tap(find.text(t('keep')));
    await tester.tap(find.text(t('save')));
    await tester.pumpAndSettle();
    expect(api.calls.last['refunded'], 600);
  });

  testWidgetsWithEnvironment(() => environment,
      'pending recovery and historical decisions are distinct; unauthorized dashboard absent',
      (tester) async {
    final api = FakeRefundApi()
      ..current = detail(canDecide: false, pending: true, decision: {
        'action': 'keep',
        'note': 'Earlier review',
        'isCurrent': false
      });
    await environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
            home: Scaffold(
                body: CardRefundDecisionPanel(
          orderId: 10,
          api: api,
          onChanged: () async {},
        ))));
    await tester.pumpAndSettle();
    expect(find.text(t('previousDecision')), findsOneWidget);
    expect(find.text(t('pending')), findsOneWidget);
    expect(find.text(t('decide')), findsNothing);
    expect(find.text(t('dashboard')), findsNothing);
  });

  test('only authorized HTTPS Stripe Dashboard links are accepted', () {
    expect(
        detail(
                dashboardUrl:
                    'https://dashboard.stripe.com/acct_x/payments/pi_x')
            .dashboardUri,
        isNotNull);
    expect(
        detail(dashboardUrl: 'https://dashboard.stripe.com.evil.test/')
            .dashboardUri,
        isNull);
    expect(detail(dashboardUrl: 'javascript:alert(1)').dashboardUri, isNull);
    expect(detail().dashboardUri, isNull);
  });
}
