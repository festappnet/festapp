import 'package:fstapp/components/forms/views/order_finish_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/forms/widgets_view/form_total_price.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/discount_codes/discount_code_entry.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/eshop/models/order_data_product_model.dart';

void main() {
  test('discount feature defaults off and explicit off/on parsing survives round trips', () {
    final feature = FeatureService.getDefaultFeatures().singleWhere(
      (f) => f.code == FeatureConstants.discountCodes,
    );
    expect(feature.isEnabled, false);
    for (final enabled in [true, false, true]) {
      final parsed = Feature.fromJson({
        'code': FeatureConstants.discountCodes,
        'is_enabled': enabled,
      });
      expect(parsed.isEnabled, enabled);
      expect(Feature.fromJson(parsed.toJson()).isEnabled, enabled);
    }
  });
  test('sold product adapter retains SQL base discount and net without recalculation', () {
    final product = OrderDataProductModel.fromJson({
      'id': 1,
      'price': 80.25,
      'base_price': 100,
      'discount_amount': 19.75,
    });
    expect(product.price, 80.25);
    expect(product.basePrice, 100);
    expect(product.discountAmount, 19.75);
    expect(OrderDataProductModel.fromJson({'price': 100}).discountAmount, 0);
  });
  testWidgets(
    'discount entry is collapsed and busy prevents duplicate application',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var applied = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscountCodeEntry(
              controller: controller,
              busy: true,
              onApply: () => applied++,
              onRemove: () => applied++,
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        expect(button.onPressed, isNull);
      }
      expect(applied, 0);
    },
  );
  testWidgets('discounted bank total retains the charged cents', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: const Scaffold(
          body: FormTotalPrice(
            amount: 80.25,
            currencyCode: 'CZK',
            discounted: true,
          ),
        ),
      ),
    );
    final text = tester
        .widget<Text>(
          find.descendant(
            of: find.byType(FormTotalPrice),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(text, matches(RegExp(r'80[,.]25')));
  });
  testWidgets(
    'unknown discounted order retries its existing submission without reopening a quote',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: FinishOrderScreen(
              retryUnknownOutcome: true,
              orderFutureFunction: () async {
                attempts++;
                return FunctionResponse(
                  status: 200,
                  data: attempts == 1
                      ? {'code': 503, 'errorCode': 'ORDER_OUTCOME_UNKNOWN'}
                      : {'code': 200},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(FilledButton), findsNothing);
    },
  );
}
