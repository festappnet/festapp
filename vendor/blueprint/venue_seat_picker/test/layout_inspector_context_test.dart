import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

void main() {
  testWidgets(
    'inspector follows selection with fresh fields and scroll position',
    (tester) async {
      final a = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        label: 'First rectangle',
        properties: {'shape': 'rectangle'},
      );
      final b = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'Second table',
        x: 300,
        y: 200,
        surface: const {'type': 'rect'},
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [a, b]),
      );
      addTearDown(c.dispose);
      c.select({a.id});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              height: 500,
              child: ListenableBuilder(
                listenable: c,
                builder: (_, _) => LayoutInspector(
                  controller: c,
                  cornerPivot: false,
                  onPivotChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      ScrollPosition position() =>
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(find.text('Save as object'), findsNothing);
      expect(find.byTooltip('Copy style'), findsNothing);
      expect(find.text('Canvas'), findsNothing);
      expect(find.text('Background image'), findsNothing);
      position().jumpTo(position().maxScrollExtent);
      await tester.pump();
      expect(position().pixels, greaterThan(0));
      c.select({b.id});
      await tester.pump();
      expect(position().pixels, 0);
      final heading = find.byKey(const ValueKey('inspector-heading'));
      expect(
        find.descendant(of: heading, matching: find.text('Second table')),
        findsOneWidget,
      );
      final name = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((field) => field.decoration?.labelText == 'Name');
      expect(name.controller!.text, 'Second table');
      expect(find.text('Canvas'), findsNothing);
      expect(find.text('Background image'), findsNothing);
      position().jumpTo(100);
      await tester.pump();
      c.updateNode(b.copyWith(x: 320));
      await tester.pump();
      expect(
        position().pixels,
        100,
      ); // Same object movement never jumps the panel.
      c.select({a.id, b.id});
      await tester.pump();
      expect(position().pixels, 0);
      expect(
        find.text('2 objects selected. Individual values vary.'),
        findsOneWidget,
      );
      expect(find.text('Align and distribute'), findsOneWidget);
      expect(find.text('Canvas'), findsNothing);
      expect(find.text('Background image'), findsNothing);
      c.select({});
      await tester.pump();
      expect(position().pixels, 0);
      expect(find.text('Canvas'), findsOneWidget);
      expect(find.text('Background image'), findsNothing);
      expect(find.text('Reusable objects'), findsNothing);
    },
  );
}
