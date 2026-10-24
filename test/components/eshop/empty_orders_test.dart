import 'package:fstapp/components/eshop/views/order_email_repair_dialog.dart';
import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/eshop/views/orders_content.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// Supabase's storage fixture uses its shared_preferences dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Router extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        AutoRoute(
            path: '/:${AppRouter.linkFormatted}',
            page: PageInfo('OrdersFixture',
                builder: (_) => const Scaffold(body: OrdersContent()))),
      ];
}

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var fail = false;
  var includeOrder = false;
  var repairReads = 0;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        final isOrders = request.url.path.endsWith('/get_orders_tab_data');
        if (request.url.path.endsWith('/get_order_history')) repairReads++;
        if (fail && isOrders) {
          return http.Response(
              jsonEncode({'message': 'Unavailable', 'code': 'XX000'}), 500,
              request: request, headers: {'content-type': 'application/json'});
        }
        final data = isOrders
            ? {
                for (final key in [
                  'orders',
                  'spots',
                  'products',
                  'product_types',
                  'tickets',
                  'payment_info',
                  'forms',
                  'order_product_ticket',
                  'orders_history',
                  'users'
                ])
                  key: key == 'orders' && includeOrder
                    ? [{'id': 4, 'order_sequence': 4, 'order_symbol': 'ORDER4', 'occasion': 1, 'state': 'ordered',
                        'currency_code': 'CZK', 'data': {'email': 'customer@example.invalid'}}]
                    : <dynamic>[],
              }
            : {'id': 1, 'unit': 1, 'link': 'empty', 'data': {}, 'features': []};
        return http.Response(jsonEncode(data), 200,
            request: request, headers: {'content-type': 'application/json'});
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> showOrders(WidgetTester tester, {String path = '/empty'}) async {
    final router = _Router();
    addTearDown(router.dispose);
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('cs')],
      startLocale: const Locale('cs'),
      path: 'unused',
      assetLoader: _Translations(),
      child: Builder(
          builder: (context) => MaterialApp.router(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                routerConfig: router.config(
                    deepLinkBuilder: (_) => DeepLink.path(path)),
              )),
    ));
    if (includeOrder) {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('new occasion without orders shows an empty state, not an error',
      (tester) async {
    fail = false;
    await showOrders(tester);
    expect(find.text('Zatím nejsou žádné objednávky.'), findsOneWidget);
    expect(find.text('Došlo k neočekávané chybě.'), findsNothing);
    // Keep the customer-facing overview action in the actual configured grid,
    // including occasions without orders and without ticket/waitlist features.
    final grid = tester.widget<SingleTableDataGrid<OrderModel>>(
        find.byType(SingleTableDataGrid<OrderModel>));
    final overview = grid.controller.columns.singleWhere(
        (column) => column.field == EshopColumnIds.ORDER_OVERVIEW);
    expect(overview.readOnly, isTrue);
    expect(overview.renderer, isNotNull);
  });

  testWidgets('failed request remains an error with retry', (tester) async {
    fail = true;
    await showOrders(tester);
    expect(find.text('Došlo k neočekávané chybě.'), findsOneWidget);
    expect(find.text('Zatím nejsou žádné objednávky.'), findsNothing);
    fail = false;
    await tester.tap(find.text('Zkusit znovu'));
    await tester.pumpAndSettle();
    expect(find.text('Zatím nejsou žádné objednávky.'), findsOneWidget);
    expect(find.text('Došlo k neočekávané chybě.'), findsNothing);
  });
  for (final source in ['', '&orderMessageId=old-resolved-message']) {
    testWidgets('notification selects a healthy order without email repair: $source', (tester) async {
      fail = false;
      includeOrder = true;
      repairReads = 0;
      addTearDown(() => includeOrder = false);
      await showOrders(tester, path: '/empty?orderId=4$source');
      expect(find.byType(OrderEmailRepairDialog), findsNothing);
      expect(repairReads, 0);
      final grid = tester.widget<SingleTableDataGrid<OrderModel>>(
        find.byType(SingleTableDataGrid<OrderModel>)).controller;
      expect(grid.stateManager.currentCell?.value, 'ORDER4');
      expect(grid.highlightedRow, isNotNull);
      await tester.pump(const Duration(seconds: 3));
    });
  }

}
