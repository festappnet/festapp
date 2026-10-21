import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_style.dart';

void main() {
  testWidgets(
    'style presets remain square and scroll horizontally in a narrow panel',
    (tester) async {
      final controller = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(controller.dispose);
      LayoutAppearance? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 210,
              child: LayoutStylePresets(
                controller: controller,
                onApply: (value) => applied = value,
              ),
            ),
          ),
        ),
      );
      final scroll = find.byKey(const ValueKey('layout-style-presets-scroll'));
      expect(
        tester.widget<SingleChildScrollView>(scroll).scrollDirection,
        Axis.horizontal,
      );
      for (final name in layoutAppearancePresets.keys) {
        final finder = find.byKey(ValueKey('layout-style-$name'));
        expect(tester.getSize(finder), const Size(88, 88));
        final button = tester.widget<OutlinedButton>(finder);
        final shape =
            button.style!.shape!.resolve({})! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(8));
      }
      await tester.drag(scroll, const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('layout-style-Slate')));
      expect(applied, same(layoutAppearancePresets['Slate']));
      expect(tester.takeException(), isNull);
    },
  );
}
