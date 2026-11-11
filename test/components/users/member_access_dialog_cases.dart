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
  setUpAll(() async {
    OccasionTimeContext.initializeTimeZones();
    fixture = await RootSupabaseFixture.open((request) async {
      Object response;
      if (request.url.path.endsWith('/get_member_access_status')) {
        response = {'invitations': [], 'messages': []};
        final completion = sent.isEmpty ? initialStatus : refreshedStatus;
        if (!completion.isCompleted) completion.complete();
      } else if (request.url.path.endsWith('/manage-member-access')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sent.add(Map<String, dynamic>.from(body['request']));
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
}
