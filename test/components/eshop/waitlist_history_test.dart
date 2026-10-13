import 'dart:convert';
import 'dart:io';
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

}
