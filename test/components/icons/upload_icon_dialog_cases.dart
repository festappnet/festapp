import '../../support/fixtures/localization_log_fixture.dart';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/icons/icons_management_widget.dart';
import 'package:fstapp/widgets/drop_file.dart';

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path d="M0 0h24v24H0z"/></svg>';

Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: UploadIconDialog())),
  );
}

Future<void> _selectSvg(WidgetTester tester,
    {String name = 'my_icon.svg'}) async {
  final dropFile = tester.widget<DropFile>(find.byType(DropFile));
  dropFile.onFilePathChanged(XFile.fromData(utf8.encode(_svg), name: name));
  await tester.pumpAndSettle();
}

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('Save is disabled until an SVG is selected', (tester) async {
    await _pumpDialog(tester);
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
  });

  testWidgets('selecting an SVG shows preview and name field, enables Save',
      (tester) async {
    await _pumpDialog(tester);
    await _selectSvg(tester);

    // Note: XFile.fromData ignores `name` off-web, so auto-fill from the
    // filename can't be asserted here; the field itself must appear and
    // Save enables once a name is typed.
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'my_icon');
    await tester.pump();
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNotNull);
  });

  testWidgets('tapping Save with a name gives visible feedback',
      (tester) async {
    await _pumpDialog(tester);
    await _selectSvg(tester);
    await tester.enterText(find.byType(TextField), 'my_icon');
    await tester.pump();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // No unit/session exists in the test env, so a correctly wired dialog
    // must surface the failure via the error Text (or pop on success).
    final dialogGone = find.byType(UploadIconDialog).evaluate().isEmpty;
    final errorShown = tester.any(find.textContaining('no_unit')) ||
        tester.any(find.textContaining('Exception')) ||
        tester.any(find.textContaining('Error'));
    expect(dialogGone || errorShown, isTrue,
        reason: 'Tapping Save produced no visible state change');
  });

  testWidgets('Save is disabled while the name is empty (no silent no-op)',
      (tester) async {
    await _pumpDialog(tester);
    await _selectSvg(tester);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: 'Save must be disabled with an empty name, '
            'otherwise clicking it silently does nothing');

    await tester.enterText(find.byType(TextField), 'my_icon');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}
