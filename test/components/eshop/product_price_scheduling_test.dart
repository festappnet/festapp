import 'package:fstapp/components/eshop/views/product_price_waves_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/models/product_price_wave.dart';
import 'package:fstapp/components/eshop/models/product_edit_bundle.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';

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
      home: Scaffold(body: child),
    ),
  ),
);
ProductPriceChange change(
  int id,
  int days, {
  bool applied = false,
  String? failure,
}) => ProductPriceChange(
  id: id,
  revision: 1,
  price: 450 + id * 50,
  time: DateTime.now().toUtc().add(Duration(days: days)),
  applied: applied,
  failureCode: failure,
);
ProductModel product(List<ProductPriceChange> changes) => ProductModel(
  id: 1,
  title: 'Vstupenka',
  price: 450,
  currencyCode: 'CZK',
  priceChanges: changes,
);
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    tzdata.initializeTimeZones();
  });
  for (final dirty in [false, true]) {
    testWidgets('opening price waves closes the small dialog, dirty=$dirty',
        (tester) async {
      var opened = false;
      final p = product([]);
      await tester.pumpWidget(app(Builder(builder: (context) => TextButton(
        onPressed: () => showDialog<bool>(
          context: context,
          builder: (_) => ProductPriceChangesDialog(
            product: p,
            canEdit: true,
            reload: () async => p,
            onOpenWaves: () => opened = true,
          ),
        ),
        child: const Text('Open plans'),
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open plans'));
      await tester.pumpAndSettle();
      if (dirty) {
        await tester.enterText(find.byType(TextField).first, '550');
      }
      await tester.tap(find.text('Cenové vlny'));
      await tester.pumpAndSettle();
      if (dirty) {
        expect(opened, isFalse);
        await tester.tap(find.widgetWithText(TextButton, CommonStrings.cancel));
        await tester.pumpAndSettle();
        expect(find.byType(ProductPriceChangesDialog), findsOneWidget);
        expect(opened, isFalse);
        await tester.tap(find.text('Cenové vlny'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, CommonStrings.discardChanges));
        await tester.pumpAndSettle();
      }
      expect(opened, isTrue);
      expect(find.byType(ProductPriceChangesDialog), findsNothing);
    });
  }
  test('DST gap rejected, overlap offers both instants and preserves occasion timezone', () {
    final prague = tz.getLocation('Europe/Prague');
    expect(
      ProductPriceChange.instants(DateTime.utc(2027, 3, 28, 2, 30), prague),
      isEmpty,
    );
    final overlap = ProductPriceChange.instants(
      DateTime.utc(2026, 10, 25, 2, 30),
      prague,
    );
    expect(overlap, [
      DateTime.utc(2026, 10, 25, 0, 30),
      DateTime.utc(2026, 10, 25, 1, 30),
    ]);
    expect(ProductPriceChange.instants(DateTime.utc(2026, 10, 15, 9), prague), [
      DateTime.utc(2026, 10, 15, 7),
    ]);
  });
  test('only pending plans sorted, metadata never sent by generic save', () {
    final p = product([
      change(3, 3),
      change(1, 1),
      change(2, 2, applied: true),
    ]);
    expect(ProductPriceChange.pending(p.priceChanges).map((c) => c.id), [1, 3]);
    expect(p.toJson().containsKey('price_changes'), false);
    expect(p.copyWith(price: 500).priceChanges.length, 3);
  });
  testWidgets('empty cell and complete multi-plan count are accessible', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 420,
          child: ProductPriceChangeCell(product: product([]), onOpen: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Naplánovat změnu'), findsOneWidget);
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 420,
          child: ProductPriceChangeCell(
            product: product([change(3, 3), change(1, 1), change(2, 2)]),
            onOpen: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('+2 další'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
  });
  testWidgets('plan cell opens with Enter from keyboard focus', (tester) async {
    int opens = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      app(
        SizedBox(
          width: 420,
          child: ProductPriceChangeCell(
            product: product([]),
            focusNode: focus,
            onOpen: () => opens++,
          ),
        ),
      ),
    );
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
        change(4, 4, applied: true),
      ]);
      await tester.pumpWidget(
        app(
          ProductPriceChangesDialog(
            product: p,
            canEdit: false,
            reload: () async => p,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Čeká na provedení'), findsOneWidget);
      expect(find.textContaining('INVALID_VALUE'), findsOneWidget);
      expect(find.text('Zrušit změnu'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Card), findsNWidgets(3));
    },
  );
  testWidgets('saving disables double submit, error retains typed form', (
    tester,
  ) async {
    final p = product([]);
    final pending = Completer<void>();
    int calls = 0;
    await tester.pumpWidget(
      app(
        ProductPriceChangesDialog(
          product: p,
          canEdit: true,
          reload: () async => p,
          save: (_, __, ___) {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '550');
    tester.widget<TimeDatePicker>(find.byType(TimeDatePicker)).onDateChanged(
        DateTime(2090, 10, 15));
    await tester.pump();
    tester.widget<TimeDatePicker>(find.byType(TimeDatePicker)).onTimeChanged(
        const TimeOfDay(hour: 9, minute: 0));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Naplánovat změnu'));
    await tester.pump();
    expect(calls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
    );
    pending.completeError(Exception('simulated network failure'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '550',
    );
    expect(find.textContaining('Změnu se nepodařilo uložit'), findsWidgets);
    expect(calls, 1);
  });
  testWidgets('compact editor uses system-local input and saves UTC', (
    tester,
  ) async {
    DateTime? saved;
    final p = product([]);
    await tester.pumpWidget(
      app(
        ProductPriceChangesDialog(
          product: p,
          canEdit: true,
          reload: () async => p,
          save: (_, instant, __) async {
            saved = instant;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Europe/Amsterdam'), findsNothing);
    expect(find.textContaining('Cena platí pro nové objednávky'), findsNothing);
    await tester.enterText(find.byType(TextField).at(0), '550');
    tester.widget<TimeDatePicker>(find.byType(TimeDatePicker)).onDateChanged(
        DateTime(2090, 10, 15));
    await tester.pump();
    tester.widget<TimeDatePicker>(find.byType(TimeDatePicker)).onTimeChanged(
        const TimeOfDay(hour: 9, minute: 0));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Naplánovat změnu'));
    await tester.pumpAndSettle();
    expect(saved, DateTime(2090, 10, 15, 9).toUtc());
    expect(saved!.isUtc, isTrue);
    expect(scheduledTime(saved!), '15. 10. 2090 09:00');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('waves project existing price/visibility targets without changing write payloads', () {
    final instant=DateTime.utc(2090,10,15,7);
    final p=product([ProductPriceChange(id:1,revision:1,price:500,time:instant)]);
    p.visibilityChanges=[ProductVisibilityChange(id:2,revision:1,time:instant,hidden:true)];
    final waves=ProductPriceWave.columns([ProductPriceWave(id:3,time:instant),ProductPriceWave(id:4,time:instant.add(const Duration(days:1)))],[p]);
    expect(waves.length,2);
    expect(waves.first.prices(p).single.price,500);
    expect(waves.first.visibility(p).single.hidden,isTrue);
    expect(p.copyWith(price:550).visibilityChanges.single.id,2);
    expect(p.toJson().containsKey('visibility_changes'),isFalse);
  });
  testWidgets('visibility-only wave sends no price and retains typed state on error', (tester) async {
    double? savedPrice;bool? savedHidden;int calls=0;
    final pending=Completer<void>();
    await tester.pumpWidget(app(WaveProductTargetDialog(
      wave:ProductPriceWave(id:1,time:DateTime.now().toUtc().add(const Duration(days:1))),
      product:product([]),save:(price,hidden) {savedPrice=price;savedHidden=hidden;calls++;return pending.future;})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beze změny').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skrýt').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'Uložit'));
    await tester.pump();
    expect(savedPrice,isNull);expect(savedHidden,isTrue);expect(calls,1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,isNull);
    pending.completeError(Exception('simulated failure'));
    await tester.pumpAndSettle();
    expect(find.text('Skrýt'),findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('wave timeline starts with current state and needs no horizontal scrolling', (tester) async {
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final instant=DateTime.now().toUtc().add(const Duration(days:5));
    final p=product([ProductPriceChange(id:1,revision:1,price:550,time:instant)]);
    p.visibilityChanges=[ProductVisibilityChange(id:2,revision:1,time:instant,hidden:true)];
    final bundle=ProductsEditBundle(products:[p],productTypes:[],inventoryPools:[],inventoryContexts:[],forms:[],priceWaves:[ProductPriceWave(id:1,time:instant)]);
    await tester.pumpWidget(app(MediaQuery(data:const MediaQueryData(size:Size(390,844),textScaler:TextScaler.linear(1.5)),
      child:ProductPriceWavesDialog(occasionLink:'test',initialBundle:bundle,canEdit:false,loader:() async=>bundle))));
    await tester.pumpAndSettle();
    expect(find.text('Cenové vlny'),findsOneWidget);
    expect(find.text('Aktuálně'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Aktuálně')).dy, lessThan(tester.getTopLeft(find.textContaining('550')).dy));
    expect(tester.widgetList<Scrollable>(find.byType(Scrollable)).every((s) => s.axisDirection == AxisDirection.down), isTrue);
    expect(find.text('Skrýt'),findsOneWidget);
    expect(find.textContaining('550'),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('narrow viewport and larger text keep actions usable', (
    tester,
  ) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = product([change(1, 1), change(2, 2), change(3, 3)]);
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.5),
          ),
          child: ProductPriceChangesDialog(
            product: p,
            canEdit: true,
            reload: () async => p,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Přidat další změnu'), findsOneWidget);
    await tester.tap(find.text('Přidat další změnu'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
