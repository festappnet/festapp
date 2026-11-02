import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:flutter/material.dart' as sdk;
import 'package:fstapp/components/notification_center/notification_center_bell.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';

import 'dart:async';

import '../../support/navigation_fixture.dart';

import 'package:fstapp/components/navigation/root_route_navigation.dart';
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
      page: PageInfo(
        'OrdersFixture',
        builder: (_) => const Scaffold(body: OrdersContent()),
      ),
    ),
  ];
}

class _ProductionShapeRouter extends RootStackRouter {
  _ProductionShapeRouter({this.showBell = false});
  final bool showBell;
  AutoRoute fixture(AutoRoute route) {
    if (route is RedirectRoute) return route;
    Widget build(BuildContext context) {
      switch (route.name) {
        case 'ReservationsRoute':
          return Scaffold(
            appBar: showBell
                ? AppBar(actions: const [NotificationCenterBell()])
                : null,
            body: const AutoRouter(),
          );
        case 'ReservationsTabsRoute':
          return const RoutedTabScaffold(
            tabs: [
              RoutedTabDefinition(
                slug: 'orders',
                route: OrdersNavigationRoute(),
                label: 'Orders',
                icon: Icons.list,
              ),
            ],
          );
        case 'OrdersNavigationRoute':
          return const AutoRouter();
        case 'OrdersTabsRoute':
          return const RoutedTabScaffold(
            tabs: [
              RoutedTabDefinition(
                slug: 'current',
                route: OrdersCurrentRoute(),
                label: 'Current',
                icon: Icons.list,
              ),
              RoutedTabDefinition(
                slug: 'history',
                route: OrdersHistoryRoute(),
                label: 'History',
                icon: Icons.history,
              ),
            ],
          );
        case 'OrdersCurrentRoute':
          return const OrdersContent();
        default:
          return Text(route.name);
      }
    }

    return route.copyWith(
      guards: [],
      page: PageInfo(route.name, builder: (_) => Builder(builder: build)),
      children: route.children?.map(fixture).toList(),
    );
  }

