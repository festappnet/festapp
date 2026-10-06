import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/views/report_text.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:fstapp/components/eshop/models/report_period.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/components/eshop/models/report_exchange_rates.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/eshop/models/occasion_report_model.dart';
import 'package:fstapp/components/eshop/report_strings.dart';
import 'package:fstapp/components/eshop/views/report_tab.dart';
import 'occasion_report_fixture.dart';
import 'package:flutter/gestures.dart';
import 'package:fstapp/components/eshop/views/report_timeline_chart.dart';

class _ReportAssetLoader extends AssetLoader {
  const _ReportAssetLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

Widget app(
  Future<OccasionReport> Function(String) loader, {
  String link = 'one',
  String identity = 'user/org',
  double scale = 1,
  Future<void> Function(OccasionReport)? exporter,
}) =>
    EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'assets/translations',
      assetLoader: const _ReportAssetLoader(),
      startLocale: const Locale('cs'),
      child: Builder(
          builder: (context) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                home: MediaQuery(
                    data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                        size: const Size(390, 844)),
                    child: ReportTab(
                        exchangeRateLoader: () async =>
                            ReportExchangeRates.fromJson({
                              'source': 'CNB',
                              'base': 'CZK',
                              'date': '2026-10-02',
                              'rates': {
                                'EUR': {'amount': '1', 'rate': '24.5'}
                              }
                            }),
                        occasionLink: link,
                        identityKey: identity,
                        loader: loader,
                        exporter: exporter)),
              )),
    );

