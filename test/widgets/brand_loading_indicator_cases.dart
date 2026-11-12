import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/widgets/brand_loading_indicator.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

void main() {
  const branded = AppConfig.loadingStyle == 'brand-outline';

  const origins = ['https://vstupenky.online', 'https://tickets.festapp.net'];

  Widget host({
    required String origin,
    bool reduced = false,
    bool ticking = true,
  }) => MaterialApp(
    builder: DependencyMaterialBridge.builder,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: TickerMode(
          enabled: ticking,
          child: Center(
            child: SizedBox(
              width: 160,
              height: 130,
              child: BrandLoadingIndicator(
                key: ValueKey(origin),
                webLink: origin,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<({int alpha, int height})> paintedMeasure(WidgetTester tester) async {
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
    var firstRow = 130;
    var lastRow = -1;
    for (var i = 3; i < bytes.lengthInBytes; i += 4) {
      final value = bytes.getUint8(i);
      alpha += value;
      if (value > 0) {
        final row = (i ~/ 4) ~/ 160;
        if (row < firstRow) firstRow = row;
        if (row > lastRow) lastRow = row;
      }
    }
    image.dispose();
    picture.dispose();
    return (
      alpha: alpha,
      height: lastRow < firstRow ? 0 : lastRow - firstRow + 1,
    );
  }

  testWidgets('brand loading reveals once then pulses the complete logo', (
    tester,
  ) async {
    for (final origin in origins) {
      await tester.pumpWidget(host(origin: origin));
      await tester.pump(const Duration(milliseconds: 300));
      final outlined = await tester.runAsync(() => paintedMeasure(tester));
      expect(outlined!.alpha, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 4101));
      await tester.pump();
      final completed = await tester.runAsync(() => paintedMeasure(tester));
      final complete = completed!.alpha;
      expect(complete, greaterThan(outlined.alpha));
      expect(
        completed.height,
        origin.contains('tickets.festapp.net')
            ? lessThan(90)
            : greaterThan(100),
      );
      expect(complete, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 1100));
      final dimmed = (await tester.runAsync(() => paintedMeasure(tester)))!
          .alpha;
      expect(dimmed, closeTo(complete * 0.76, complete * 0.02));
      await tester.pump(const Duration(milliseconds: 1100));
      expect(
        (await tester.runAsync(() => paintedMeasure(tester)))!.alpha,
        complete,
      );
      await tester.pump(const Duration(milliseconds: 1100));
      expect(
        (await tester.runAsync(() => paintedMeasure(tester)))!.alpha,
        dimmed,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(BrandLoadingIndicator)).width, 160);
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    }
  }, skip: !branded);

  testWidgets(
    'reduced motion keeps the complete logo without a repeating ticker',
    (tester) async {
      for (final origin in origins) {
        await tester.pumpWidget(host(origin: origin, reduced: true));
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
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip: !branded,
  );

  testWidgets('inactive routes stop the loading animation', (tester) async {
    for (final origin in origins) {
      await tester.pumpWidget(host(origin: origin));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(host(origin: origin, ticking: false));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  }, skip: !branded);
}
