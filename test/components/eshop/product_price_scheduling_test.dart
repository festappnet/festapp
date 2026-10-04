import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_price_change.dart';
import 'package:fstapp/components/eshop/views/product_price_change_cell.dart';
import 'package:fstapp/components/eshop/views/product_price_changes_dialog.dart';

class _Loader extends AssetLoader {
  const _Loader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync());
}

Widget app(Widget child) => EasyLocalization(
    supportedLocales: const [Locale('cs')],
    startLocale: const Locale('cs'),
    path: 'assets/translations',
    assetLoader: const _Loader(),
    child: Builder(
        builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(body: child))));
ProductPriceChange change(int id, int days,
        {bool applied = false, String? failure}) =>
    ProductPriceChange(
        id: id,
        revision: 1,
        price: 450 + id * 50,
        time: DateTime.now().toUtc().add(Duration(days: days)),
        applied: applied,
        failureCode: failure);
ProductModel product(List<ProductPriceChange> changes) => ProductModel(
    id: 1,
    title: 'Vstupenka',
    price: 450,
    currencyCode: 'CZK',
    priceChanges: changes);
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    tzdata.initializeTimeZones();
  });
  test(
      'DST gap rejected, overlap offers both instants and preserves occasion timezone',
      () {
    final prague = tz.getLocation('Europe/Prague');
    expect(
        ProductPriceChange.instants(DateTime.utc(2027, 3, 28, 2, 30), prague),
        isEmpty);
    final overlap =
        ProductPriceChange.instants(DateTime.utc(2026, 10, 25, 2, 30), prague);
    expect(overlap,
        [DateTime.utc(2026, 10, 25, 0, 30), DateTime.utc(2026, 10, 25, 1, 30)]);
    expect(ProductPriceChange.instants(DateTime.utc(2026, 10, 15, 9), prague),
        [DateTime.utc(2026, 10, 15, 7)]);
  });
  test('only pending plans sorted, metadata never sent by generic save', () {
    final p =
        product([change(3, 3), change(1, 1), change(2, 2, applied: true)]);
    expect(ProductPriceChange.pending(p.priceChanges).map((c) => c.id), [1, 3]);
    expect(p.toJson().containsKey('price_changes'), false);
    expect(p.copyWith(price: 500).priceChanges.length, 3);
  });
  testWidgets('empty cell and complete multi-plan count are accessible',
      (tester) async {
    await tester.pumpWidget(app(SizedBox(
        width: 420,
        child: ProductPriceChangeCell(
            product: product([]), timezone: 'Europe/Prague', onOpen: () {}))));
    await tester.pumpAndSettle();
    expect(find.text('Naplánovat změnu'), findsOneWidget);
    await tester.pumpWidget(app(SizedBox(
        width: 420,
        child: ProductPriceChangeCell(
            product: product([change(3, 3), change(1, 1), change(2, 2)]),
            timezone: 'Europe/Prague',
            onOpen: () {}))));
    await tester.pumpAndSettle();
    expect(find.textContaining('+2 další'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });
  testWidgets('plan cell opens with Enter from keyboard focus', (tester) async {
    int opens = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(app(SizedBox(
        width: 420,
        child: ProductPriceChangeCell(
            product: product([]),
            timezone: 'Europe/Prague',
            focusNode: focus,
            onOpen: () => opens++))));
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opens, 1);
  });
  testWidgets(
      'viewer sees full timeline and pending failure, has no mutation actions',
      (tester) async {
    final p = product([
      change(3, 3),
      change(1, -1),
      change(2, 2, failure: 'INVALID_VALUE'),
      change(4, 4, applied: true)
    ]);
    await tester.pumpWidget(app(ProductPriceChangesDialog(
        product: p,
        timezone: 'Europe/Prague',
        canEdit: false,
        reload: () async => p)));
    await tester.pumpAndSettle();
    expect(find.text('Čeká na provedení'), findsOneWidget);
    expect(find.textContaining('INVALID_VALUE'), findsOneWidget);
    expect(find.text('Zrušit změnu'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Card), findsNWidgets(3));
  });
  testWidgets('saving disables double submit, error retains typed form',
      (tester) async {
    final p = product([]);
    final pending = Completer<void>();
    int calls = 0;
    await tester.pumpWidget(app(ProductPriceChangesDialog(
        product: p,
        timezone: 'Europe/Prague',
        canEdit: true,
        reload: () async => p,
        save: (_, __, ___) {
          calls++;
          return pending.future;
        })));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '550');
    await tester.enterText(find.byType(TextField).at(1), '2090-10-15');
    await tester.enterText(find.byType(TextField).at(2), '09:00');
    await tester.tap(find.widgetWithText(FilledButton, 'Naplánovat změnu'));
    await tester.pump();
    expect(calls, 1);
    expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull);
    pending.completeError(Exception('simulated network failure'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        '550');
    expect(find.textContaining('Změnu se nepodařilo uložit'), findsWidgets);
    expect(calls, 1);
  });
  testWidgets('narrow viewport and larger text keep actions usable',
      (tester) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = product([change(1, 1), change(2, 2), change(3, 3)]);
    await tester.pumpWidget(app(MediaQuery(
        data: const MediaQueryData(
            size: Size(390, 844), textScaler: TextScaler.linear(1.5)),
        child: ProductPriceChangesDialog(
            product: p,
            timezone: 'Europe/Prague',
            canEdit: true,
            reload: () async => p))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Přidat další změnu'), findsOneWidget);
    await tester.tap(find.text('Přidat další změnu'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
