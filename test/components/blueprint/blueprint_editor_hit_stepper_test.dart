import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets('imported decoration table receives canvas clicks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final table = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      x: 100,
      y: 336,
      width: 192,
      height: 88,
      surface: const {'type': 'rect'},
      properties: const {'role': 'decoration'},
    );
    final c = VenueLayoutController(
      VenueLayoutDocument(
        nodes: [table],
        canvas: const {
          'x': 0,
          'y': 0,
          'width': 800,
          'height': 600,
          'fill': '#FFFFFFFF',
        },
      ),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byType(LayoutSceneSurface);
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(of: surface, matching: find.byType(CustomPaint)),
        )
        .map((w) => w.painter)
        .whereType<LayoutScenePainter>()
        .single;
    final point =
        tester.getTopLeft(surface) +
        MatrixUtils.transformPoint(
          painter.camera!.value,
          painter.offset + Offset(table.x, table.y) * painter.scale,
        );
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(c.selection, {table.id});
    expect(tester.widget<LayoutSceneSurface>(surface).canvasSelected, isFalse);
    expect(c.canUndo, isFalse);
  });

  testWidgets('Czech side counts keep digits visible beside compact steppers', (
    tester,
  ) async {
    final document = tableLayout(
      shape: 'rectangle',
      count: 24,
      width: 800,
      height: 120,
    );
    final c = VenueLayoutController(document)
      ..select({document.nodes.firstWhere((n) => n.kind == 'table').id});
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('cs'),
        supportedLocales: VenueLayoutLocalizations.supportedLocales,
        localizationsDelegates: VenueLayoutLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
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
      ),
    );
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Nahoře');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    final render = tester.state<EditableTextState>(editable).renderEditable;
    final text = TextPainter(
      text: render.text,
      textDirection: TextDirection.ltr,
      textScaler: render.textScaler,
    )..layout();
    expect(render.size.width, greaterThanOrEqualTo(text.width + 2));
    text.dispose();
    final buttons = find.descendant(
      of: field,
      matching: find.byType(IconButton),
    );
    expect(buttons, findsNWidgets(2));
    for (final button in buttons.evaluate()) {
      expect(
        tester.getSize(find.byWidget(button.widget)).width,
        lessThanOrEqualTo(32),
      );
    }
    expect(tester.takeException(), isNull);
  });
}
