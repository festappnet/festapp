import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/fonts/font_family_picker.dart';

void main() {
  testWidgets(
      'popular, custom family and reset preserve previous selection on load failure',
      (tester) async {
    String? value;
    var fail = false;
    final calls = <String?>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => FontFamilyPicker(
                    value: value,
                    families: const ['Roboto', 'Russo One'],
                    onSelected: (font) async {
                      calls.add(font);
                      if (fail) throw StateError('offline');
                      setState(() => value = font);
                    })))));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roboto').last);
    await tester.pumpAndSettle();
    expect(value, 'Roboto');
    await tester.enterText(find.byType(TextField), 'Russo One');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(value, 'Russo One');
    fail = true;
    await tester.enterText(find.byType(TextField), 'Roboto');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(value, 'Russo One');
    fail = false;
    await tester.tap(find.byIcon(Icons.restore));
    await tester.pumpAndSettle();
    expect(value, isNull);
    expect(calls, ['Roboto', 'Russo One', 'Roboto', null]);
  });
  testWidgets('loading is visible and disposed response cannot update picker',
      (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FontFamilyPicker(
                value: null,
                families: const ['Roboto'],
                onSelected: (_) => pending.future))));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roboto').last);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
