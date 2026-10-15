import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/counseling_hours_panel.dart';
import 'package:fstapp/components/map/map_page_helper.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('each counseling range is a theme-aware action', (tester) async {
    CounselingHoursRange? selected;
    final range = CounselingHoursRange(
      start: DateTime(2026, 8, 12, 14),
      end: DateTime(2026, 8, 12, 18, 55),
      entryEventId: 42,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.blue),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: Colors.blue,
        ),
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: CounselingHoursPanel(
            ranges: [range],
            onRangePressed: (value) => selected = value,
          ),
        ),
      ),
    );

    expect(find.byType(InkWell), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    expect(selected?.entryEventId, 42);

    final context = tester.element(find.byType(CounselingHoursPanel));
    final title = tester.widget<Text>(
      find
          .descendant(of: find.byType(InkWell), matching: find.byType(Text))
          .first,
    );
    expect(title.style?.color, Theme.of(context).colorScheme.onSurface);
  });
}
