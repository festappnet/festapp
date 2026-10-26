import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:trina_grid/trina_grid.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

class _RendererState extends Fake implements TrinaGridStateManager {}

class _Router extends RootStackRouter {
  AutoRoute page(String name, String path, WidgetBuilder builder,
          {List<AutoRoute>? children}) =>
      AutoRoute(
          page: PageInfo(name, builder: (_) => Builder(builder: builder)),
          path: path,
          children: children);

  @override
  List<AutoRoute> get routes => [
        page('Reservations', '/:${AppRouter.linkFormatted}/reservations',
            (_) => const AutoRouter(),
            children: [
              page('Tabs', '', (_) => const AutoRouter(), children: [
                page('Tickets', 'tickets', (context) {
                  final column = EshopColumns.generateColumns(
                      context, [EshopColumnIds.TICKET_BATCH]).single;
                  final cell = TrinaCell(value: 'drahe');
                  return Scaffold(
                      body: column.renderer!(TrinaColumnRendererContext(
                          column: column,
                          rowIdx: 0,
                          row: TrinaRow(cells: {
                            EshopColumnIds.TICKET_BATCH: cell,
                            EshopColumnIds.TICKET_MODEL_REFERENCE: TrinaCell(
                                value: TicketModel(batch: {
                              'id': 'batch-1',
                              'title': 'drahe',
                            }))
                          }),
                          cell: cell,
                          stateManager: _RendererState())));
                }),
                page('Orders', 'orders', (_) => const AutoRouter(), children: [
                  page('OrderTabs', '', (_) => const AutoRouter(), children: [
                    page('Batches', 'pregenerated', (_) => const AutoRouter(),
                        children: [
                          page('BatchDetail', ':batchId',
                              (_) => const Text('BATCH DETAIL')),
                        ]),
                  ]),
                  page('OrdersNotFound', '*', (_) => const Text('NOT FOUND')),
                ]),
              ]),
              page('NotFound', '*', (_) => const Text('NOT FOUND')),
            ]),
      ];
}

void main() {
  WidgetEnvironmentFixture.register();
  testWidgets(
      'ticket batch link escapes nested wildcard and opens batch detail',
      (tester) async {
    final environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync()));
    final router = _Router();
    addTearDown(router.dispose);
    await environment.pumpWidget(
        tester,
        MaterialApp.router(builder: DependencyMaterialBridge.builder,
            routerConfig: router.config(
                deepLinkBuilder: (_) =>
                    DeepLink.path('/occasion-a/reservations/tickets'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('drahe'));
    await tester.pumpAndSettle();
    expect(find.text('NOT FOUND'), findsNothing);
    expect(find.text('BATCH DETAIL'), findsOneWidget);
    expect(router.currentUrl,
        '/occasion-a/reservations/orders/pregenerated/batch-1');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
