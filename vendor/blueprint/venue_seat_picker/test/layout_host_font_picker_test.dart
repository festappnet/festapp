import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_font_size_control.dart';

void main() {
  testWidgets(
    'host font catalog replaces only selector and is never built in view mode',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'Table',
        x: 400,
        y: 300,
        properties: {},
        surface: const {'type': 'rect'},
        style: {
          'label': {'size': 40.64},
        },
      );
      final controller = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [node]),
      )..select({node.id});
      addTearDown(controller.dispose);
      var calls = 0;
      Widget editor(bool editing) => MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(
            controller: controller,
            showGallery: false,
            interactionEnabled: editing,
            fontPickerBuilder: (context, selected) {
              calls++;
              expect(selected.id, node.id);
              return const Text('Host full font catalog');
            },
          ),
        ),
      );
      await tester.pumpWidget(editor(true));
      await tester.pumpAndSettle();
      expect(calls, greaterThan(0));
      expect(find.text('Host full font catalog'), findsOneWidget);
      expect(find.byType(EditorFontPicker), findsNothing);
      expect(find.text('Font size'), findsOneWidget);
      expect(find.byTooltip('Bold'), findsOneWidget);
      expect(find.byTooltip('Italic'), findsOneWidget);
      final beforeView = calls;
      await tester.pumpWidget(editor(false));
      await tester.pumpAndSettle();
      expect(calls, beforeView);
      expect(find.text('Host full font catalog'), findsNothing);
      expect(find.byType(LayoutFontSizeControl), findsNothing);
      expect(controller.dirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
