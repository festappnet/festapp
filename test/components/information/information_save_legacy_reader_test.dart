import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  var commandStatus = 'applied';
  final requests = <http.Request>[];
  const canonicalHtml = '<p>Hotels and pensions</p>';
  setUpAll(() async {
    await Supabase.initialize(
        url: 'https://example.test',
        publishableKey: 'test-key',
        authOptions: const FlutterAuthClientOptions(
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUri: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          Object response;
          if (request.url.path == '/rest/v1/information' &&
              request.method != 'GET') {
            return http.Response(
                jsonEncode({
                  'code': '42501',
                  'message': 'permission denied for table information'
                }),
                403,
                headers: {'content-type': 'application/json'},
                request: request);
          }
          switch (request.url.path) {
            case '/rest/v1/information':
              response = [
                {
                  'id': 12,
                  'title': 'Accommodation',
                  'description': '<p>Stale cached HTML</p>'
                },
                {
                  'id': 13,
                  'title': 'Song',
                  'type': 'song',
                  'description': '<p>Song text</p>'
                },
              ];
            case '/rest/v1/rpc/get_information_editor_bundle_v1':
              final parameters =
                  jsonDecode(request.body) as Map<String, dynamic>;
              expect(parameters['p_occasion'], 1);
              response = {
                'code': 200,
                'information': [
                  {
                    'id': 12,
                    'title': 'Accommodation',
                    'description': canonicalHtml,
                    'aggregate_version': 7
                  },
                  {
                    'id': 14,
                    'title': 'Hidden',
                    'is_hidden': true,
                    'aggregate_version': 2
                  },
                ]
              };
            case '/rest/v1/rpc/save_information_client_sync_v1':
              final parameters =
                  jsonDecode(request.body) as Map<String, dynamic>;
              expect(parameters['p_expected_version'], 7);
              expect(parameters['p_occasion'], 1);
              expect(parameters['p_command_id'], isNotEmpty);
              response = {
                'status': commandStatus,
                'code': 200,
                'data': {
                  'version': 8,
                  if (commandStatus == 'applied')
                    'information': parameters['p_information']
                },
                'mutation': {
                  'commandId': '00000000-0000-4000-8000-000000000001',
                  'receiptId': '00000000-0000-4000-8000-000000000001',
                  'commitId': null,
                  'replayed': false,
                  'occurredAt': '2026-10-07T10:00:00Z'
                },
                'sync': {'replacements': <Object>[]}
              };
            default:
              throw StateError(
                  'Unexpected request: ${request.method} ${request.url.path}');
          }
          return http.Response(jsonEncode(response), 200,
              headers: {'content-type': 'application/json'}, request: request);
        }));
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    commandStatus = 'applied';
    requests.clear();
    expect(ClientSyncRuntime.isV1Selected, isFalse);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasionUser: OccasionUserModel(isEditor: true),
        occasion: OccasionModel(
            id: 1, isOpen: true, isHidden: false, isPromoted: false));
  });
  tearDown(() => RightsService.occasionLinkModelNotifier.value = null);

  test('information Save succeeds through canonical RPC with legacy readers',
      () async {
    final information = InformationModel(
        id: 12,
        title: 'Accommodation',
        description: '<p>Edited hotels</p>',
        aggregateVersion: 7);
    await DbInformation.updateInformation(information);
    expect(information.aggregateVersion, 8);
    expect(requests.single.method, 'POST');
  });

  test(
      'editor reads content and version together while preserving public songs',
      () async {
    final information = await DbInformation.getAllActiveInformation();
    final editable = information.singleWhere((info) => info.id == 12);
    expect(editable.description, canonicalHtml);
    expect(editable.aggregateVersion, 7);
    expect(information.any((info) => info.id == 14), isFalse);
    expect(information.singleWhere((info) => info.id == 13).description,
        '<p>Song text</p>');
  });

  test('public readers do not request private editor metadata', () async {
    RightsService.occasionLinkModelNotifier.value!.occasionUser!.isEditor =
        false;
    final information = await DbInformation.getAllActiveInformation();
    expect(information, hasLength(2));
    expect(requests.single.method, 'GET');
    expect(requests.single.url.path, '/rest/v1/information');
  });

  test('conflicts cannot overwrite another editors information', () async {
    commandStatus = 'conflict';
    final information = InformationModel(
        id: 12, description: '<p>Draft</p>', aggregateVersion: 7);
    await expectLater(
        DbInformation.updateInformation(information), throwsStateError);
    expect(information.aggregateVersion, 7);
    expect(requests, hasLength(1));
  });

  testWidgets('inline Information Save persists edited HTML and leaves editing',
      (tester) async {
    final loaded = await DbInformation.getAllActiveInformation();
    final List<InformationModel> cached;
    if (kIsWeb) {
      cached = (await tester.runAsync(() async {
        await OfflineDataService.saveAllInfo(loaded);
        return OfflineDataService.getAllInfo();
      }))!;
    } else {
      // Same JSON codec as the persistent cache; web runs the real store.
      cached = (jsonDecode(jsonEncode(loaded)) as List)
          .map((row) => InformationModel.fromJson(row as Map<String, dynamic>))
          .toList();
    }
    final information = cached.singleWhere((info) => info.id == 12);
    expect(information.aggregateVersion, 7);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EditableHtmlField(
                html: information.description,
                onChanged: (_) {},
                onSave: (html) async {
                  information.description = html;
                  await DbInformation.updateInformation(information);
                }))));
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    final controller =
        tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
    final node = controller.editor.document.first as TextNode;
    controller.editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: node.id,
              nodePosition: TextNodePosition(offset: node.text.length)),
          textToInsert: ' updated',
          attributions: {})
    ]);
    await tester.pump();
    await tester.tap(find.text('Common.save'));
    await tester.pumpAndSettle();
    expect(find.byType(RichHtmlEditor), findsNothing);
    expect(information.aggregateVersion, 8);
    final save = requests.singleWhere((request) =>
        request.url.path.endsWith('/save_information_client_sync_v1'));
    expect(jsonDecode(save.body)['p_information']['description'],
        '<p>Hotels and pensions updated</p>');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
