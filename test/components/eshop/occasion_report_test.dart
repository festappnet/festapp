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
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

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
      expect(r.text, contains('Report 1'));
    }

    await tester.pumpWidget(app(loader, exporter: exporter));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((w) => w.properties.label == 'paid: 2 / 3'),
        isTrue);
    await tester.pumpWidget(app(loader, exporter: exporter));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ReportStrings.text));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
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
    expect(find.byType(Table), findsOneWidget);
    expect(tester.widget<Table>(find.byType(Table)).children.length, 3);
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
