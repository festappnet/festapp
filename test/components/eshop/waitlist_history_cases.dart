import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'dart:convert';
import 'dart:io';
import 'package:fstapp/components/eshop/views/order_state_display.dart';
import 'package:fstapp/components/eshop/views/order_state_cell.dart';
import 'package:fstapp/components/eshop/models/order_admin_detail.dart';
import 'package:fstapp/components/forms/models/form_response_model.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/order_data_ticket_model.dart';
import 'package:fstapp/components/eshop/models/order_data_product_model.dart';
import 'package:fstapp/components/eshop/models/orders_history_model.dart';
import 'package:fstapp/components/eshop/models/waitlist_summary_model.dart';
import 'package:festapp_core/time.dart' as zones;
import 'package:timezone/timezone.dart' as tz;

late WidgetEnvironmentFixture _environment;

class _TestTranslations extends easy.AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync());
}

class _RendererState extends Fake implements TrinaGridStateManager {}

void main() {
  WidgetEnvironmentFixture.register();
  setUp(() {
    _environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync()));
    if (!tz.timeZoneDatabase.isInitialized) {
      zones.OccasionTimeContext.initializeTimeZones();
    }
    final previousZone = tz.local;
    addTearDown(() => tz.setLocalLocation(previousZone));
    tz.setLocalLocation(tz.getLocation('Europe/Prague'));
  });
  testWithWidgetEnvironment(() => _environment,
      'single offered projection preserves canonical state and multi order label',
      () {
    final order = OrderModel(state: 'waitlisted');
    order.waitlistSummary = WaitlistSummaryModel.fromJson({
      'counts': {'offered': 1}
    });
    expect(order.stateLabel, 'Nabídnuto');
    expect(order.state, 'waitlisted');
    order.waitlistSummary = WaitlistSummaryModel.fromJson({
      'counts': {'offered': 1, 'waiting': 1}
    });
    expect(order.stateLabel, OrderModel.stateToLocale('waitlisted'));
    order.state = 'paid';
    expect(order.stateLabel, OrderModel.stateToLocale('paid'));
  });
  testWidgetsWithEnvironment(() => _environment,
      'immutable offer history renders action and expiry in both views',
      (tester) async {
    final history = OrderHistoryModel(
        state: 'waitlisted',
        data: {
          'action': 'offer_sent',
          'count': 1,
          'expiresAt': '2026-10-13T12:00:00Z'
        },
        orderModel: OrderModel(state: 'paid'));
    await _environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
            home: Scaffold(
                body: Builder(
                    builder: (context) => Column(children: [
                          history.generateSingleLineSummaryWidget(context),
                          history.generateMultiLineSummaryWidget(context)
                        ])))));
    expect(find.text('Místo nabídnuto · Nabídka platí do: 13. 10. 2026 14:00'),
        findsNWidgets(2));
    for (final action in ['accept', 'decline', 'withdraw', 'cancel']) {
      final entry = OrderHistoryModel(data: {
        'action': 'waitlist_$action',
        'ticketIds': [1, 2]
      });
      expect(entry.waitlistActionSummary, contains('Počet míst: 2'));
      expect(entry.waitlistActionSummary, isNot(contains('waitlist_')));
    }
    expect(OrderHistoryModel(data: {}).waitlistActionSummary, isNull);
  });
  testWidgetsWithEnvironment(
      () => _environment, 'accepted history keeps action and product diff',
      (tester) async {
    final history = OrderHistoryModel(
        data: {'action': 'waitlist_accept'},
        previousHistoryRecord: OrderHistoryModel(dataTickets: []),
        dataTickets: [
          OrderDataTicketModel(
              ticketSymbol: 'T1',
              products: [OrderDataProductModel(id: 1, title: 'Ubytování')])
        ]);
    await _environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
            home: Scaffold(
                body: Builder(
                    builder: (context) => Column(children: [
                          history.generateSingleLineSummaryWidget(context),
                          history.generateMultiLineSummaryWidget(context)
                        ])))));
    expect(
        find.textContaining('Přijato', findRichText: true), findsNWidgets(2));
    expect(find.textContaining('+ Ubytování', findRichText: true),
        findsNWidgets(2));
  });

  testWidgetsWithEnvironment(
    () => _environment,
    'order and form response grids share the detail status and render its color',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await easy.EasyLocalization.ensureInitialized();
      final scenarios = [
        ('waitlisted', {'offered': 1}, 'offered', 'Nabídnuto'),
        ('waitlisted', {'withdrawn': 2}, 'withdrawn', 'Vyřazeno z náhradníků'),
        (
          'waitlisted',
          {'withdrawn': 1, 'waiting': 1},
          'waitlisted',
          'Náhradníci',
        ),
        (
          'waitlisted',
          {'offer_declined': 1},
          'offer_declined',
          'Nabídka odmítnuta',
        ),
        (
          'waitlisted',
          {'offer_cancelled': 1},
          'offer_cancelled',
          'Nabídka zrušena',
        ),
        (
          'waitlisted',
          {'offer_declined': 1, 'waiting': 1},
          'waitlisted',
          'Náhradníci',
        ),
        (
          'waitlisted',
          {'offer_declined': 1, 'withdrawn': 1},
          'withdrawn',
          'Vyřazeno z náhradníků',
        ),
        ('waitlisted', {'offer_expired': 1}, 'waitlisted', 'Náhradníci'),
        ('storno', {'withdrawn': 1}, 'storno', 'Stornováno'),
        ('sent', {'offered': 1}, 'sent', 'Odesláno'),
      ];
      for (final (stored, counts, displayed, label) in scenarios) {
        final orderJson = {'id': 1, 'order_symbol': 'A', 'state': stored};
        final summary = {'counts': counts};
        final order = OrderModel.fromJson({
          ...orderJson,
          'waitlistSummary': summary,
        });
        final detail = OrderAdminDetail({
          'order': orderJson,
          'waitlistSummary': summary,
        }).model;
        expect(detail.stateLabel, label);
        expect(detail.displayState, displayed);
        expect(detail.state, stored);
        expect(order.state, stored);
        if (const {
          'withdrawn',
          'storno',
          'offer_declined',
          'offer_cancelled',
        }.contains(displayed)) {
          expect(
            OrderModel.singleDataGridStateToColor(displayed),
            Colors.grey.shade700.withValues(alpha: 0.6),
          );
        }
        await _environment.pumpWidget(
          tester,
          easy.EasyLocalization(
            supportedLocales: const [Locale('cs')],
            path: 'unused',
            assetLoader: _TestTranslations(),
            child: MaterialApp(
              builder: DependencyMaterialBridge.builder,
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    final column = EshopColumns.generateColumns(context, [
                      EshopColumnIds.ORDER_STATE,
                    ]).single;
                    final row = order.toTrinaRow(context);
                    final cell = row.cells[EshopColumnIds.ORDER_STATE]!;
                    final response = FormResponseModel(
                      order: order,
                      allFields: [],
                    );
                    expect(cell.value, '$displayed;$label');
                    expect(
                      response
                          .toTrinaRow(context)
                          .cells[EshopColumnIds.ORDER_STATE]!
                          .value,
                      cell.value,
                    );
                    return column.renderer!(
                      TrinaColumnRendererContext(
                        column: column,
                        rowIdx: 0,
                        row: row,
                        cell: cell,
                        stateManager: _RendererState(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(label.toUpperCase()), findsOneWidget);
        expect(
          tester.widget<OrderStateCell>(find.byType(OrderStateCell)).background,
          OrderModel.singleDataGridStateToColor(displayed),
        );
      }
    },
  );

  testWidgetsWithEnvironment(() => _environment,
      'history status uses immutable action and affected count, never current order',
      (tester) async {
    final history = OrderHistoryModel(
        state: 'waitlisted',
        orderModel: OrderModel(state: 'paid'),
        data: {
          'action': 'waitlist_withdraw',
          'ticketIds': [1]
        });
    await _environment.pumpWidget(tester,
        MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      final cell = history
          .toTrinaRow(context)
          .cells[EshopColumnIds.HISTORY_STATE]!
          .value;
      expect(cell,
          'waitlisted;Náhradníci → withdrawn;Vyřazeno z náhradníků (1)');
      return const SizedBox();
    })));
    history.data = {'action': 'offer_sent', 'count': 2};
    expect(history.waitlistHistoryState,
        'waitlisted;Náhradníci → offered;Nabídnuto (2)');
    expect(history.state, 'waitlisted');
  });

  testWidgetsWithEnvironment(() => _environment,
      'history arrow renders lifecycle colors and target label without redundant tooltip at 280px',
      (tester) async {
    for (final action in [
      'waitlist_withdraw',
      'waitlist_decline',
      'waitlist_cancel',
      'offer_sent',
      'waitlist_accept'
    ]) {
      final history = OrderHistoryModel(state: 'paid', data: {
        'action': action,
        'ticketIds': [1],
        'count': 1
      });
      final formatted = history.waitlistHistoryState!;
      await _environment.pumpWidget(
          tester,
          MaterialApp(builder: DependencyMaterialBridge.builder,
              home: Scaffold(
                  body: Center(
                      child: SizedBox(
                          width: 280,
                          child: EshopColumns.buildOrderStateRenderer(formatted,
                              OrderModel.singleDataGridStateToColor))))));
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      final tags = tester
          .widgetList<Container>(find.byType(Container))
          .where((w) => w.decoration is BoxDecoration)
          .toList();
      expect((tags.first.decoration as BoxDecoration).color,
          OrderModel.singleDataGridStateToColor('waitlisted'));
      final expectedColor = action == 'offer_sent'
          ? OrderModel.singleDataGridStateToColor('waitlisted')
          : action == 'waitlist_accept'
              ? OrderModel.singleDataGridStateToColor('paid')
              : Colors.grey.shade700.withValues(alpha: 0.6);
      expect((tags.last.decoration as BoxDecoration).color, expectedColor);
      final target =
          formatted.split(';').last.toUpperCase();
      expect(find.text(target), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgetsWithEnvironment(
    () => _environment,
    'narrow order history wraps and displays the full withdrawn label',
    (tester) async {
      final history = OrderHistoryModel(
        state: 'waitlisted',
        data: {
          'action': 'waitlist_withdraw',
          'ticketIds': [1],
        },
      );
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 140,
                child: OrderStateDisplay(
                  formattedState: history.waitlistHistoryState!,
                  getBackground: OrderModel.singleDataGridStateToColor,
                  enableWrapping: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      final label = find.text('VYŘAZENO Z NÁHRADNÍKŮ (1)');
      expect(tester.widget<Text>(label).maxLines, isNull);
      expect(
        tester.getSize(label).height,
        greaterThan(tester.getSize(find.text('NÁHRADNÍCI')).height),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
