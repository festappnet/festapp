import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/models/orders_history_model.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  OrderHistoryModel record(String? seat, {num price = 450}) =>
      OrderHistoryModel.fromJson({
        'id': 1,
        'state': 'ordered',
        'price': price,
        'currency_code': 'CZK',
        'data': {
          'tickets': [
            {
              'id': 10,
              'ticket_symbol': 'TEST',
              'products': [
                {
                  'id': 20,
                  'title': 'Místo',
                  'price': price,
                  'currency_code': 'CZK',
                  if (seat != null) 'spot_title': seat
                }
              ]
            }
          ]
        }
      });
  for (final previous in [null, 'S16A']) {
    testWidgets('missing seat metadata does not invent a move from $previous',
        (tester) async {
      final current = record(previous == null ? 'S16A' : null)
        ..previousHistoryRecord = record(previous);
      final catalog =
          jsonDecode(File('assets/translations/cs.json').readAsStringSync());
      await WidgetEnvironmentFixture(
              locale: const Locale('cs'), translations: catalog)
          .pumpWidget(tester, MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
        final summary = current
            .toTrinaRow(context)
            .cells[EshopColumnIds.HISTORY_CHANGES_SUMMARY]!
            .value as String;
        expect(summary, isNot(contains('→')));
        expect(summary, isNot(contains('null')));
        return const SizedBox();
      })));
    });
  }
  testWidgets('real seat and price changes remain visible', (tester) async {
    final moved = record('S16B')..previousHistoryRecord = record('S16A');
    final repriced = record('S16A', price: 500)
      ..previousHistoryRecord = record(null);
    final catalog =
        jsonDecode(File('assets/translations/cs.json').readAsStringSync());
    await WidgetEnvironmentFixture(
            locale: const Locale('cs'), translations: catalog)
        .pumpWidget(tester, MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      String summary(OrderHistoryModel model) => model
          .toTrinaRow(context)
          .cells[EshopColumnIds.HISTORY_CHANGES_SUMMARY]!
          .value as String;
      expect(summary(moved), contains('S16A → S16B'));
      expect(summary(repriced), contains('450'));
      expect(summary(repriced), contains('500'));
      expect(summary(repriced), isNot(contains('null')));
      return const SizedBox();
    })));
  });
}