void main() {
  testWidgets('valid report is the default and toggles without reloading', (tester) async {
    final response = reportResponse();
    response['report']['valid']['orders'] = {'total': 1, 'by_state': [{'state': 'paid', 'count': 1}]};
    response['report']['valid']['tickets'] = {'total': 0, 'by_state': []};
    response['report']['valid']['order_days'] = [{'day': '2026-10-01', 'currency': 'CZK', 'count': 1}];
    final report = OccasionReport.fromResponse(response);
    expect(report.onlyValid().orders.total, 1);
    expect(report.onlyValid().tickets.total, 0);
    expect(report.onlyValid().orderDays.single.count, 1);
    expect(report.onlyValid().money.first.amounts, report.money.first.amounts);
    var calls = 0;
    await tester.pumpWidget(app((_) async { calls++; return report; }));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('reportValidityFilter')), matching: find.byIcon(Icons.check_box_outlined)), findsOneWidget);
    expect(find.text('Pouze platné'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reportValidityFilter')));
    await tester.pumpAndSettle();
    expect(find.text('Včetně stornovaných'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('reportValidityFilter')), matching: find.byIcon(Icons.check_box_outline_blank)), findsOneWidget);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  test('report period ends with occasion but preserves later activity', () {
    final today = DateTime.utc(2026, 10, 3);
    final end = DateTime.utc(2026, 2, 20);
    expect(
        reportTimelineEnd(
            today: today,
            lastActivity: DateTime.utc(2026, 2, 1),
            occasionEnd: end),
        end);
    expect(
        reportTimelineEnd(
            today: today,
            lastActivity: DateTime.utc(2026, 3, 5),
            occasionEnd: end),
        DateTime.utc(2026, 3, 5));
    expect(
        reportTimelineEnd(
            today: today,
            lastActivity: end,
            occasionEnd: DateTime.utc(2026, 12, 1)),
        today);
    expect(reportTimelineEnd(today: today, lastActivity: end), end);
    expect(reportDay(DateTime.parse('2026-03-29T22:30:00Z')),
        DateTime.utc(2026, 3, 30));
  });
  test('CNB conversion rounds exact cents and respects quoted quantities', () {
    final rates = ReportExchangeRates.fromJson({
      'source': 'CNB',
      'base': 'CZK',
      'date': '2026-10-02',
      'rates': {
        'EUR': {'amount': '1', 'rate': '24.5'},
        'JPY': {'amount': '100', 'rate': '14.123'}
      }
    });
    expect(rates.toCzk(BigInt.from(100), 'EUR'), BigInt.from(2450));
    expect(rates.toCzk(BigInt.one, 'EUR'), BigInt.from(25));
    expect(rates.toCzk(BigInt.from(10000), 'JPY'), BigInt.from(1412));
    expect(rates.toCzk(BigInt.parse('1234567890123456789012'), 'EUR'),
        BigInt.parse('30246913308024691330794'));
    expect(() => rates.toCzk(BigInt.one, 'XXX'), throwsFormatException);
  });
  setUpAll(() async {
    tzdata.initializeTimeZones();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final ticketMode in [false, true]) {
    testWidgets(
        'report distinguishes registration and ticket mode: $ticketMode',
        (tester) async {
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          occasion: OccasionModel(
              id: 1,
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [
            TicketFeature(code: FeatureConstants.ticket, isEnabled: ticketMode),
          ]));
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      await tester.pumpWidget(app((_) async => reportFixture()));
      await tester.pumpAndSettle();
      expect(find.text(ReportStrings.tickets),
          ticketMode ? findsWidgets : findsNothing);
      expect(
          formatReportText(reportFixture())
              .contains('${ReportStrings.tickets}:'),
          ticketMode);
      if (!ticketMode) {
        expect(find.text(OrdersStrings.applications), findsWidgets);
        expect(formatReportText(reportFixture()),
            contains('${OrdersStrings.applications}: 3'));
      }
    });
  }

  for (final layout in [(320.0, 1.0), (800.0, 1.0), (320.0, 2.0)]) {
    testWidgets('moving across chart values keeps positions stable: $layout',
        (tester) async {
      final start = DateTime.utc(2026, 1, 1), end = DateTime.utc(2026, 1, 2);
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(layout.$2)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                          width: layout.$1,
                          child: ReportTimelineChart(
                              start: start,
                              end: end,
                              cumulative: false,
                              series: [
                                ReportTimelineSeries(
                                    'Přijaté platby',
                                    Colors.green,
                                    {
                                      start: BigInt.one,
                                      end: BigInt.parse('123456789012345')
                                    },
                                    currency: 'CZK'),
                                ReportTimelineSeries(
                                    'Vráceno',
                                    Colors.red,
                                    {
                                      start: BigInt.zero,
                                      end: BigInt.parse('98765432109876')
                                    },
                                    currency: 'CZK'),
                              ])))))));
      await tester.pumpAndSettle();
      final plot = find.descendant(
          of: find.byType(ReportTimelineChart),
          matching: find.byType(CustomPaint));
      await tester.ensureVisible(plot);
      await tester.pumpAndSettle();
      final plotBefore = tester.getRect(plot);
      final legendBefore =
          tester.getTopLeft(find.text('Vráceno: 987654321098,76 CZK'));
      await tester.tapAt(Offset(plotBefore.left + 1, plotBefore.center.dy));
      await tester.pump();
      expect(tester.getRect(plot), plotBefore);
      expect(tester.getTopLeft(find.text('Vráceno: 0,00 CZK')), legendBefore);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('nested report loads the occasion from its parent route',
      (tester) async {
    String? loadedLink;
    final router = RootStackRouter.build(routes: [
      AutoRoute(
          page: PageInfo('OccasionReportRoot',
              builder: (_) => const AutoRouter()),
          path: '/:{occasionLink}/reservations',
          children: [
            AutoRoute(
                page: PageInfo('OccasionReportLeaf',
                    builder: (_) => ReportTab(
                        identityKey: 'synthetic/editor',
                        loader: (link) async {
                          loadedLink = link;
                          return reportFixture();
                        })),
                path: 'report'),
          ]),
    ]);
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'assets/translations',
      assetLoader: const _ReportAssetLoader(),
      startLocale: const Locale('cs'),
      child: Builder(
          builder: (context) => MaterialApp.router(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                routerConfig: router.config(
                    deepLinkBuilder: (_) =>
                        const DeepLink.path('/occasion-a/reservations/report')),
              )),
    ));
    await tester.pumpAndSettle();
    expect(loadedLink, 'occasion-a');
    expect(tester.takeException(), isNull);
  });

  test('contract preserves decimal precision and rejects unavailable reports',
      () {
    final r = reportFixture();
    expect(r.money.first.amounts['current_order_value'],
        '12345678901234567890.12');
    expect(r.products.map((p) => p.id), ['1', '2']);
    expect(reportFixture(empty: true).orders.total, 0);
    expect(() => OccasionReport.fromResponse({'code': 403}),
        throwsA(isA<ReportUnavailable>()));
    expect(
        () => OccasionReport.fromResponse({'code': 200, 'data': 'old backend'}),
        throwsA(isA<ReportUnavailable>()));
    final unsupported = reportResponse();
    unsupported['report']['schema_version'] = 2;
    expect(() => OccasionReport.fromResponse(unsupported),
        throwsA(isA<ReportUnavailable>()));
    final bad = reportResponse();
    bad['report']['orders']['total'] = 9;
    expect(() => OccasionReport.fromResponse(bad),
        throwsA(isA<ReportUnavailable>()));
  });

  testWidgets(
      'one load across rebuild, text, export; explicit refresh loads once',
      (tester) async {
    int calls = 0, exports = 0;
    Future<OccasionReport> loader(String _) async {
      calls++;
      return reportFixture();
    }

    Future<void> exporter(OccasionReport r) async {
      exports++;
      expect(formatReportText(r),
          contains('${OrderModel.stateToLocale('paid')}: 2'));
    }

    await tester.pumpWidget(app(loader, exporter: exporter));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
        tester
            .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, ReportStrings.cumulative))
            .selected,
        isTrue);
    expect(
        tester
            .widgetList<ReportTimelineChart>(find.byType(ReportTimelineChart))
            .every((chart) => chart.cumulative),
        isTrue);
    expect(
        tester.widgetList<Semantics>(find.byType(Semantics)).any((w) =>
            w.properties.label == '${OrderModel.stateToLocale('paid')}: 2 / 3'),
        isTrue);
    await tester.pumpWidget(app(loader, exporter: exporter));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ReportStrings.text));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    final displayed =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(displayed, contains('${OrderModel.stateToLocale('paid')}: 2'));
    expect(displayed, isNot(contains('  paid:')));
    expect(displayed, formatReportText(reportFixture()));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ReportStrings.export));
    await tester.pumpAndSettle();
    expect(exports, 1);
    expect(calls, 1);
    await tester.tap(find.text(ReportStrings.refresh));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets(
      'refresh is disabled while pending, error retries and dispose is safe',
      (tester) async {
    int calls = 0;
    final pending = Completer<OccasionReport>();
    Future<OccasionReport> loader(String _) {
      calls++;
      return pending.future;
    }

    await tester.pumpWidget(app(loader));
    await tester.pump();
    await tester.pump();
    final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, ReportStrings.refresh));
    expect(button.onPressed, isNull);
    pending.completeError(const ReportUnavailable(403));
    await tester.pumpAndSettle();
    expect(find.text(ReportStrings.error), findsOneWidget);
    final second = Completer<OccasionReport>();
    await tester.pumpWidget(app((_) {
      calls++;
      return second.future;
    }));
    await tester.tap(find.text(ReportStrings.refresh));
    await tester.pump();
    expect(calls, 2);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    second.complete(reportFixture());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'occasion and identity changes discard old snapshots and late responses',
      (tester) async {
    final pending = <Completer<OccasionReport>>[];
    Future<OccasionReport> loader(String _) {
      final c = Completer<OccasionReport>();
      pending.add(c);
      return c.future;
    }

    await tester.pumpWidget(app(loader));
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(app(loader, link: 'two'));
    await tester.pump();
    expect(pending.length, 2);
    pending[1].complete(reportFixture(id: '2'));
    await tester.pumpAndSettle();
    pending[0].complete(reportFixture(id: '1'));
    await tester.pumpAndSettle();
    expect(find.text(reportFixture(id: '2').title), findsOneWidget);
    expect(find.text(reportFixture(id: '1').title), findsNothing);
    await tester.pumpWidget(app(loader, link: 'two', identity: 'other/org'));
    await tester.pump();
    expect(find.text(reportFixture(id: '2').title), findsNothing);
    expect(pending.length, 3);
    pending[2].complete(reportFixture(id: '3'));
    await tester.pumpAndSettle();
  });

  for (final emptyPayments in [true, false]) {
    testWidgets('timeline cards have equal heights, empty payments: $emptyPayments',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final response = reportResponse();
      if (emptyPayments) {
        final report = response['report'] as Map<String, dynamic>;
        final timeline = report['timeline'] as Map<String, dynamic>;
        timeline['payments'] = [];
        timeline['orders'] = [{'day': '2026-10-04', 'currency': 'CZK', 'count': 2}];
        report['valid']['order_days'] = timeline['orders'];
        report['money_by_currency'] = [
          (report['money_by_currency'] as List).first,
        ];
      }
      await tester.pumpWidget(app((_) async => OccasionReport.fromResponse(response)));
      await tester.pumpAndSettle();
      final orders = find.widgetWithText(Card, ReportStrings.orderTimeline);
      final payments = find.widgetWithText(Card, ReportStrings.paymentTimeline);
      expect(orders, findsOneWidget);
      expect(payments, findsOneWidget);
      final orderRect = tester.getRect(orders);
      final paymentRect = tester.getRect(payments);
      expect(orderRect.top, paymentRect.top);
      expect(orderRect.bottom, paymentRect.bottom);
      expect(orderRect.width, paymentRect.width);
      expect(orderRect.right, lessThan(paymentRect.left));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [360.0, 390.0]) {
    testWidgets('mobile $width, text 200 percent, long names and amounts',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app((_) async => reportFixture(), scale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(PopupMenuButton<String>)).shortestSide,
          greaterThanOrEqualTo(48));
      await tester.scrollUntilVisible(
          find.byIcon(Icons.info_outline).first, 300);
      await tester.tap(find.byIcon(Icons.info_outline).first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(ReportStrings.orderTimelineHelp), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      final scroll = find.byType(SingleChildScrollView).first;
      for (var i = 0; i < 20; i++) {
        await tester.drag(scroll, const Offset(0, -650));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(DataTable), findsNothing);
      expect(find.byType(Table), findsNothing);
      await tester.drag(scroll, const Offset(0, 20000));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ReportStrings.text));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'failed refresh hides the previous snapshot after access is revoked',
      (tester) async {
    var calls = 0;
    Future<OccasionReport> loader(String _) async {
      if (++calls == 1) return reportFixture();
      throw const ReportUnavailable(403);
    }

    await tester.pumpWidget(app(loader));
    await tester.pumpAndSettle();
    expect(find.text(reportFixture().title), findsOneWidget);
    await tester.tap(find.text(ReportStrings.refresh));
    await tester.pumpAndSettle();
    expect(find.text(reportFixture().title), findsNothing);
    expect(find.text(ReportStrings.error), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('wide layout shows a product table with distinct product rows',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app((_) async => reportFixture()));
    await tester.pumpAndSettle();
    final products = find.widgetWithText(Table, ReportStrings.product);
    expect(products, findsOneWidget);
    expect(tester.widget<Table>(products).children.length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty snapshot renders without seat occupancy or division by zero',
      (tester) async {
    await tester.pumpWidget(app((_) async => reportFixture(empty: true)));
    await tester.pumpAndSettle();
    expect(find.text(ReportStrings.spots), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('info hover and currency/range switches keep one snapshot',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(app((_) async {
      calls++;
      return reportFixture();
    }));
    await tester.pumpAndSettle();
    final icon = find.byIcon(Icons.info_outline).first;
    await tester.scrollUntilVisible(icon, 200);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(icon));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(ReportStrings.orderTimelineHelp), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 200));
    await mouse.removePointer();
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'EUR'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'EUR'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, ReportStrings.compareCurrencies));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(ChoiceChip, ReportStrings.compareCurrencies));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  test('date axis uses month boundaries across years and days for short ranges',
      () {
    expect(
        reportChartTicks(DateTime.utc(2025, 11, 20), DateTime.utc(2026, 1, 18)),
        [
          DateTime.utc(2025, 11, 20),
          DateTime.utc(2025, 12, 1),
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 18),
        ]);
    expect(
        reportChartTicks(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 3))
            .length,
        3);
    expect(
        reportChartTicks(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 1, 1))
            .length,
        1);
  });

  test('chart preserves exact cents and fills missing calendar days', () {
    final value = reportMinorUnits('12345678901234567890.12');
    expect(reportChartAmount(value, 'CZK'), '12345678901234567890,12 CZK');
    expect(
        reportChartDays(DateTime.utc(2026, 3, 28), DateTime.utc(2026, 3, 30))
            .length,
        3);
    final fixture = reportFixture();
    expect(fixture.orderDays.length, 2);
    expect(fixture.paymentDays[0].received, '25.00');
  });
}
