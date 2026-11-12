import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/models/payment_operation_context.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  final environment = WidgetEnvironmentFixture(
    locale: const Locale('cs'),
    translations: jsonDecode(
      File('assets/translations/cs.json').readAsStringSync(),
    ) as Map<String, dynamic>,
  );
  testWidgetsWithEnvironment(
    () => environment,
    'payment grid actions inherit the cell foreground and authorized cash capability',
    (tester) async {
      for (final allowed in [true, false]) {
        const foreground = Color(0xffa5a9b1);
        final order = OrderModel(id: 9, paymentInfo: 12);
        order.paymentInfoModel = PaymentInfoModel(
          paymentOperations: PaymentOperationContext(
            gross: '1000',
            net: '1000',
            available: '1000',
            currency: 'CZK',
            methods: [
              PaymentOperationMethod(
                id: 'cash',
                displayName: 'Cash',
                record: allowed,
                refund: allowed,
              ),
            ],
          ),
        );
        final row = TrinaRow(
          cells: {
            EshopColumnIds.ORDER_ID: TrinaCell(value: 9),
            EshopColumnIds.ORDER_MODEL_REFERENCE: TrinaCell(value: order),
            EshopColumnIds.PAYMENT_INFO_PAID: TrinaCell(value: '1000 Kč'),
            EshopColumnIds.PAYMENT_INFO_RETURNED: TrinaCell(value: '0 Kč'),
          },
        );
        await environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Builder(
              builder: (context) {
                final builders = EshopColumns.columnBuilders(context);
                return Scaffold(
                  body: TrinaGrid(
                    key: ValueKey(allowed),
                    columns: [
                      TrinaColumn(
                        title: 'Order',
                        field: EshopColumnIds.ORDER_ID,
                        hide: true,
                        type: TrinaColumnType.number(),
                      ),
                      TrinaColumn(
                        title: 'Model',
                        field: EshopColumnIds.ORDER_MODEL_REFERENCE,
                        hide: true,
                        type: TrinaColumnType.text(),
                      ),
                      ...(builders[EshopColumnIds.PAYMENT_INFO_PAID]
                              as Function)({'unitId': 3})
                          as List<TrinaColumn>,
                      ...(builders[EshopColumnIds.PAYMENT_INFO_RETURNED]
                              as Function)({'unitId': 3})
                          as List<TrinaColumn>,
                    ],
                    rows: [row],
                    configuration: const TrinaGridConfiguration(
                      style: TrinaGridStyleConfig(
                        cellTextStyle: TextStyle(color: foreground),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final icon in [
          Icons.add_circle_outline,
          Icons.remove_circle_outline,
        ]) {
          final button = tester.widget<IconButton>(
            find.widgetWithIcon(IconButton, icon),
          );
          expect(button.color, foreground);
          expect(button.disabledColor, foreground.withValues(alpha: .38));
          expect(button.onPressed != null, allowed);
        }
      }
    },
  );
}
