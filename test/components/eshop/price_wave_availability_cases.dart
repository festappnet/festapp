import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/views/product_price_waves_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>,
    );
  });
  for (final choice in [0, 1, 2]) {
    testWidgetsWithEnvironment(() => environment,
        'availability explains and saves choice $choice on a narrow screen',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? savedHidden;
      var saves = 0;
      await environment.pumpWidget(
          tester,
          MaterialApp(
              builder: DependencyMaterialBridge.wrapBuilder((context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!)),
              home: Builder(
                  builder: (context) => Scaffold(
                        body: TextButton(
                            onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => WaveProductTargetDialog(
                                      wave: ProductPriceWave(
                                          id: 1, time: DateTime.utc(2099)),
                                      product: ProductModel(
                                          id: 1,
                                          isUsedInBlueprint: false,
                                          title: 'Místo',
                                          price: 440,
                                          currencyCode: 'CZK'),
                                      save: (_, hidden) async {
                                        savedHidden = hidden;
                                        saves++;
                                      },
                                    )),
                            child: const Text('Open')),
                      ))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text(OrdersStrings.waveAvailabilityNoChange), findsOneWidget);
      expect(find.text(OrdersStrings.waveAvailabilityKeepHint), findsOneWidget);
      await tester.tap(find.byTooltip(OrdersStrings.waveAvailabilityHelpTitle));
      await tester.pumpAndSettle();
      expect(find.text(OrdersStrings.waveAvailabilityHelp), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      final labels = [
        OrdersStrings.waveAvailabilityNoChange,
        OrdersStrings.waveShown,
        OrdersStrings.waveHidden
      ];
      await tester.tap(find.text(labels[choice]).last);
      await tester.pumpAndSettle();
      final hints = [
        OrdersStrings.waveAvailabilityKeepHint,
        OrdersStrings.waveAvailabilityShowHint,
        OrdersStrings.waveAvailabilityHideHint
      ];
      expect(find.text(hints[choice]), findsOneWidget);
      await tester.ensureVisible(find.text(CommonStrings.save));
      await tester.tap(find.text(CommonStrings.save));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(savedHidden, choice == 0 ? isNull : equals(choice == 2));
      expect(tester.takeException(), isNull);
    });
  }
  for (final usage in [true, null]) {
    for (final originalHidden in [null, false, true]) {
      for (final cancel in originalHidden == null ? [false] : [false, true]) {
        testWidgetsWithEnvironment(() => environment,
            'restricted availability usage=$usage hidden=$originalHidden cancel=$cancel',
            (tester) async {
          tester.view.physicalSize = const Size(375, 812);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final time = DateTime.utc(2099);
          var saves = 0;
          bool? savedHidden;
          double? savedPrice;
          await environment.pumpWidget(
              tester,
              MaterialApp(
                builder: DependencyMaterialBridge.wrapBuilder((context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(1.5)),
                    child: child!)),
                home: Builder(
                    builder: (context) => Scaffold(
                          body: TextButton(
                            child: const Text('Open'),
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => WaveProductTargetDialog(
                                wave: ProductPriceWave(id: 1, time: time),
                                product: ProductModel(
                                  id: 1,
                                  title: 'Místo',
                                  isUsedInBlueprint: usage,
                                  currencyCode: 'CZK',
                                  visibilityChanges: [
                                    if (originalHidden != null)
                                      ProductVisibilityChange(
                                          id: 10,
                                          revision: 2,
                                          waveId: 1,
                                          time: time,
                                          hidden: originalHidden),
                                  ],
                                ),
                                save: (price, hidden) async {
                                  saves++;
                                  savedPrice = price;
                                  savedHidden = hidden;
                                },
                              ),
                            ),
                          ),
                        )),
              ));
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
          expect(
              tester
                  .widget<DropdownButtonFormField<int>>(
                      find.byType(DropdownButtonFormField<int>))
                  .onChanged,
              isNull);
          expect(
              find.text(usage == true
                  ? OrdersStrings.waveSeatProductHint
                  : OrdersStrings.waveAvailabilityUnknownHint),
              findsOneWidget);
          await tester.enterText(find.byType(TextField), '550');
          if (originalHidden != null) {
            expect(
                find.text(originalHidden
                    ? OrdersStrings.waveHidden
                    : OrdersStrings.waveShown),
                findsOneWidget);
            if (cancel) {
              await tester.ensureVisible(find.byType(CheckboxListTile));
              await tester.tap(find.byType(CheckboxListTile));
              await tester.pumpAndSettle();
            }
          } else {
            expect(find.byType(CheckboxListTile), findsNothing);
          }
          await tester.ensureVisible(find.text(CommonStrings.save));
          await tester.tap(find.text(CommonStrings.save));
          await tester.pumpAndSettle();
          expect(saves, 1);
          expect(savedPrice, 550);
          expect(savedHidden, cancel ? isNull : equals(originalHidden));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
