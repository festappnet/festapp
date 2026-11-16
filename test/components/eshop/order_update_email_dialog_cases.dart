import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/views/order_update_email_dialog.dart';
import 'package:fstapp/components/eshop/views/product_changes_preview.dart';
import 'package:fstapp/components/eshop/views/product_info_panel.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues({}));
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
            builder: (context) => MaterialApp(builder: DependencyMaterialBridge.builder,
                locale: context.locale,
                localizationsDelegates: [...context.localizationDelegates, ...GlobalMaterialLocalizations.delegates],
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
    expect(find.text('(Storno)'), findsOneWidget);
    expect(find.text('Vstupenka FIRST'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Vstupenka FIRST')).style?.decoration,
        TextDecoration.lineThrough);
    expect(find.text('Vstupenka SURVIVOR'), findsOneWidget);
    expect(
        tester.widget<Text>(find.text('Vstupenka SURVIVOR')).style?.decoration,
        isNull);
    expect(find.textContaining('Změny produktů na vstupence'), findsNothing);
    expect(find.text('Odebrané položky:'), findsNothing);
    expect(find.textContaining('+ Vstupenka'), findsNothing);
    expect(find.byIcon(Icons.undo_outlined), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Poslat e-mail'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
  Future<void> pumpPreview(
      WidgetTester tester, Map<String, dynamic> data) async {
    await EasyLocalization.ensureInitialized();
    await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('cs')],
        path: 'unused',
        startLocale: const Locale('cs'),
        assetLoader: _Translations(),
        child: Builder(
            builder: (context) => MaterialApp(builder: DependencyMaterialBridge.builder,
                locale: context.locale,
                localizationsDelegates: [...context.localizationDelegates, ...GlobalMaterialLocalizations.delegates],
                supportedLocales: context.supportedLocales,
                home: Scaffold(
                    body: SingleChildScrollView(
                        child: ProductChangesPreview(
                            changes: OrderChangeSummary.fromJson(data))))))));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> fixture() => jsonDecode(
      File('test/fixtures/order_changes/cancellation_and_product_edit.json')
          .readAsStringSync());

  testWidgets(
      'product removal keeps survivor context and no cancellation label',
      (tester) async {
    final data = fixture();
    final product = data['cancelledTickets'][0]['products'][0];
    data['cancelledTickets'] = [];
    data['productChanges'] = [
      {
        'id': 2,
        'ticket_symbol': 'SURVIVOR',
        'added': [],
        'removed': [product],
        'changed': []
      }
    ];
    await pumpPreview(tester, data);
    expect(find.text('Stornované vstupenky:'), findsNothing);
    expect(find.textContaining('- Místo'), findsOneWidget);
    expect(find.text('Vstupenka SURVIVOR'), findsOneWidget);
    expect(
        tester.widget<Text>(find.text('Vstupenka SURVIVOR')).style?.decoration,
        isNull);
    expect(find.textContaining('Změny produktů na vstupence'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'multiple free cancellations render on a narrow screen without product removals',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = fixture();
    data['cancelledTickets'] = [
      {'id': 1, 'ticket_symbol': 'FIRST', 'products': []},
      {'id': 3, 'ticket_symbol': 'THIRD', 'products': []},
    ];
    data['productChanges'] = [];
    data['referenceTotal'] = 0;
    data['currentTotal'] = 0;
    await pumpPreview(tester, data);
    expect(find.text('Vstupenka FIRST'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Vstupenka FIRST')).style?.decoration,
        TextDecoration.lineThrough);
    expect(find.text('Vstupenka THIRD'), findsOneWidget);
    expect(find.text('Odebrané položky:'), findsNothing);
    expect(find.text('Změna celkové ceny'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'ticket blocks retain original price transitions on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = fixture();
    data['productChanges'][0]['changed'][0]['to']['title'] = 'Nové místo';
    await pumpPreview(tester, data);
    expect(find.byIcon(Icons.list_alt_outlined), findsOneWidget);
    expect(find.text('• Nové místo:'), findsNWidgets(2));
    expect(find.byIcon(Icons.arrow_forward), findsNWidgets(3));
    expect(find.text('Stornované vstupenky:'), findsNothing);
    expect(find.text('Změna ceny položek:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
      'canonical change context identifies other tickets without comparing products again',
      () {
    final changes = OrderChangeSummary.fromJson(fixture());
    expect(changes.hasChangesOutside(2), isTrue);
    final data = fixture()..['cancelledTickets'] = [];
    expect(OrderChangeSummary.fromJson(data).hasChangesOutside(2), isFalse);
  });
  testWidgets('seat changes retain both seat labels in the update preview', (
    tester,
  ) async {
    final data = fixture();
    data['cancelledTickets'] = [];
    data['productChanges'] = [
      {
        'id': 2,
        'ticket_symbol': 'SP26',
        'added': [],
        'removed': [],
        'changed': [
          {
            'from': {
              'id': 7,
              'title': 'Místo',
              'price': 100,
              'spot_title': '7F',
            },
            'to': {'id': 7, 'title': 'Místo', 'price': 100, 'spot_title': '6G'},
          },
        ],
      },
    ];
    data['referenceTotal'] = 100;
    data['currentTotal'] = 100;
    await pumpPreview(tester, data);
    expect(find.textContaining('7F', findRichText: true), findsOneWidget);
    expect(find.textContaining('6G', findRichText: true), findsOneWidget);
    expect(find.text('Změna celkové ceny'), findsNothing);
  });

  testWidgets(
    'persisted product change exposes the existing update email action',
    (tester) async {
      await EasyLocalization.ensureInitialized();
      var tapped = false;
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('cs')],
          path: 'unused',
          startLocale: const Locale('cs'),
          assetLoader: _Translations(),
          child: Builder(
            builder: (context) => MaterialApp(
              builder: DependencyMaterialBridge.builder,
              locale: context.locale,
              localizationsDelegates: [
                ...context.localizationDelegates,
                ...GlobalMaterialLocalizations.delegates,
              ],
              supportedLocales: context.supportedLocales,
              home: Scaffold(
                body: ProductInfoPanel(
                  order: OrderModel(
                    state: 'sent',
                    price: 150,
                    data: {'email': 'host@example.invalid'},
                  ),
                  paymentInfo: null,
                  ticket: TicketModel(ticketSymbol: 'SP26'),
                  orderHistory: OrderHistoryInfo(isNewerVersionAvailable: true),
                  onSendUpdate: () => tapped = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.email_outlined), findsOneWidget);
      expect(tapped, isFalse);
      await tester.tap(find.byIcon(Icons.email_outlined));
      expect(tapped, isTrue);
    },
  );
}
