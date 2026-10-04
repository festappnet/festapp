import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';

void main() {
  test(
      'snapshot detects nested edits, ignores map ordering, and accepts reverts',
      () {
    final data = <String, dynamic>{
      'fields': [
        {'title': 'A'}
      ],
      'data': {'x': 1, 'y': 2}
    };
    final snapshot = EditorSnapshot()..accept(data);
    expect(snapshot.differs(data), false);
    (data['fields'] as List).first['title'] = 'B';
    expect(snapshot.differs(data), true);
    (data['fields'] as List).first['title'] = 'A';
    data['data'] = {'y': 2, 'x': 1};
    expect(snapshot.differs(data), false);
    (data['fields'] as List).clear();
    expect(snapshot.differs(data), true);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'actions use a matching surface in $brightness and block duplicate saves',
        (tester) async {
      final saved = Completer<void>();
      var saves = 0;
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
              bottomNavigationBar: EditorActionBar(
                  hasChanges: true,
                  onSave: () {
                    saves++;
                    return saved.future;
                  },
                  onDiscard: () async {}))));
      final bar = tester.widget<BottomAppBar>(find.byType(BottomAppBar));
      final context = tester.element(find.byType(EditorActionBar));
      expect(bar.color, Theme.of(context).colorScheme.surface);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(saves, 1);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
      saved.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);
    });
  }
}
