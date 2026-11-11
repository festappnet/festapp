import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/batch_progress_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import '../support/fixtures/localization_log_fixture.dart';

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  testWidgets(
      'mixed delivery results remain visible and retry excludes sent recipients',
      (tester) async {
    final calls = [0, 0, 0];
    final tasks = List.generate(
        3,
        (i) => BatchTask(
            label: ['Anna', 'Jan', 'Eva'][i],
            run: () async {
              calls[i]++;
              if (i == 1 && calls[i] == 1) throw StateError('HTTP 503');
              if (i == 2 && calls[i] == 1) return BatchTaskOutcome.deferred;
              return BatchTaskOutcome.completed;
            }));
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => BatchProgressDialog(
                            title: 'Invitations',
                            tasks: tasks,
                            successLabel: 'Sent',
                            failureLabel: 'Failed',
                            deferredLabel: 'Queued',
                            retryLabel: 'Retry unsent')),
                    child: const Text('Start'))))));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Anna: Sent'), findsOneWidget);
    expect(find.text('Jan: Failed'), findsOneWidget);
    expect(find.text('Eva: Queued'), findsOneWidget);
    expect(find.text(CommonStrings.processingCompleted), findsNothing);
    await tester.tap(find.text('Retry unsent'));
    await tester.pumpAndSettle();
    expect(calls, [1, 2, 2]);
    expect(find.text(CommonStrings.processingCompleted), findsOneWidget);
    expect(find.text('Jan: Sent'), findsOneWidget);
  });
}
