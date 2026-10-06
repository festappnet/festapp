import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/order_change_summary.dart';
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
      'cancelled ticket and survivor product change have distinct sections',
      (tester) async {
    await EasyLocalization.ensureInitialized();
    final changes = OrderChangeSummary.fromJson(jsonDecode(
        File('test/fixtures/order_changes/cancellation_and_product_edit.json')
            .readAsStringSync()));
    expect(changes.cancelledTickets, hasLength(1));
    expect(changes.productChanges, hasLength(1));
    expect(changes.referenceTotal, 200);
    expect(changes.currentTotal, 120);
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
                            ticketId: 2,
                            balance: -100);
                      },
                      child: const Text('Preview'));
                })))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.text('Stornované vstupenky:'), findsOneWidget);
    expect(find.text('Vstupenka FIRST'), findsOneWidget);
    expect(find.text('Změny produktů na vstupence SURVIVOR'), findsOneWidget);
    expect(find.text('Odebrané položky:'), findsNothing);
    expect(find.textContaining('+ Vstupenka'), findsNothing);
    expect(find.byIcon(Icons.undo_outlined), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Poslat e-mail'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
