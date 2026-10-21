import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  testWidgets(
    'active editor handles undo and redo with focus in surrounding chrome',
    (tester) async {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 300,
        width: 190,
        height: 110,
        surface: const {'type': 'rect'},
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [table]),
      );
      final chromeFocus = FocusNode();
      addTearDown(c.dispose);
      addTearDown(chromeFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextButton(
                  focusNode: chromeFocus,
                  onPressed: () {},
                  child: const Text('App chrome'),
                ),
                Expanded(
                  child: VenueLayoutEditor(controller: c, showGallery: false),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.select({table.id});
      c.moveSelection(10, 0);
      chromeFocus.requestFocus();
      await tester.pump();
      expect(chromeFocus.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.document.nodes.single.x, 400);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.document.nodes.single.x, 410);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(c.document.nodes.single.x, 410);
    },
  );

  testWidgets(
    'undo works after leaving an inspector field by clicking panel heading',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 300,
        width: 190,
        height: 110,
        surface: const {'type': 'rect'},
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [table]),
      );
      addTearDown(c.dispose);
      const fieldKey = ValueKey('inspector-test-field');
      const headingKey = ValueKey('inspector-test-heading');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(
              controller: c,
              showGallery: false,
              inspectorBuilder: (_, __) => Column(
                children: [
                  const SizedBox(
                    height: 40,
                    child: Center(
                      child: Text('Selected table', key: headingKey),
                    ),
                  ),
                  TextField(
                    key: fieldKey,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.select({table.id});
      c.moveSelection(10, 0);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(fieldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(fieldKey).hitTestable());
      await tester.pump();
      await tester.ensureVisible(find.byKey(headingKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(headingKey).hitTestable());
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(c.document.nodes.single.x, 400);
    },
  );

  testWidgets(
    'history shortcuts survive control focus and modal close but preserve text editing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 300,
        width: 190,
        height: 110,
        surface: const {'type': 'rect'},
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [node]),
      );
      final controlFocus = FocusNode();
      final textFocus = FocusNode();
      addTearDown(c.dispose);
      addTearDown(controlFocus.dispose);
      addTearDown(textFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(
              controller: c,
              showGallery: false,
              toolbarTrailing: Builder(
                builder: (context) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextField(focusNode: textFocus),
                    ),
                    TextButton(
                      focusNode: controlFocus,
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close test dialog'),
                            ),
                          ],
                        ),
                      ),
                      child: const Text('Open test dialog'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.select({node.id});
      c.moveSelection(10, 0);
      await tester.pump();
      expect(c.document.nodes.single.x, 410);
      Future<void> shortcut(
        LogicalKeyboardKey key, {
        bool meta = false,
        bool shift = false,
      }) async {
        final modifier = meta
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        await tester.sendKeyDownEvent(modifier);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(modifier);
        await tester.pump();
      }

      controlFocus.requestFocus();
      await tester.pump();
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(c.document.nodes.single.x, 400);
      await shortcut(LogicalKeyboardKey.keyZ, meta: true, shift: true);
      expect(c.document.nodes.single.x, 410);
      await shortcut(LogicalKeyboardKey.keyZ, meta: true);
      expect(c.document.nodes.single.x, 400);
      await shortcut(LogicalKeyboardKey.keyY);
      expect(c.document.nodes.single.x, 410);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(c.document.nodes.single.x, 410);
      await tester.tap(find.text('Close test dialog'));
      await tester.pumpAndSettle();
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(c.document.nodes.single.x, 400);
      await shortcut(LogicalKeyboardKey.keyY);

      textFocus.requestFocus();
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Editing text');
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(c.document.nodes.single.x, 410);
      controlFocus.requestFocus();
      await tester.pump();
      await shortcut(LogicalKeyboardKey.keyZ);
      expect(c.document.nodes.single.x, 400);
    },
  );
}
