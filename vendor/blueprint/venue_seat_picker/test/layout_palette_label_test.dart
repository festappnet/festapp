import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  for (final scale in [1.0, 1.25]) {
    testWidgets('two-line Czech palette labels fit at text scale $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('cs'),
          supportedLocales: VenueLayoutLocalizations.supportedLocales,
          localizationsDelegates:
              VenueLayoutLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: VenueLayoutEditor(controller: controller, showGallery: false),
          ),
        ),
      );
      final label = find.text('Oblouková řada');
      await tester.ensureVisible(label);
      await tester.pump();
      final paragraph = tester.renderObject<RenderParagraph>(label);
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 14),
      );
      // Fallback glyph runs can split one visual line into multiple boxes.
      expect(boxes.map((box) => box.top).toSet(), hasLength(2));
      for (final box in boxes) {
        expect(
          box.bottom,
          lessThanOrEqualTo(paragraph.size.height + .1),
          reason: 'The second line must fit inside the label box',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
}
