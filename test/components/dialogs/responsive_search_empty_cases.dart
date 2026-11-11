import 'package:flutter/services.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/dialogs/responsive_search_dialog.dart';

import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  testWidgets('empty collection guidance differs from no search results', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: ResponsiveSearchDialog<String>(
          items: const [],
          searchLabel: 'Search participants',
          description: 'Participants from this unit',
          emptyState: const Text('Return and add a participant'),
          filter: (item, query) => item.contains(query),
          itemBuilder: Text.new,
        ),
      ),
    );
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

  testWidgets('group selection searches accents and returns the chosen model', (
    tester,
  ) async {
    final yellow = UserGroupInfoModel(id: 1, title: 'Žlutá skupina');
    final blue = UserGroupInfoModel(id: 2, title: 'Modrá skupina');
    UserGroupInfoModel? chosen;
    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  chosen = await DialogHelper.showAddToGroupDialogAsync(
                    context,
                    [yellow, blue],
                  ),
              child: const Text('Choose'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zluta');
    await tester.pumpAndSettle();
    expect(find.text(blue.title), findsNothing);
    await tester.tap(find.text(yellow.title));
    await tester.pumpAndSettle();
    expect(chosen, same(yellow));
  });

  testWidgets('Escape cancels group selection without choosing a value', (
    tester,
  ) async {
    var completed = false;
    UserGroupInfoModel? chosen = UserGroupInfoModel(id: 0, title: 'Unchanged');
    await tester.pumpWidget(
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await DialogHelper.showAddToGroupDialogAsync(context, [
                  UserGroupInfoModel(id: 1, title: 'Group'),
                ]);
                completed = true;
              },
              child: const Text('Choose'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(chosen, isNull);
  });
}
