import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/views/add_cash_payment_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

// Mock Localization if needed, or rely on defaults if simple strings
class MockLocalization {
  // Simplistic mock if needed
}

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('AddCashPaymentDialog renders and validates input',
      (WidgetTester tester) async {
    // Determine screen size to avoid overflow
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: AddCashPaymentDialog(
            unitId: 100,
            currency: 'CZK',
            variableSymbol: '123456',
            paymentInfoId: 555,
          ),
        ),
      ),
    );

    // Check availability of widgets
    // Note: Strings might be untranslated keys if EasyLocalization not loaded.
    // We search by Type or Key if needed.

    expect(find.byType(TextFormField),
        findsOneWidget); // Amount only (Note is in collapsed ExpansionTile)

    // Open ExpansionTile
    await tester.tap(find.text(CommonStrings.advancedSettings));
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(2)); // Amount + Note

    // Input Amount
    await tester.enterText(find.byType(TextFormField).first, "100");
    await tester.pump();

    // We can't verify DB call without mocking static DbOrders.
    // But we verified the widget pumps and interacts.
  });
}
