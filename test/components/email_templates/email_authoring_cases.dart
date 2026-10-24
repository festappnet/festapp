import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
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
  testWidgets('ticket variable example shows the delivered QR structure',
      (tester) async {
    final provider = EmailAuthoringProvider(
        EmailTemplateModel(code: 'TICKET_ORDER_PAYMENT_DONE'),
        field: EmailTargetField.body)
      ..inlineTicketsEnabled = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => provider.preview(context, 'tickets')!))));
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Vaše vstupenka'), findsOneWidget);
    expect(
        find.text('Kód vstupenky: festapp-preview:INVALID-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('QR ticket variable stays hidden without enabled inline delivery', () {
    final provider = EmailAuthoringProvider(
        EmailTemplateModel(code: 'TICKET_ORDER_PAYMENT_DONE'),
        field: EmailTargetField.body);
    expect(
        provider.search('', const {}).any((entry) => entry.code == 'tickets'),
        isFalse);
    expect(provider.entry('tickets'), isNull);
    provider.inlineTicketsEnabled = true;
    expect(
        provider.search('', const {}).any((entry) => entry.code == 'tickets'),
        isTrue);
    provider.inlineTicketsEnabled = false;
    expect(provider.entry('tickets'), isNull);
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
  for (final typed in [false, true]) {
    testWidgets(
        '${typed ? 'typed' : 'explicit'} chooser cancels on outside click without insertion',
        (tester) async {
      final provider = EmailAuthoringProvider(
          EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
          field: EmailTargetField.body);
      final controller = RichHtmlEditorController(
          initialHtml: '<p>Hello</p>',
          owner: const HtmlMediaOwner.none(),
          authoring: provider);
      var outsideClicks = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Column(children: [
        Expanded(child: RichHtmlEditor(controller: controller)),
        TextButton(
            onPressed: () => outsideClicks++, child: const Text('Outside')),
      ]))));
      if (typed) {
        final node = controller.editor.document.first as TextNode;
        controller.editor.execute([
          ChangeSelectionRequest(
              DocumentSelection.collapsed(
                  position: DocumentPosition(
                      nodeId: node.id,
                      nodePosition: const TextNodePosition(offset: 0))),
              SelectionChangeType.placeCaret,
              SelectionReason.userInteraction),
          InsertTextRequest(
              documentPosition: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 0)),
              textToInsert: '@',
              attributions: {}),
        ]);
        controller.focusNode.requestFocus();
      } else {
        await tester.tap(find.byTooltip(provider.insertLabel));
      }
      await tester.pump();
      await tester.pump();
      expect(find.byType(ListTile), findsWidgets);
      final html = controller.html;
      await tester.tap(find.text('Outside'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ListTile), findsNothing);
      expect(controller.composingTag, isNull);
      expect(controller.html, html);
      expect(controller.templateUsage, isEmpty);
      expect(outsideClicks, 1);
      // A later rebuild must not reopen a cancelled query.
      controller.focusNode.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(find.byType(ListTile), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
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
    await tester.tap(find.byIcon(Icons.alternate_email));
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
