import 'package:fstapp/components/users/member_access_batch.dart';

import 'dart:async';

import 'package:festapp_core/time.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';

import '../../support/fixtures/rights_context_fixture.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/users/views/member_access_dialog.dart';
import 'package:fstapp/components/users/unit_user_model.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/root_supabase_fixture.dart';
import '../../support/fixtures/localization_log_fixture.dart';

class _SelectionGrid extends SingleDataGridController<UnitUserModel> {
  _SelectionGrid(
    BuildContext context,
    this.checked,
    Future<List<UnitUserModel>> Function() load,
  ) : super(
        context: context,
        loadData: load,
        fromPlutoJson: UnitUserModel.fromPlutoJson,
        firstColumnType: DataGridFirstColumn.check,
        idColumn: 'user',
        columns: [],
      );
  final List<TrinaRow> checked;
  @override
  Iterable<TrinaRow> get visibleCheckedRows => checked;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RootSupabaseFixture fixture;
  final sent = <Map<String, dynamic>>[];
  late Completer<void> initialStatus;
  late Completer<void> refreshedStatus;
  Completer<void>? expectedRead;
  var statusReads = 0;
  var deliveryState = 'delivered';
  String? failingUser;
  setUpAll(() async {
    OccasionTimeContext.initializeTimeZones();
    fixture = await RootSupabaseFixture.open((request) async {
      Object response;
      if (request.url.path.endsWith('/get_member_access_status')) {
        statusReads++;
        response = {
          'invitations': [],
          'messages': [
            for (var index = 0; index < sent.length; index++)
              if (sent[index]['userId'] != failingUser || failingUser == null)
                {
                  'messageId': 'message-${index + 1}',
                  'state': deliveryState,
                  'userId': sent[index]['userId'],
                  'recipient':
                      sent[index]['email'] ??
                      '${sent[index]['userId']}@example.test',
                  'code': 'TEAM_ACCESS_NOTICE',
                },
            {
              'messageId': 'unrelated',
              'state': 'delivered',
              'recipient': 'other@example.test',
              'code': 'TEAM_ACCESS_NOTICE',
            },
          ],
        };
        if (expectedRead?.isCompleted == false) expectedRead!.complete();
        final completion = sent.isEmpty ? initialStatus : refreshedStatus;
        if (!completion.isCompleted) completion.complete();
      } else if (request.url.path.endsWith('/manage-member-access')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sent.add(Map<String, dynamic>.from(body['request']));
        if (failingUser != null && sent.last['userId'] == failingUser) {
          return http.Response(
            jsonEncode({'reasonCode': 'preparation_deferred'}),
            400,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        response = {
          'status': 'applied',
          'code': 200,
          'data': {
            'communication': {
              'state': 'queued',
              'messageId': 'message-${sent.length}',
            },
          },
          'mutation': {
            'commandId': body['commandId'],
            'receiptId': body['commandId'],
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-11-11T10:00:00Z',
          },
          'sync': {'replacements': []},
        };
      } else {
        throw StateError('Unexpected ${request.url.path}');
      }
      return http.Response(
        jsonEncode(response),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
  });
  tearDownAll(() => fixture.dispose());
  setUp(() {
    sent.clear();
    deliveryState = 'delivered';
    failingUser = null;
    statusReads = 0;
    expectedRead = null;
    initialStatus = Completer<void>();
    refreshedStatus = Completer<void>();
    final rights = RightsContextFixture(
      context: OccasionLinkModel(
        capabilities: {AuthorizationCapabilities.unitUsersWrite: true},
      ),
    );
    addTearDown(rights.dispose);
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  for (final width in [900.0, 390.0]) {
    testWidgets(
      'selected grid opens saved mixed grants and sends notices at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final manager = UnitUserModel(
          user: 'manager',
          name: 'Jana',
          surname: 'Nováková',
          emailReadonly: 'jana@example.test',
          isManager: true,
        );
        final viewer = UnitUserModel(
          user: 'viewer',
          name: 'Petr',
          surname: 'Novák',
          emailReadonly: 'petr@example.test',
          isEditorView: true,
        );
        var loads = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            builder: DependencyMaterialBridge.builder,
            home: Builder(
              builder: (context) {
                // The draft editor flags deliberately disagree with saved manager/viewer roles.
                final rows = [
                  UnitUserModel(
                    user: 'manager',
                    isEditor: true,
                  ).toTrinaRow(context),
                  UnitUserModel(
                    user: 'viewer',
                    isEditor: true,
                  ).toTrinaRow(context),
                ];
                final grid = _SelectionGrid(context, rows, () async {
                  loads++;
                  return [manager, viewer];
                });
                return Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        MemberAccessDialog.show(context, 'unit', 2, grid: grid),
                    child: const Text('Open'),
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => initialStatus.future.timeout(const Duration(seconds: 5)),
        );
        await tester.pumpAndSettle();
        expect(loads, 1);
        expect(find.text('Jana Nováková\njana@example.test'), findsOneWidget);
        expect(find.text('Petr Novák\npetr@example.test'), findsOneWidget);
        expect(
          find.textContaining(
            'MemberAccess.currentPermissions: MemberAccess.is_manager',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'MemberAccess.currentPermissions: MemberAccess.is_editor_view',
          ),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await tester.tap(find.text('MemberAccess.sendSelected'));
          await refreshedStatus.future.timeout(const Duration(seconds: 5));
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(sent.map((request) => request['userId']), ['manager', 'viewer']);
        for (final request in sent) {
          expect(request['scope'], {'type': 'unit', 'id': 2});
          expect(request['communication'], 'notify_existing_access');
          expect(request.containsKey('changes'), isFalse);
          expect(request.containsKey('roles'), isFalse);
        }
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  Future<void> completeRead(
    WidgetTester tester,
    Completer<void> completion,
  ) async {
    // Keep user callbacks and polling timers in the fake clock. Only drain the
    // mocked HTTP client's real async work between deterministic widget pumps.
    for (var turn = 0; turn < 20 && !completion.isCompleted; turn++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(completion.isCompleted, isTrue);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> openDelivery(
    WidgetTester tester, {
    required bool selected,
    bool two = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        builder: DependencyMaterialBridge.builder,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => MemberAccessDialog(
                  scope: 'unit',
                  scopeId: 2,
                  recipients: selected
                      ? [
                          MemberAccessRecipient(
                            userId: 'manager',
                            email: 'jana@example.test',
                            roles: {'is_manager': true},
                          ),
                          if (two)
                            MemberAccessRecipient(
                              userId: 'viewer',
                              email: 'petr@example.test',
                              roles: {'is_editor_view': true},
                            ),
                        ]
                      : const [],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await completeRead(tester, initialStatus);
    if (!selected)
      await tester.enterText(find.byType(TextField), 'jana@example.test');
    await tester.tap(
      find.text(selected ? 'MemberAccess.sendSelected' : 'MemberAccess.send'),
    );
    await completeRead(tester, refreshedStatus);
  }

  Future<void> poll(WidgetTester tester, Duration elapsed) async {
    expectedRead = Completer<void>();
    await tester.pump(elapsed);
    await completeRead(tester, expectedRead!);
  }

  for (final selected in [true, false]) {
    testWidgets(
      'delivery updates queued accepted delivered automatically for selected $selected',
      (tester) async {
        deliveryState = 'queued';
        await openDelivery(tester, selected: selected);
        expect(find.text('MemberAccess.deliveryProgress: 0/1'), findsOneWidget);
        expect(find.text('MemberAccess.deliveryQueued: 1'), findsOneWidget);
        expect(find.text('MemberAccess.queued'), findsNothing);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'MemberAccess.close'),
              )
              .onPressed,
          isNotNull,
        );
        deliveryState = 'provider_accepted';
        await poll(tester, const Duration(seconds: 2));
        expect(find.text('MemberAccess.provider_accepted: 1'), findsOneWidget);
        expect(find.text('MemberAccess.deliveryProgress: 0/1'), findsOneWidget);
        deliveryState = 'delivered';
        await poll(tester, const Duration(seconds: 5));
        expect(find.text('MemberAccess.deliveryProgress: 1/1'), findsOneWidget);
        expect(find.text('MemberAccess.deliveryQueued: 1'), findsNothing);
        expect(find.text('MemberAccess.deliveryWatching'), findsNothing);
        final reads = statusReads;
        await tester.pump(const Duration(minutes: 3));
        expect(statusReads, reads);
        expect(sent, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'delivery progression retains partial batch failures without resending',
    (tester) async {
      deliveryState = 'queued';
      failingUser = 'viewer';
      await openDelivery(tester, selected: true, two: true);
      expect(find.text('MemberAccess.batchPartial'), findsOneWidget);
      expect(find.text('MemberAccess.deliveryProgress: 0/1'), findsOneWidget);
      deliveryState = 'delivered';
      await poll(tester, const Duration(seconds: 2));
      expect(find.text('MemberAccess.deliveryProgress: 1/1'), findsOneWidget);
      expect(find.text('MemberAccess.batchPartial'), findsOneWidget);
      expect(find.text('MemberAccess.retryFailed'), findsOneWidget);
      expect(sent, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('closing pending delivery cancels future status requests', (
    tester,
  ) async {
    deliveryState = 'queued';
    await openDelivery(tester, selected: true);
    final reads = statusReads;
    await tester.tap(find.text('MemberAccess.close'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 3));
    expect(statusReads, reads);
    expect(sent, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
