import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets('graphic resize keeps aspect ratio unless Shift is held', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = VenueLayoutController(VenueLayoutDocument.empty());
    addTearDown(c.dispose);
    c.insertVectorGraphic(
      LayoutVectorGraphic.fromJson({
        'version': 1,
        'width': 200,
        'height': 100,
        'commands': <Object>[],
      }),
      x: 500,
      y: 500,
      width: 200,
      height: 100,
    );
    final original = c.document;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    LayoutSceneSurface surface() =>
        tester.widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface));
    surface().onHandleStart!('Resize se', const Offset(600, 550));
    surface().onDragUpdate!(const Offset(700, 550));
    surface().onDragEnd!();
    await tester.pumpAndSettle();
    expect(
      c.document.nodes.single.width / c.document.nodes.single.height,
      closeTo(2, .001),
    );
    c.undo();
    expect(c.document.toJson(), original.toJson());
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    surface().onHandleStart!('Resize se', const Offset(600, 550));
    surface().onDragUpdate!(const Offset(700, 550));
    surface().onDragEnd!();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(
      c.document.nodes.single.width / c.document.nodes.single.height,
      closeTo(3, .001),
    );
  });

  testWidgets('focused committed property field uses plan undo and redo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'shape',
      x: 500,
      y: 500,
      width: 200,
      height: 100,
      properties: const {'shape': 'rect'},
    );
    final c = VenueLayoutController(VenueLayoutDocument(nodes: [node]))
      ..select({node.id});
    addTearDown(c.dispose);
    c.updateNode(node.copyWith(x: 600));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Position and size'));
    await tester.tap(find.text('Position and size'));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'X',
    );
    await tester.ensureVisible(field);
    await tester.tap(field);
    Future<void> undo({bool redo = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (redo) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      if (redo) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await undo();
    expect(c.document.nodes.single.x, 500);
    await undo(redo: true);
    expect(c.document.nodes.single.x, 600);
    await tester.enterText(field, '650');
    await undo();
    expect(
      c.document.nodes.single.x,
      600,
      reason: 'Uncommitted text stays in native undo',
    );
    await tester.enterText(field, '650');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.document.nodes.single.x, 650);
    await undo();
    expect(c.document.nodes.single.x, 600);
  });
}
