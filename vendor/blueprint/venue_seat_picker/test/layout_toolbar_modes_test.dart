import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  for (final width in [600.0, 1280.0]) {
    testWidgets('pointer tools keep their place across modes at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(c.dispose);
      Future<void> mount(bool edit) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueLayoutEditor(
                controller: c,
                showGallery: false,
                interactionEnabled: edit,
                toolbarPrefix: const SizedBox(width: 100),
                toolbarLeading: SizedBox(width: edit ? 200 : 80),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Finder tool(String name) => find.byKey(ValueKey('layout-tool-$name'));
      await mount(true);
      if (width < 700) {
        final compact = find.byKey(
          const ValueKey('layout-mobile-pointer-tool'),
        );
        final before = tester.getRect(compact);
        await tester.tap(compact);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(PopupMenuItem<String>, 'Select'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Pan'));
        await tester.pumpAndSettle();
        expect(tester.getRect(compact), before);
        expect(find.byTooltip('Pan'), findsOneWidget);
        await mount(false);
        expect(compact, findsNothing);
        return;
      }
      final select = tester.getRect(tool('Select'));
      final pan = tester.getRect(tool('Pan'));
      final toolbar = find.byKey(const ValueKey('layout-editor-toolbar'));
      expect(
        find.descendant(of: toolbar, matching: tool('Select')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: toolbar, matching: tool('Pan')),
        findsOneWidget,
      );
      expect(select.center.dy, pan.center.dy);
      expect(
        find.descendant(of: toolbar, matching: find.text('Plan style')),
        findsNothing,
      );
      expect(
        find.descendant(of: toolbar, matching: find.text('Choose template')),
        findsNothing,
      );

      expect(
        find.descendant(of: tool('Select'), matching: find.text('Select')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tool('Pan'), matching: find.text('Pan')),
        findsOneWidget,
      );
      expect(tool('Resize'), findsNothing);
      expect(tool('Rotate'), findsNothing);
      await mount(false);
      expect(tool('Select'), findsNothing);
      expect(tool('Pan'), findsNothing);
      expect(tool('Resize'), findsNothing);
      expect(tool('Rotate'), findsNothing);
    });
  }
}
