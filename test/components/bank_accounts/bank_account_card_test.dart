import 'dart:convert';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/views/order_state_cell.dart';
import 'package:fstapp/components/eshop/views/order_state_column_width.dart';
import 'package:trina_grid/trina_grid.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/_shared/copy_button.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/bank_accounts/views/unit_bank_account_card.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    loader.addFont(Future.value(ByteData.sublistView(
        File('test/fixtures/ticket_fonts/Roboto.ttf').readAsBytesSync())));
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('order status fits both indicators at ${scale}x',
        (tester) async {
      await EasyLocalization.ensureInitialized();
      final order = OrderModel(
          state: OrderModel.expiredState,
          paymentInfoModel: PaymentInfoModel(
              bankAccount: 42,
              amount: 100,
              paid: 0,
              bankSyncWarning: const BankSyncWarning(
                  code: 'suspended', bankAccountTitle: 'Test')));
      await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'unused',
        startLocale: const Locale('en'),
        assetLoader: const _Translations(),
        child: Builder(
            builder: (context) => MaterialApp(
                  locale: context.locale,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  home: Scaffold(
                      body: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: DefaultTextStyle(
                      style: TrinaGridStyleConfig.defaultLightCellTextStyle,
                      child: Builder(
                          builder: (context) => Center(
                                  child: SizedBox(
                                width: orderStateColumnWidth(context, [order]),
                                height: 56,
                                child: OrderStateCell(
                                    label: OrderModel.statesDataGridToUpper(
                                        order.stateLabel),
                                    background: Colors.orange.shade100,
                                    order: order,
                                    expired: true),
                              ))),
                    ),
                  )),
                )),
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      final label =
          find.text(OrderModel.statesDataGridToUpper(order.stateLabel));
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('narrow account card and copyable warning: ${brightness.name}',
        (tester) async {
      await EasyLocalization.ensureInitialized();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? clipboard;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData')
          clipboard = call.arguments['text'];
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      var opened = 0;
      var unlinked = 0;
      final account = BankAccountModel.fromJson({
        'id': 42,
        'is_admin': true,
        'title': 'Scout festival account for international participants',
        'account_number': '123456789/2010',
        'supported_currencies': ['CZK', 'EUR', 'USD'],
        'bank_sync': {'state': 'suspended', 'mode': 'api'},
        'bank_sync_warning': {
          'code': 'suspended',
          'bank_account_title': 'Scout festival account',
          'contacts': [
            {'name': 'Jane Admin', 'email': 'admin@example.test'},
            {'name': 'Jane Duplicate', 'email': 'ADMIN@example.test'},
          ],
        },
      });
      final previewKey = GlobalKey();
      await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'unused',
        startLocale: const Locale('en'),
        assetLoader: const _Translations(),
        child: Builder(
            builder: (context) => RepaintBoundary(
                  key: previewKey,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme:
                        ThemeData(brightness: brightness, fontFamily: 'Roboto'),
                    locale: context.locale,
                    localizationsDelegates: context.localizationDelegates,
                    supportedLocales: context.supportedLocales,
                    home: Scaffold(
                        body: SafeArea(
                            child: ReorderableListView(
                      onReorder: (_, __) {},
                      buildDefaultDragHandles: false,
                      children: [
                        UnitBankAccountCard(
                            key: const ValueKey(42),
                            account: account,
                            primaryCurrencies: const {'CZK', 'EUR'},
                            index: 0,
                            onOpen: () => opened++,
                            onUnlink: () => unlinked++)
                      ],
                    ))),
                  ),
                )),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(ReorderableDragStartListener), findsOneWidget);
      expect(find.text(account.title!), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.tap(find.byIcon(Icons.link_off));
      expect(opened, 1);
      expect(unlinked, 1);
      expect(tester.takeException(), isNull);
      Future<void> capture(String suffix) async {
        if (!const bool.fromEnvironment('BANK_UI_SCREENSHOTS')) return;
        final boundary = previewKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/bank-$suffix-${brightness.name}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('card');
      final warningButton =
          find.widgetWithIcon(IconButton, Icons.warning_amber_rounded);
      final tooltip = tester.widget<IconButton>(warningButton).tooltip!;
      expect(tooltip, contains('Jane Admin'));
      expect(tooltip, isNot(contains('Jane Duplicate')));
      expect(tooltip, isNot(contains('admin@example.test')));
      await tester.tap(warningButton);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SelectableText, 'admin@example.test'),
          findsOneWidget);
      expect(find.byType(CopyButton), findsOneWidget);
      await capture('dialog');
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      expect(clipboard, 'admin@example.test');
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
