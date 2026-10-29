import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/widgets/brand_loading_indicator.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

void main() {
  const branded = AppConfig.loadingStyle == 'vstupenky-outline';

  Widget host({bool reduced = false, bool ticking = true}) => MaterialApp(
    builder: DependencyMaterialBridge.builder,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: ticking,
          child: const Center(
            child: SizedBox(
              width: 160,
              height: 130,
              child: BrandLoadingIndicator(),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('brand loading fits a compact panel and repeats until disposal', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 13));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BrandLoadingIndicator)).width, 160);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  }, skip: !branded);

  testWidgets(
    'reduced motion keeps the complete logo without a repeating ticker',
    (tester) async {
      await tester.pumpWidget(host(reduced: true));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        find.descendant(
          of: find.byType(BrandLoadingIndicator),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    skip: !branded,
  );

  testWidgets('inactive routes stop the loading animation', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(host(ticking: false));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  }, skip: !branded);
}
