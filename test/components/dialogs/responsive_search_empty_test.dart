import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/dialogs/responsive_search_dialog.dart';
import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  testWidgets('empty collection guidance differs from no search results',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ResponsiveSearchDialog<String>(
        items: const [],
        searchLabel: 'Search participants',
        description: 'Participants from this unit',
        emptyState: const Text('Return and add a participant'),
        filter: (item, query) => item.contains(query),
        itemBuilder: Text.new,
      ),
    ));
    expect(find.text('Participants from this unit'), findsOneWidget);
    expect(find.text('Return and add a participant'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.pump();
    expect(find.text('Return and add a participant'), findsNothing);
    expect(find.text('Dialogs.noResults'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('Return and add a participant'), findsOneWidget);
  });
}
