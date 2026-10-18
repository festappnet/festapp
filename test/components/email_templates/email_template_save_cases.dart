import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:super_editor/super_editor.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/email_templates/views/email_templates_settings_page.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import '../../support/fixtures/root_supabase_fixture.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'email_template_dialog_cases.dart' show openTemplate;

void main() {
  late RootSupabaseFixture backend;
  var failSave = true;
  setUpAll(() async {
    backend = await RootSupabaseFixture.open((request) {
      expect(request.url.path, '/rest/v1/rpc/update_email_template');
      return failSave
          ? http.Response(
              '{"message":"Save unavailable","code":"fixture"}', 500,
              request: request, headers: {'content-type': 'application/json'})
          : http.Response('{}', 200,
              request: request, headers: {'content-type': 'application/json'});
    });
  });
  tearDownAll(() async => backend.dispose());
  testWidgets(
      'one save submits subject and body; failed save retains both for retry',
      (tester) async {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
    await openTemplate(tester);
    final editors =
        tester.widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor)).toList();
    for (final widget in editors) {
      final node = widget.controller.editor.document.first as TextNode;
      widget.controller.editor.execute([
        InsertTextRequest(
            documentPosition: DocumentPosition(
                nodeId: node.id,
                nodePosition: const TextNodePosition(offset: 0)),
            textToInsert: 'Draft ',
            attributions: {})
      ]);
    }
    await tester.pump();
    expect(find.text(CommonStrings.save), findsOneWidget);
    await tester.tap(find.text(CommonStrings.save));
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsOneWidget);
    expect(editors.first.controller.plainText, 'Draft Subject');
    expect(editors.last.controller.plainText, 'Draft Content');
    expect(editors.first.controller.hasUserChanges, isTrue);
    expect(editors.last.controller.hasUserChanges, isTrue);
    final sent = jsonDecode(backend.requests.last.body)['p_data'];
    expect(sent['subject'], 'Draft Subject');
    expect(sent['html'], '<p>Draft Content</p>');
    failSave = false;
    await tester.tap(find.text(CommonStrings.save));
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsNothing);
    expect(backend.requests.length, 2);
  });
}
