import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/editor_ui.dart';

void main() {
  testWidgets('a focused child consumes Escape before the route dismissal', (tester) async {
    var childOpen = true;
    var closes = 0;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      TextButton(onPressed: () => showEditorDialog<void>(context: context,
        builder: (_) => EditorDialogDismissal(onClose: () => closes++, child:
          Focus(focusNode: focus, autofocus: true, onKeyEvent: (_, event) {
            if (childOpen && event.logicalKey == LogicalKeyboardKey.escape) {
              if (event is KeyDownEvent) childOpen = false;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }, child: const Text('menu')))), child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(childOpen, false);
    expect(closes, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closes, 1);
  });
}
