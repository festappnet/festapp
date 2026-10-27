import 'package:fstapp/components/notification_center/notification_center_controller.dart';
import 'package:fstapp/components/notification_center/notification_center_panel.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/eshop/views/order_email_repair_dialog.dart';
import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
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
  var groupSelection = false;
  Map<String, dynamic>? groupRequest;
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
        if (isOrders && groupSelection) groupRequest = jsonDecode(request.body) as Map<String,dynamic>;
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
        if (isOrders && groupSelection) {
          data['orders'] = [for (final id in [4,5,6,7,8,9,10]) {'id':id,'created_at':'2026-10-27T12:00:00Z','order_sequence':id,'order_symbol':'ORDER$id','occasion':1,'state':groupRequest?['p_notification_group']?['id'].toString().contains('order_cancelled')==true && id!=10?'storno':'ordered','currency_code':'CZK','data':{'email':'customer@example.invalid'}}];
          data['notification_order_ids'] = [4,5,6,7,8,9];
        }
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
          builder: (context) => MaterialApp.router(builder: DependencyMaterialBridge.builder,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: [...context.localizationDelegates, ...GlobalMaterialLocalizations.delegates],
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
      expect(grid.stateManager.hasFocus, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(grid.stateManager.hasFocus, isTrue);
      final current = grid.stateManager.currentCell!.key;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(grid.stateManager.currentCell!.key, isNot(current));
    });
  }

  for (final selectedKind in ['order_created','order_cancelled']) {
  testWidgets('$selectedKind navigation checks all six matching orders in the existing orders RPC', (tester) async {
    fail = false; includeOrder = true; groupSelection = true; groupRequest = null;
    addTearDown(() { includeOrder = false; groupSelection = false; });
    final group = {'id':'occasion-kind:1:$selectedKind','organization':3,'snapshot':7,'timezone':'Europe/Prague'};
    await showOrders(tester, path: Uri(path:'/empty',queryParameters:{'notificationGroup':jsonEncode(group)}).toString());
    final grid = tester.widget<SingleTableDataGrid<OrderModel>>(find.byType(SingleTableDataGrid<OrderModel>)).controller;
    expect(grid.stateManager.refRows.originalList.map((row)=>row.checked), [true,true,true,true,true,true,false]);
    expect(groupRequest?['p_notification_group'],group);
    expect(find.byType(OrderEmailRepairDialog),findsNothing);
  });

  }

  for (final kind in ['order_created', 'order_cancelled']) {
  testWidgets('localized $kind names fit one line and metadata retains exact counts', (tester) async {
    final loader = FontLoader('NotificationPreviewFont')..addFont(Future.value(ByteData.sublistView(File('test/fixtures/ticket_fonts/Roboto.ttf').readAsBytesSync())));
    await loader.load();
    final c = NotificationCenterController();
    addTearDown(c.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    c.snapshotAt = DateTime(2026,10,27);
    c.items = [NotificationItem.fromJson({'id':'names','kind':kind,'occasionId':1,'occasionTitle':'Ples','day':'2026-10-26','data':{'activityCount':8,'placeCount':18,'relatedOrders':true,'previewContacts':[{'name':'Jana','surname':'Czernérová'},{'name':'Radomír','surname':'Káňa'},{'name':'Miroslav','surname':'Krajíček'}]}})];
    for(final width in [800.0,390.0,320.0]) {
      tester.view.physicalSize = Size(width,1200); tester.view.devicePixelRatio=1;
      await tester.pumpWidget(EasyLocalization(supportedLocales:const [Locale('cs')],startLocale:const Locale('cs'),path:'unused',assetLoader:_Translations(),child:Builder(builder:(context)=>MaterialApp(builder:DependencyMaterialBridge.builder,locale:context.locale,supportedLocales:context.supportedLocales,localizationsDelegates:[...context.localizationDelegates,...GlobalMaterialLocalizations.delegates],theme:ThemeData(fontFamily:'NotificationPreviewFont'),home:NotificationCenterPanel(controller:c,onDetail:(_){})))));
      await tester.pumpAndSettle();
      final preview = tester.widget<Text>(find.byKey(const ValueKey('notification-preview-names')));
      expect(preview.maxLines,1);
      if(width>=390) {
        expect(preview.data,contains('Jana Czernérová'));
        expect(preview.data,contains('další'));
      } else {
        expect(preview.data,anyOf(contains('Jana Czernérová'),kind == 'order_cancelled' ? '8 zrušených objednávek' : '8 nových objednávek'));
      }
      expect(preview.data,isNot(contains('…')));
      expect(find.text('Včera · 8 objednávek · 18 míst'),findsOneWidget);
      expect(find.text(kind == 'order_cancelled'?'Zrušené objednávky':'Nové objednávky'),findsOneWidget);
      expect(find.byKey(const ValueKey('notification-age-names')),findsOneWidget);
      expect(tester.takeException(),isNull);
    }
    c.items.first.data.remove('placeCount');
    c.items.first.data['allowsMultiple'] = true;
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.textContaining('Počet míst není dostupný'), findsOneWidget);
    c.items.first.data['allowsMultiple'] = false;
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.textContaining('Počet míst není dostupný'), findsNothing);
  });

  }
}