  @override
  List<AutoRoute> get routes => AppRouter().routes
      .where((route) => route.name == 'ReservationsRoute')
      .map(fixture)
      .toList();
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
  var bellEntry = false;
  Map<String, dynamic>? groupRequest;
  setUp(() {
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasion: OccasionModel(
        id: 1,
        unit: 1,
        link: 'empty',
        isOpen: true,
        isHidden: false,
        isPromoted: false,
      ),
    );
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
  });
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        final isOrders = request.url.path.endsWith('/get_orders_tab_data');
        if (bellEntry &&
            (request.url.path.endsWith('/get_notification_center_badge') ||
                request.url.path.endsWith(
                  '/get_notification_center_daily_overview',
                ))) {
          final overview = request.url.path.endsWith(
            '/get_notification_center_daily_overview',
          );
          return http.Response(
            jsonEncode({
              'enabled': true,
              'feedSupported': true,
              'timelineSupported': true,
              'dailySupported': true,
              'unread': true,
              'lastSequence': 7,
              'readThrough': 0,
              if (overview) ...{
                'snapshot': 7,
                'snapshotAt': DateTime.now().toUtc().toIso8601String(),
                'previousReadThrough': 0,
                'items': [
                  {
                    'id': 'occasion-kind:1:order_created',
                    'kind': 'order_created',
                    'occasionId': 1,
                    'occasionTitle': 'Ples',
                    'occasionLink': 'empty',
                    'sequence': 7,
                    'occurredAt': DateTime.now().toUtc().toIso8601String(),
                    'data': {
                      'activityCount': 6,
                      'relatedOrders': true,
                      'placeCount': 6,
                      'previewContacts': [
                        {'name': 'Jan', 'surname': 'Novák'},
                      ],
                    },
                  },
                ],
                'occasions': [],
              },
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (isOrders && groupSelection)
          groupRequest = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/get_order_history')) repairReads++;
        if (fail && isOrders) {
          return http.Response(
            jsonEncode({'message': 'Unavailable', 'code': 'XX000'}),
            500,
            request: request,
            headers: {'content-type': 'application/json'},
          );
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
                  'users',
                ])
                  key: key == 'orders' && includeOrder
                      ? [
                          {
                            'id': 4,
                            'order_sequence': 4,
                            'order_symbol': 'ORDER4',
                            'occasion': 1,
                            'state': 'ordered',
                            'currency_code': 'CZK',
                            'data': {'email': 'customer@example.invalid'},
                          },
                        ]
                      : <dynamic>[],
              }
            : {'id': 1, 'unit': 1, 'link': 'empty', 'data': {}, 'features': []};
        if (isOrders && groupSelection) {
          data['orders'] = [
            for (final id in [4, 5, 6, 7, 8, 9, 10])
              {
                'id': id,
                'created_at': '2026-10-27T12:00:00Z',
                'order_sequence': id,
                'order_symbol': 'ORDER$id',
                'occasion': 1,
                'state':
                    groupRequest?['p_notification_group']?['id']
                                .toString()
                                .contains('order_cancelled') ==
                            true &&
                        id != 10
                    ? 'storno'
                    : 'ordered',
                'currency_code': 'CZK',
                'data': {'email': 'customer@example.invalid'},
              },
          ];
          data['notification_order_ids'] = [4, 5, 6, 7, 8, 9];
        }
        return http.Response(
          jsonEncode(data),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> showOrders(
    WidgetTester tester, {
    String path = '/empty',
    RootStackRouter? externalRouter,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = externalRouter ?? _Router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('cs')],
        startLocale: const Locale('cs'),
        path: 'unused',
        assetLoader: _Translations(),
        child: Builder(
          builder: (context) => MaterialApp.router(
            builder: (context, child) => DependencyMaterialBridge.builder(
              context,
              sdk.Material(child: child),
            ),
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: [
              ...context.localizationDelegates,
              ...GlobalMaterialLocalizations.delegates,
            ],
            routerConfig: router.config(
              deepLinkBuilder: (_) => DeepLink.path(path),
            ),
          ),
        ),
      ),
    );
    if (includeOrder) {
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'new occasion without orders shows an empty state, not an error',
    (tester) async {
      fail = false;
      await showOrders(tester);
      expect(find.text('Zatím nejsou žádné objednávky.'), findsOneWidget);
      expect(find.text('Došlo k neočekávané chybě.'), findsNothing);
      // Symbols remain the explicit detail entry point after moving the
      // customer overview action into the detail header.
      final grid = tester.widget<SingleTableDataGrid<OrderModel>>(
        find.byType(SingleTableDataGrid<OrderModel>),
      );
      final overview = grid.controller.columns.singleWhere(
        (column) => column.field == EshopColumnIds.ORDER_SYMBOL,
      );
      expect(overview.readOnly, isTrue);
      expect(overview.renderer, isNotNull);
    },
  );

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
    testWidgets(
      'notification selects a healthy order without email repair: $source',
      (tester) async {
        fail = false;
        includeOrder = true;
        repairReads = 0;
        addTearDown(() => includeOrder = false);
        await showOrders(tester, path: '/empty?orderId=4$source');
        expect(find.byType(OrderEmailRepairDialog), findsNothing);
        expect(repairReads, 0);
        final grid = tester
            .widget<SingleTableDataGrid<OrderModel>>(
              find.byType(SingleTableDataGrid<OrderModel>),
            )
            .controller;
        expect(grid.stateManager.currentCell?.value, 'ORDER4');
        expect(grid.stateManager.hasFocus, isTrue);
        await tester.pump(const Duration(seconds: 3));
        expect(grid.stateManager.hasFocus, isTrue);
        final current = grid.stateManager.currentCell!.key;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(grid.stateManager.currentCell!.key, isNot(current));
      },
    );
  }

  for (final selectedKind in ['order_created', 'order_cancelled']) {
    testWidgets(
      '$selectedKind navigation selects all six matching rows in the existing orders RPC',
      (tester) async {
        fail = false;
        includeOrder = true;
        groupSelection = true;
        groupRequest = null;
        addTearDown(() {
          includeOrder = false;
          groupSelection = false;
        });
        final group = {
          'id': 'occasion-kind:1:$selectedKind',
          'organization': 3,
          'snapshot': 7,
          'timezone': 'Europe/Prague',
        };
        await showOrders(
          tester,
          path: Uri(
            path: '/empty',
            queryParameters: {'notificationGroup': jsonEncode(group)},
          ).toString(),
        );
        final grid = tester
            .widget<SingleTableDataGrid<OrderModel>>(
              find.byType(SingleTableDataGrid<OrderModel>),
            )
            .controller;
        expect(
          grid.stateManager.refRows.originalList.map(
            (row) => grid.stateManager.isSelectedRow(row.key),
          ),
          [true, true, true, true, true, true, false],
        );
        expect(groupRequest?['p_notification_group'], group);
        expect(find.byType(OrderEmailRepairDialog), findsNothing);
      },
    );
  }

  testWidgets(
    'group notification selects orders when the real retained tab is already open',
    (tester) async {
      fail = false;
      includeOrder = true;
      groupSelection = true;
      groupRequest = null;
      addTearDown(() {
        includeOrder = false;
        groupSelection = false;
      });
      final router = FixtureRouter(Access())
        ..ordersCurrentBuilder = (_) => const Material(child: OrdersContent());
      await showOrders(
        tester,
        path: '/empty/reservations/orders/current',
        externalRouter: router,
      );
      final group = {
        'id': 'occasion-kind:1:order_created',
        'organization': 3,
        'snapshot': 7,
        'timezone': 'Europe/Prague',
      };
      unawaited(
        pushRootPath(
          router,
          Uri(
            path: '/empty/reservations/orders/current',
            queryParameters: {'notificationGroup': jsonEncode(group)},
          ).toString(),
        ),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final grids = find.byType(SingleTableDataGrid<OrderModel>);
      final grid = tester
          .widget<SingleTableDataGrid<OrderModel>>(grids.last)
          .controller;
      expect(groupRequest?['p_notification_group'], group);
      expect(
        grid.stateManager.refRows.originalList.map(
          (row) => grid.stateManager.isSelectedRow(row.key),
        ),
        [true, true, true, true, true, true, false],
      );
      await grid.reloadIfClean();
      await tester.pumpAndSettle();
      expect(
        grid.stateManager.refRows.originalList.map(
          (row) => grid.stateManager.isSelectedRow(row.key),
        ),
        [true, true, true, true, true, true, false],
        reason:
            'automatic clean reload must preserve the notification selection',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final returnFromHistory in [false, true]) {
    testWidgets(
      'production route shape applies group after retained tab return=$returnFromHistory',
      (tester) async {
        fail = false;
        includeOrder = true;
        groupSelection = true;
        groupRequest = null;
        addTearDown(() {
          includeOrder = false;
          groupSelection = false;
        });
        final router = _ProductionShapeRouter();
        const path = '/empty/reservations/orders/current';
        await showOrders(tester, path: path, externalRouter: router);
        if (returnFromHistory) {
          unawaited(
            router.navigate(
              rootRouteForPath(router, '/empty/reservations/orders/history'),
            ),
          );
          for (var i = 0; i < 20; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        }
        final group = {
          'id': 'occasion-kind:1:order_created',
          'organization': 3,
          'snapshot': 7,
          'timezone': 'Europe/Prague',
        };
        unawaited(
          pushRootPath(
            router,
            Uri(
              path: path,
              queryParameters: {'notificationGroup': jsonEncode(group)},
            ).toString(),
          ),
        );
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final grid = tester
            .widget<SingleTableDataGrid<OrderModel>>(
              find.byType(SingleTableDataGrid<OrderModel>).last,
            )
            .controller;
        expect(groupRequest?['p_notification_group'], group);
        expect(
          grid.stateManager.refRows.originalList.map(
            (row) => grid.stateManager.isSelectedRow(row.key),
          ),
          [true, true, true, true, true, true, false],
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final kind in ['order_created', 'order_cancelled']) {
    testWidgets(
      'localized $kind names fit one line and metadata retains exact counts',
      (tester) async {
        final loader = FontLoader('NotificationPreviewFont')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('test/fixtures/ticket_fonts/Roboto.ttf').readAsBytesSync(),
              ),
            ),
          );
        await loader.load();
        final c = NotificationCenterController();
        addTearDown(c.dispose);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        c.snapshotAt = DateTime(2026, 10, 27);
        c.items = [
          NotificationItem.fromJson({
            'id': 'names',
            'kind': kind,
            'occasionId': 1,
            'occasionTitle': 'Ples',
            'day': '2026-10-26',
            'data': {
              'activityCount': 8,
              'placeCount': 18,
              'relatedOrders': true,
              'previewContacts': [
                {'name': 'Jana', 'surname': 'Czernérová'},
                {'name': 'Radomír', 'surname': 'Káňa'},
                {'name': 'Miroslav', 'surname': 'Krajíček'},
              ],
            },
          }),
        ];
        for (final width in [800.0, 390.0, 320.0]) {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            EasyLocalization(
              supportedLocales: const [Locale('cs')],
              startLocale: const Locale('cs'),
              path: 'unused',
              assetLoader: _Translations(),
              child: Builder(
                builder: (context) => MaterialApp(
                  builder: DependencyMaterialBridge.builder,
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: [
                    ...context.localizationDelegates,
                    ...GlobalMaterialLocalizations.delegates,
                  ],
                  theme: ThemeData(fontFamily: 'NotificationPreviewFont'),
                  home: NotificationCenterPanel(
                    controller: c,
                    onDetail: (_) {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final preview = tester.widget<Text>(
            find.byKey(const ValueKey('notification-preview-names')),
          );
          expect(preview.maxLines, 1);
          if (width >= 390) {
            expect(preview.data, contains('Jana Czernérová'));
            expect(preview.data, contains('další'));
          } else {
            expect(
              preview.data,
              anyOf(
                contains('Jana Czernérová'),
                kind == 'order_cancelled'
                    ? '8 stornovaných objednávek'
                    : '8 nových objednávek',
              ),
            );
          }
          expect(preview.data, isNot(contains('…')));
          expect(find.text('Včera · 8 objednávek · 18 míst'), findsOneWidget);
          expect(
            find.text(
              kind == 'order_cancelled'
                  ? 'Stornované objednávky'
                  : 'Nové objednávky',
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('notification-age-names')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
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
      },
    );
  }
  testWidgets(
    'actual bell click selects matching order rows through production routing',
    (tester) async {
      fail = false;
      includeOrder = true;
      groupSelection = true;
      bellEntry = true;
      groupRequest = null;
      addTearDown(() {
        includeOrder = false;
        groupSelection = false;
        bellEntry = false;
      });
      const actor = '00000000-0000-4000-8000-000000000001';
      final token = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
                'sub': actor,
              }),
            ),
          )
          .replaceAll('=', '');
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode({
          'access_token': 'eyJhbGciOiJIUzI1NiJ9.$token.fixture',
          'refresh_token': 'fixture',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': actor,
            'aud': 'authenticated',
            'role': 'authenticated',
            'created_at': '2026-01-01T00:00:00Z',
          },
        }),
      );
      final router = _ProductionShapeRouter(showBell: true);
      await showOrders(
        tester,
        path: '/empty/reservations/orders/current',
        externalRouter: router,
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotificationCenterBell), findsOneWidget);
      final dynamic bellState = tester.state(
        find.byType(NotificationCenterBell),
      );
      final NotificationCenterController c = bellState.controller;
      await tester.runAsync(c.refreshBadge);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NotificationCenterBell));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('notification-item-occasion-kind:1:order_created'),
        ),
      );
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final grid = tester
          .widget<SingleTableDataGrid<OrderModel>>(
            find.byType(SingleTableDataGrid<OrderModel>).last,
          )
          .controller;
      expect(groupRequest?['p_notification_group']?['snapshot'], 7);
      final visibleChecks = tester
          .widgetList<sdk.Checkbox>(find.byType(sdk.Checkbox))
          .map((x) => x.value)
          .toList();
      expect(
        visibleChecks.where((x) => x == true),
        isEmpty,
        reason: 'notification selection must not check bulk-action checkboxes',
      );
      expect(
        grid.stateManager.refRows.originalList.map(
          (row) => grid.stateManager.isSelectedRow(row.key),
        ),
        [true, true, true, true, true, true, false],
      );
    },
  );
}
