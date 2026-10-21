import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/editor_ui.dart';

void main() {
  Future<void> wheel(WidgetTester tester, Finder field, double dy) async {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(field),
        scrollDelta: Offset(0, dy),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'focused wheel edits use normal callbacks and consume panel scrolling',
    (tester) async {
      final text = TextEditingController(text: '40'),
          scroll = ScrollController();
      addTearDown(text.dispose);
      addTearDown(scroll.dispose);
      final changes = <String>[];
      var commits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 250,
              child: ListView(
                controller: scroll,
                children: [
                  EditorNumberScroll(
                    onChanged: () => commits++,
                    child: TextField(controller: text, onChanged: changes.add),
                  ),
                  const SizedBox(height: 1500),
                ],
              ),
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pump();
      await wheel(tester, field, -100);
      expect(text.text, '41');
      expect(changes, ['41']);
      expect(commits, 1);
      expect(scroll.offset, 0);
      await wheel(tester, field, 100);
      expect(text.text, '40');
      expect(commits, 2);
      expect(scroll.offset, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await wheel(tester, field, -100);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(text.text, '50');
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      await wheel(tester, field, 100);
      expect(text.text, '50');
      expect(scroll.offset, greaterThan(0));
    },
  );
  testWidgets(
    'decimal steps clamp at bounds and preserve standard form updates',
    (tester) async {
      final key = GlobalKey<FormFieldState<String>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorNumberScroll(
              min: 0,
              max: 1,
              step: .05,
              child: TextFormField(key: key, initialValue: '0,95'),
            ),
          ),
        ),
      );
      final field = find.byType(TextFormField);
      await tester.tap(field);
      await tester.pump();
      await wheel(tester, field, -100);
      expect(key.currentState!.value, '1');
      await wheel(tester, field, -100);
      expect(key.currentState!.value, '1');
      await wheel(tester, field, 100);
      expect(key.currentState!.value, '0.95');
    },
  );
  testWidgets(
    'hovering a different field or a read-only field does not change its number',
    (tester) async {
      final a = TextEditingController(text: '10'),
          b = TextEditingController(text: '20');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                EditorNumberScroll(child: TextField(controller: a)),
                EditorNumberScroll(
                  child: TextField(controller: b, readOnly: true),
                ),
              ],
            ),
          ),
        ),
      );
      final fields = find.byType(TextField);
      await tester.tap(fields.first);
      await tester.pump();
      await wheel(tester, fields.last, -100);
      expect(b.text, '20');
      expect(a.text, '10');
      await tester.tap(fields.last);
      await tester.pump();
      await wheel(tester, fields.last, -100);
      expect(b.text, '20');
    },
  );
}
