import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/views/blueprint_editor_feedback.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  testWidgets(
      'save progress and success share a centered notice above the canvas',
      (tester) async {
    Future<void> render(bool saving) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: BlueprintEditorFeedback(
                message: null,
                onDismiss: () {},
                status: saving ? 'Saving' : 'Saved',
                saving: saving,
                child: const Center(child: Text('Canvas'))))));
    await render(true);
    final canvas = tester.getRect(find.text('Canvas'));
    final notice =
        tester.getRect(find.byKey(const ValueKey('blueprint-save-status')));
    expect(notice.center.dx, closeTo(canvas.center.dx, 1));
    expect(notice.bottom, lessThan(canvas.top));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await render(false);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(tester.getRect(find.text('Canvas')), canvas);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editor error floats at bottom center and can be dismissed without moving content',
    (tester) async {
      String? message = 'Upload failed';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => BlueprintEditorFeedback(
                message: message,
                onDismiss: () => update(() => message = null),
                child: const Center(child: Text('Canvas')),
              ),
            ),
          ),
        ),
      );
      final canvas = tester.getRect(find.text('Canvas'));
      final notice = tester.getRect(
        find.byKey(const ValueKey('blueprint-editor-feedback')),
      );
      expect(
        notice.center.dx,
        tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
      );
      expect(notice.top, greaterThan(canvas.bottom));
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text('Upload failed'), findsNothing);
      expect(tester.getRect(find.text('Canvas')), canvas);
    },
  );

  testWidgets(
    'host color shell has close button and previews cancel or commit as one undo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = tableLayout(shape: 'rect', count: 0);
      final node = document.nodes.first;
      final c = VenueLayoutController(document);
      addTearDown(c.dispose);
      c.select({node.id});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorColorDialogTheme(
              builder: (context, dialog) => AppAlertDialog(
                title: dialog.title,
                content: dialog.content,
                actions: dialog.actions,
                alignment: Alignment.centerRight,
              ),
              child: VenueLayoutEditor(controller: c),
            ),
          ),
        ),
      );
      Future<void> preview() async {
        final button = find.byKey(const ValueKey('canonical-style-fill'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(AppAlertDialog), findsOneWidget);
        expect(
            tester
                .getCenter(find.descendant(
                    of: find.byType(AppAlertDialog),
                    matching: find.byIcon(Icons.close)))
                .dx,
            greaterThan(900));
        final swatch = find.byKey(
          const ValueKey('editor-color-Basic colors-2563EB'),
        );
        await tester.tap(swatch);
        await tester.pump();
        expect(c.document.nodes.first.style['fill'], '#2563EBFF');
        expect(c.canUndo, isFalse);
      }

      await preview();
      await tester.tap(find.descendant(
          of: find.byType(AppAlertDialog), matching: find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      expect(c.document.toJson(), document.toJson());
      await preview();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(c.canUndo, isTrue);
      c.undo();
      expect(c.document.toJson(), document.toJson());
      expect(c.canUndo, isFalse);
    },
  );
}
