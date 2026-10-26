import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'dart:convert';
import 'dart:io';

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues({}));
  test('cancelled ticket usage cannot be toggled', () {
    expect(canToggleTicketUsage(OrderModel.stornoState), isFalse);
    expect(
      canToggleTicketUsage('${OrderModel.stornoState};STORNO'),
      isFalse,
    );
  });

  test('waiting ticket cannot be used or downloaded as an admission', () {
    for (final state in [
      OrderModel.waitlistedState,
      '${OrderModel.waitlistedState};Waiting'
    ]) {
      expect(canToggleTicketUsage(state), isFalse);
      expect(canDownloadTicket(state), isFalse);
    }
    expect(canDownloadTicket(OrderModel.sentState), isTrue);
  });

  test('active and used ticket usage can be toggled', () {
    expect(canToggleTicketUsage(OrderModel.sentState), isTrue);
    expect(canToggleTicketUsage(OrderModel.usedState), isTrue);
  });

  testWidgets('usage confirmation identifies ticket and its order',
      (tester) async {
    await EasyLocalization.ensureInitialized();
    final order = OrderModel(
      id: 10,
      orderSymbol: 'ORDER10',
      state: OrderModel.sentState,
      data: {'name': 'Jana Nováková', 'email': 'jana@example.org'},
    );
    for (final state in [OrderModel.sentState, OrderModel.usedState]) {
      final ticket = TicketModel(
        id: 20,
        ticketSymbol: 'TICKET20',
        state: state,
        relatedOrder: order,
      );
      await tester.pumpWidget(EasyLocalization(
        key: ValueKey(state),
        supportedLocales: const [Locale('cs')],
        path: 'unused',
        assetLoader: _Translations(),
        child: Builder(
            builder: (localizedContext) => MaterialApp(builder: DependencyMaterialBridge.builder,
                  locale: localizedContext.locale,
                  supportedLocales: localizedContext.supportedLocales,
                  localizationsDelegates: [...localizedContext.localizationDelegates, ...GlobalMaterialLocalizations.delegates],
                  home: Scaffold(body: Builder(builder: (context) {
                    final columns = EshopColumns.generateColumns(
                        context, [EshopColumnIds.TICKET_CONFIRM]);
                    columns.single.width = 600;
                    return TrinaGrid(
                      columns: columns,
                      rows: [ticket.toTrinaRow(context)],
                    );
                  })),
                )),
      ));
      await tester.pumpAndSettle();
      final label = state == OrderModel.usedState
          ? OrdersStrings.restoreTicket
          : OrdersStrings.confirmTicket;
      await tester.tap(find.widgetWithText(ElevatedButton, label));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(find.descendant(of: dialog, matching: find.text('TICKET20')),
          findsOneWidget);
      expect(
          find.descendant(
              of: dialog, matching: find.text(order.toBasicString())),
          findsOneWidget);
      expect(
          find.descendant(
              of: dialog, matching: find.widgetWithText(ElevatedButton, label)),
          findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, CommonStrings.storno));
      await tester.pumpAndSettle();
      expect(ticket.state, state);
      expect(find.byType(AlertDialog), findsNothing);
    }
  });
}
