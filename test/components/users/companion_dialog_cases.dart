import 'dart:async';

import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/connectivity_service.dart';
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

  testWidgets('attendance refreshes in order and uses the live sign-in gate',
      (tester) async {
    final calls = <String>[];
    var canSignIn = true;
    final signedIn = CompanionModel.fromJson({
      ...assigned.toJson(),
      'event_ids': [42],
    });
    await tester.pumpWidget(MaterialApp(
      home: CompanionAttendanceDialog(
        eventId: 42,
        companions: [assigned],
        canSignIn: () => canSignIn,
        changeAttendance: (eventId, companion, signIn) async {
          expect(eventId, 42);
          expect(companion.id, assigned.id);
          expect(signIn, isTrue);
          calls.add('change');
        },
        refreshData: () async {
          calls.add('refresh');
          canSignIn = false;
        },
        reloadCompanions: () async {
          calls.add('reload');
          return [signedIn, created];
        },
      ),
    ));

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(calls, ['change', 'refresh', 'reload']);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNotNull,
        reason: 'refreshed attendance offers sign-out');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: 'refreshed capacity blocks another sign-in');
  });

  testWidgets('attendance can close while its companion reload is pending',
      (tester) async {
    final reload = Completer<List<CompanionModel>>();
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => CompanionAttendanceDialog(
                      eventId: 42,
                      companions: [assigned],
                      canSignIn: () => true,
                      changeAttendance: (_, __, ___) async =>
                          calls.add('change'),
                      refreshData: () async => calls.add('refresh'),
                      reloadCompanions: () {
                        calls.add('reload');
                        return reload.future;
                      },
                    ),
                  ),
                  child: const Text('Open attendance'),
                ),
              )),
    ));
    await tester.tap(find.text('Open attendance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(calls, ['change', 'refresh', 'reload']);

    Navigator.of(tester.element(find.byType(CompanionAttendanceDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(CompanionAttendanceDialog), findsNothing);
    reload.complete([created]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(calls, ['change', 'refresh', 'reload']);
  });

  testWidgets('offline attendance blocks both sign-in and sign-out',
      (tester) async {
    final wasOffline = ConnectivityService.isOfflineNotifier.value;
    addTearDown(() => ConnectivityService.isOfflineNotifier.value = wasOffline);
    ConnectivityService.isOfflineNotifier.value = false;
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
      home: CompanionAttendanceDialog(
        eventId: 42,
        companions: [
          CompanionModel.fromJson({
            ...assigned.toJson(),
            'event_ids': [42]
          }),
          created,
        ],
        canSignIn: () => true,
        refreshData: () async {},
        changeAttendance: (_, __, ___) async {
          changes++;
        },
        reloadCompanions: () async => [],
      ),
    ));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNotNull);

    ConnectivityService.isOfflineNotifier.value = true;
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    await tester.tap(find.byType(FilledButton));
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(changes, 0);
  });
}
