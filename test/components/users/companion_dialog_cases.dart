import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/companion/companion_dialog.dart';
import 'package:fstapp/components/users/companion/companion_model.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  final assigned = CompanionModel(
    id: 'assigned',
    name: 'Ada',
    surname: 'Lovelace',
    groupTitle: 'DISK 19',
    origin: 'admin_assigned',
    canOwnerDelete: false,
    eventIds: [],
  );
  final created = CompanionModel(
    id: 'created',
    name: 'Grace',
    surname: 'Hopper',
    origin: 'self_created',
    canOwnerDelete: true,
    eventIds: [],
  );

  testWidgets('management separates create and origin-safe delete actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CompanionManagementDialog(
        allowUserCreate: false,
        maxCompanions: 2,
        companions: [assigned, created],
        refreshData: () async {},
        reloadCompanions: () async => [assigned, created],
      ),
    ));

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('DISK 19'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget,
        reason: 'only the self-created companion is deletable');
  });

  testWidgets('attendance has no lifecycle controls and targets companion id',
      (tester) async {
    String? participant;
    await tester.pumpWidget(MaterialApp(
      home: CompanionAttendanceDialog(
        eventId: 42,
        companions: [assigned],
        canSignIn: () => true,
        refreshData: () async {},
        changeAttendance: (eventId, companion, signIn) async {
          expect(eventId, 42);
          expect(signIn, isTrue);
          participant = companion.id;
        },
        reloadCompanions: () async => [assigned],
      ),
    ));

    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(participant, 'assigned');
  });
}
