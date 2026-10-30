import 'dart:ui' as ui;

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

  Future<int> paintedAlpha(WidgetTester tester) async {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(BrandLoadingIndicator),
        matching: find.byType(CustomPaint),
      ),
    );
    final recorder = ui.PictureRecorder();
    paint.painter!.paint(ui.Canvas(recorder), const ui.Size(160, 130));
    final picture = recorder.endRecording();
    final image = await picture.toImage(160, 130);
    final bytes = (await image.toByteData())!;
    var alpha = 0;
    for (var i = 3; i < bytes.lengthInBytes; i += 4) {
      alpha += bytes.getUint8(i);
    }
    image.dispose();
    picture.dispose();
    return alpha;
  }

  testWidgets('brand loading reveals once then pulses the complete logo', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 4401));
    await tester.pump();
    final complete = await tester.runAsync(() => paintedAlpha(tester));
    expect(complete, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 1100));
    final dimmed = await tester.runAsync(() => paintedAlpha(tester));
    expect(dimmed, closeTo(complete! * 0.76, complete * 0.02));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(await tester.runAsync(() => paintedAlpha(tester)), complete);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(await tester.runAsync(() => paintedAlpha(tester)), dimmed);
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
