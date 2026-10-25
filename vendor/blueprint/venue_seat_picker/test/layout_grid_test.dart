import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'grid toggles independently from snapping and never changes document/history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = VenueLayoutDocument.empty();
      final c = VenueLayoutController(original);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onSelectDown != null,
        ),
      );
      expect(surface().showGrid, isFalse);
      await tester.tap(find.widgetWithText(FilterChip, 'Grid'));
      await tester.pump();
      expect(surface().showGrid, isTrue);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Snap'))
            .selected,
        isTrue,
      );
      final painter =
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: find.byWidgetPredicate(
                            (w) =>
                                w is LayoutSceneSurface &&
                                w.onSelectDown != null,
                          ),
                          matching: find.byWidgetPredicate(
                            (w) =>
                                w is CustomPaint &&
                                w.painter is LayoutScenePainter,
                          ),
                        )
                        .first,
                  )
                  .painter
              as LayoutScenePainter;
      expect(painter.showGrid, isTrue);
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, isFalse);
      surface().onSelectDown!(const Offset(100, 100));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pump();
      expect(surface().showGrid, isFalse);
      expect(c.canUndo, isFalse);
    },
  );
}
