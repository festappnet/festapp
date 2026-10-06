import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/logic/order_calc_helper.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/views/order_update_email_dialog.dart';

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  testWidgets(
      'cancelled ticket is previewed once while identical survivor remains',
      (tester) async {
    await EasyLocalization.ensureInitialized();
    const product = {'id': 7, 'title': 'Vstupenka', 'price': 100};
    final changes = OrderCalcHelper.calculateGlobalOrderChanges(
      referenceOrder: OrderModel(data: {
        'tickets': [
          {
            'id': 1,
            'products': [product]
          },
          {
            'id': 2,
            'products': [product]
          },
        ],
      }),
      currentOrder: OrderModel(data: {
        'tickets': [
          {
            'id': 2,
            'products': [product]
          }
        ],
      }),
      currentTicketId: 2,
      currentTicketProducts: [
        ProductModel(id: 7, title: 'Vstupenka', price: 100)
      ],
    );
    expect(changes.removed, hasLength(1));
    expect(changes.added, isEmpty);
    expect(changes.changed, isEmpty);
    expect(changes.referenceTotal, 200);
    expect(changes.currentTotal, 100);
    bool? confirmed;
    await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('cs')],
        path: 'unused',
        startLocale: const Locale('cs'),
        assetLoader: _Translations(),
        child: Builder(
            builder: (context) => MaterialApp(
                locale: context.locale,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                home: Builder(builder: (context) {
                  return ElevatedButton(
                      onPressed: () async {
                        confirmed = await showOrderUpdateEmailDialog(context,
                            email: 'owner@example.invalid',
                            changes: changes,
                            balance: -100);
                      },
                      child: const Text('Preview'));
                })))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.textContaining('- Vstupenka'), findsOneWidget);
    expect(find.textContaining('+ Vstupenka'), findsNothing);
    expect(find.byIcon(Icons.undo_outlined), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Poslat e-mail'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
