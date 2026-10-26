import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_global_style.dart';

void main() {
  testWidgets(
    'global style hover previews without choosing; click commits and Escape restores',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = tableLayout(shape: 'rect', count: 4);
      final c = VenueLayoutController(original);
      addTearDown(c.dispose);
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 280,
                child: LayoutGlobalStylePanel(
                  controller: c,
                  onClose: () => closed = true,
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      final wood = find.byKey(const ValueKey('appearance-family-wood'));
      await mouse.moveTo(tester.getCenter(wood));
      await tester.pump();
      expect(c.gestureActive, isTrue);
      expect(c.document.styles['kinds']['seat']['seatStyle'], 'wood');
      expect(c.canUndo, isFalse);
      await mouse.moveTo(const Offset(10, 10));
      await tester.pump();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, isFalse);
      await tester.tap(wood);
      await tester.pump();
      expect(c.gestureActive, isFalse);
      expect(c.canUndo, isTrue);
      c.undo();
      await tester.pump();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, isFalse);
      final palette = find.byKey(const ValueKey('layout-style-Warm'));
      await mouse.moveTo(tester.getCenter(palette));
      await tester.pump();
      expect(c.gestureActive, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closed, isTrue);
      expect(c.document.toJson(), original.toJson());
      expect(c.gestureActive, isFalse);
      expect(c.canUndo, isFalse);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    },
  );
}
