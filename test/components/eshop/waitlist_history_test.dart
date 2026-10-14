import 'dart:convert';
import 'dart:io';
import 'package:fstapp/components/eshop/views/order_state_display.dart';
import 'package:easy_localization/easy_localization.dart' as easy;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/order_data_ticket_model.dart';
import 'package:fstapp/components/eshop/models/order_data_product_model.dart';
import 'package:fstapp/components/eshop/models/orders_history_model.dart';
import 'package:fstapp/components/eshop/models/waitlist_summary_model.dart';
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;

class _TestTranslations extends easy.AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync());
}

class _RendererState extends Fake implements TrinaGridStateManager {}

void main() {
  setUp(() {
    Localization.load(const Locale('cs'), translations: Translations(jsonDecode(File('assets/translations/cs.json').readAsStringSync())));
    zones.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Prague'));
  });
  test('single offered projection preserves canonical state and multi order label', () {
    final order = OrderModel(state: 'waitlisted');
    order.waitlistSummary = WaitlistSummaryModel.fromJson({'counts': {'offered': 1}});
    expect(order.stateLabel, 'Nabídnuto');
    expect(order.state, 'waitlisted');
    order.waitlistSummary = WaitlistSummaryModel.fromJson({'counts': {'offered': 1, 'waiting': 1}});
    expect(order.stateLabel, OrderModel.stateToLocale('waitlisted'));
    order.state = 'paid';
    expect(order.stateLabel, OrderModel.stateToLocale('paid'));
  });
  testWidgets('immutable offer history renders action and expiry in both views', (tester) async {
    final history = OrderHistoryModel(state: 'waitlisted', data: {'action':'offer_sent','count':1,'expiresAt':'2026-10-13T12:00:00Z'}, orderModel: OrderModel(state:'paid'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => Column(children:[history.generateSingleLineSummaryWidget(context),history.generateMultiLineSummaryWidget(context)])))));
    expect(find.text('Místo nabídnuto · Nabídka platí do: 13. 10. 2026 14:00'), findsNWidgets(2));
    for (final action in ['accept','decline','withdraw','cancel']) {
      final entry=OrderHistoryModel(data:{'action':'waitlist_$action','ticketIds':[1,2]});
      expect(entry.waitlistActionSummary, contains('Počet míst: 2'));
      expect(entry.waitlistActionSummary, isNot(contains('waitlist_')));
    }
    expect(OrderHistoryModel(data:{}).waitlistActionSummary,isNull);
  });
  testWidgets('accepted history keeps action and product diff', (tester) async {
    final history = OrderHistoryModel(data: {'action': 'waitlist_accept'},
      previousHistoryRecord: OrderHistoryModel(dataTickets: []),
      dataTickets: [OrderDataTicketModel(ticketSymbol: 'T1', products: [OrderDataProductModel(id: 1, title: 'Ubytování')])]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => Column(children: [history.generateSingleLineSummaryWidget(context), history.generateMultiLineSummaryWidget(context)])))));
    expect(find.textContaining('Přijato', findRichText: true), findsNWidgets(2));
    expect(find.textContaining('+ Ubytování', findRichText: true), findsNWidgets(2));
  });

  testWidgets('actual state renderer preserves draft state and projects offered only for waitlisted cell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await easy.EasyLocalization.ensureInitialized();
    final order = OrderModel(state: 'ordered');
    for (final scenario in ['sent', 'offered', 'offeredDraft']) {
      order.state = scenario == 'sent' ? 'ordered' : 'waitlisted';
      order.waitlistSummary = WaitlistSummaryModel.fromJson({'counts': {'offered': 1}});
      final cell = TrinaCell(value: scenario == 'offered' ? 'waitlisted;Náhradníci' : 'sent;Odesláno');
      final row = TrinaRow(cells: {EshopColumns.ORDER_STATE: cell, EshopColumns.ORDER_MODEL_REFERENCE: TrinaCell(value: order)});
      await tester.pumpWidget(easy.EasyLocalization(supportedLocales: const [Locale('cs')], path: 'unused', assetLoader: _TestTranslations(), child: MaterialApp(home: Scaffold(body: Builder(builder: (context) {
        final column = EshopColumns.generateColumns(context, [EshopColumns.ORDER_STATE]).single;
        return column.renderer!(TrinaColumnRendererContext(column: column, rowIdx: 0, row: row, cell: cell, stateManager: _RendererState()));
      })))));
      await tester.pumpAndSettle();
      expect(find.text(scenario == 'offered' ? 'NABÍDNUTO' : 'ODESLÁNO'), findsOneWidget);
    }
  });

  testWidgets('history status uses immutable action and affected count, never current order', (tester) async {
    final history = OrderHistoryModel(state:'waitlisted', orderModel:OrderModel(state:'paid'), data:{'action':'waitlist_withdraw','ticketIds':[1]});
    await tester.pumpWidget(MaterialApp(home: Builder(builder:(context) {
      final cell=history.toTrinaRow(context).cells[EshopColumns.HISTORY_STATE]!.value;
      expect(cell,'waitlisted;Náhradníci → history:withdrawn;Vyřazeno z náhradníků (1)');
      return const SizedBox();
    })));
    history.data={'action':'offer_sent','count':2};
    expect(history.waitlistHistoryState,'waitlisted;Náhradníci → waitlisted;Nabídnuto (2)');
    expect(history.state,'waitlisted');
  });

  testWidgets('history arrow renders lifecycle colors and full target tooltip at 280px', (tester) async {
    for (final action in ['waitlist_withdraw', 'offer_sent', 'waitlist_accept']) {
      final history = OrderHistoryModel(state: 'paid', data: {'action': action, 'ticketIds': [1], 'count': 1});
      final formatted = history.waitlistHistoryState!;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width:280,
        child:EshopColumns.buildOrderStateRenderer(formatted, OrderStateDisplay.historyBackground))))));
      expect(find.byIcon(Icons.arrow_forward),findsOneWidget);
      final tags = tester.widgetList<Container>(find.byType(Container)).where((w) => w.decoration is BoxDecoration).toList();
      expect((tags.first.decoration as BoxDecoration).color,OrderModel.singleDataGridStateToColor('waitlisted'));
      final expectedColor = action == 'offer_sent' ? OrderModel.singleDataGridStateToColor('waitlisted') : action == 'waitlist_accept' ? OrderModel.singleDataGridStateToColor('paid') : Colors.grey.shade500.withValues(alpha:0.6);
      expect((tags.last.decoration as BoxDecoration).color,expectedColor);
      final target = OrderModel.statesDataGridToUpper(formatted.split(';').last);
      expect(find.byTooltip(target), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

}
