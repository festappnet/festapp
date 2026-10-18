import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/email_templates.dart';
import 'package:fstapp/components/email_templates/email_authoring_provider.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/email_templates/email_preview_examples.dart';
import 'package:fstapp/components/email_templates/email_preview_html.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/template_authoring.dart';
import 'package:super_editor/super_editor.dart';
import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test(
      'catalog variables have generated values and subject supports only scalar',
      () {
    final examples = EmailPreviewExamples.fromJson(jsonDecode(
        File('assets/email_templates/preview_examples.json')
            .readAsStringSync()));
    for (final item in EmailTemplateModel.substitutionDefinitions.entries) {
      final scenarios = examples.scenariosFor(item.key);
      expect(scenarios, isNotEmpty, reason: item.key);
      for (final scenario in scenarios) {
        for (final sub in item.value) {
          expect(scenario.values.containsKey(sub.code), isTrue,
              reason: '${item.key}/${scenario.scenario}/${sub.code}');
          expect(
              sub.supportsField(EmailTargetField.subject),
              sub.kind == EmailValueKind.text ||
                  sub.kind == EmailValueKind.url);
        }
      }
    }
  });
  testWidgets(
      'addresses never publish composing menu; query insert and Escape stay local',
      (tester) async {
    final controller = RichHtmlEditorController(
        initialHtml: '<p></p>',
        owner: const HtmlMediaOwner.none(),
        authoring: EmailAuthoringProvider(
            EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
            field: EmailTargetField.body));
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RichHtmlEditor(
                controller: controller, onCancel: () => cancelled = true))));
    for (final text in [
      'jana@',
      'jana.novakova@',
      'jana+akce@',
      'jana+@',
      'jana@example.cz',
      'https://example.invalid/@name'
    ]) {
      controller.reset('<p></p>');
      final node = controller.editor.document.first as TextNode;
      controller.editor.execute([
        ChangeSelectionRequest(
            DocumentSelection.collapsed(
                position: DocumentPosition(
                    nodeId: node.id,
                    nodePosition: const TextNodePosition(offset: 0))),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction)
      ]);
      for (final char in text.split('')) {
        controller.editor.execute([
          InsertTextRequest(
              documentPosition: controller.editor.composer.selection!.extent,
              textToInsert: char,
              attributions: {})
        ]);
        expect(controller.composingTag, isNull, reason: text);
        await tester.pump();
      }
    }
    controller.reset('<p></p>');
    final node = controller.editor.document.first as TextNode;
    controller.editor.execute([
      ChangeSelectionRequest(
          DocumentSelection.collapsed(
              position: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 0))),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction)
    ]);
    controller.focusNode.requestFocus();
    controller.editor.execute([
      InsertTextRequest(
          documentPosition: controller.editor.composer.selection!.extent,
          textToInsert: '@',
          attributions: {})
    ]);
    await tester.pump();
    await tester.pump();
    expect(controller.composingTag, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.composingTag, isNull);
    expect(cancelled, isFalse);
    expect(controller.plainText, '@');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(cancelled, isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
      'explicit chooser retains caret across search focus and inserts with Enter',
      (tester) async {
    final controller = RichHtmlEditorController(
        initialHtml: '<p>Before </p>',
        owner: const HtmlMediaOwner.none(),
        authoring: EmailAuthoringProvider(
            EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
            field: EmailTargetField.subject));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RichHtmlEditor(controller: controller))));
    await tester.tap(find.widgetWithIcon(TextButton, Icons.alternate_email));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'occasionTitle');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.plainText, 'Before {{occasionTitle}}');
    expect(find.byType(TextField), findsNothing);
    expect(controller.focusNode.hasFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(controller.plainText, 'Before ');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('subject IME requests and paste remain one plain paragraph',
      (tester) async {
    final provider = EmailAuthoringProvider(
        EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
        field: EmailTargetField.subject);
    final controller = RichHtmlEditorController(
        initialHtml: '<p>A</p>',
        owner: const HtmlMediaOwner.none(),
        authoring: provider);
    addTearDown(controller.dispose);
    final node = controller.editor.document.first as TextNode;
    controller.editor.execute([
      ChangeSelectionRequest(
          DocumentSelection.collapsed(
              position: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 1))),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction)
    ]);
    controller.editor.execute([
      InsertTextRequest(
          documentPosition: controller.editor.composer.selection!.extent,
          textToInsert: '\nB',
          attributions: {})
    ]);
    await controller.pasteHtml('<p><b>One</b><br>Two {{occasionTitle}}</p>');
    expect(controller.editor.document.length, 1);
    expect(controller.plainText, contains('One Two {{occasionTitle}}'));
    expect(controller.plainText, isNot(contains('\n')));
    expect(controller.insertTemplateToken('fullOrder'), isFalse);
    expect(
        (controller.editor.document.first as TextNode).text.placeholders.values,
        contains(const TemplateTokenPlaceholder('occasionTitle')));
  });
  testWidgets(
      'preview preserves readable button styles without tap or URL semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: EmailPreviewHtml(
                html:
                    '<a href="https://example.com/real-capability" style="display:inline-block;background:#1565c0;color:white;padding:12px 20px;border-radius:6px">Overview</a><a href="mailto:real@example.com">Email</a>'))));
    await tester.pumpAndSettle();
    expect(find.text('Overview', findRichText: true), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    await tester.tap(find.text('Overview', findRichText: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
