import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/client_changes/client_change_model.dart';
import 'package:fstapp/components/client_changes/client_changes_tab.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  Widget testApp(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows the pre-activation state without querying Supabase',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ClientChangesTab(clientSyncEnabled: false),
        ),
      ),
    );

    expect(find.byIcon(Icons.history_toggle_off), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('loads an aggregate seven-day activity range', (tester) async {
    DateTime? requestedFrom;
    DateTime? requestedTo;

    Future<List<ClientActivityDay>> load({
      required int occasionId,
      required DateTime from,
      required DateTime to,
    }) async {
      requestedFrom = from;
      requestedTo = to;
      return const [];
    }

    await tester.pumpWidget(testApp(
      ClientChangesTab(
        clientSyncEnabled: true,
        activityLoader: load,
        isOffline: () async => false,
        occasionId: 1,
      ),
    ));
    await tester.pumpAndSettle();

    expect(requestedTo!.difference(requestedFrom!), const Duration(days: 7));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('can switch the aggregate activity range to fourteen days',
      (tester) async {
    final requestedRanges = <Duration>[];

    Future<List<ClientActivityDay>> load({
      required int occasionId,
      required DateTime from,
      required DateTime to,
    }) async {
      requestedRanges.add(to.difference(from));
      return const [];
    }

    await tester.pumpWidget(testApp(
      ClientChangesTab(
        clientSyncEnabled: true,
        activityLoader: load,
        isOffline: () async => false,
        occasionId: 1,
      ),
    ));
    await tester.pumpAndSettle();

    final rangeSelector = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    rangeSelector.onSelectionChanged!({14});
    await tester.pumpAndSettle();

    expect(requestedRanges, [
      const Duration(days: 7),
      const Duration(days: 14),
    ]);
  });

  testWidgets('renders daily change columns without users', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());

    Future<List<ClientActivityDay>> load({
      required int occasionId,
      required DateTime from,
      required DateTime to,
    }) async =>
        [
          ClientActivityDay(
            day: today,
            actionCount: 511,
            changedItemCount: 511,
            activeActorCount: 42,
          ),
        ];

    await tester.pumpWidget(testApp(
      ClientChangesTab(
        clientSyncEnabled: true,
        activityLoader: load,
        isOffline: () async => false,
        occasionId: 1,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ClientActivityBarChart), findsOneWidget);
    expect(
      find.byKey(
          ValueKey('activity-${today.year}-${today.month}-${today.day}')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.person_search), findsNothing);
  });
}
