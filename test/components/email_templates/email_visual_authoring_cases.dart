import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:festapp_core/email_templates.dart';
import 'package:fstapp/components/email_templates/email_authoring_provider.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/email_templates/email_preview_examples.dart';
import 'package:fstapp/components/email_templates/email_preview_html.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  final examples = EmailPreviewExamples.fromJson(jsonDecode(
      File('assets/email_templates/preview_examples.json').readAsStringSync()));
  final scenario = examples.scenariosFor('TICKET_ORDER_CONFIRMATION').first;
  testWidgets('subject displays actual sample value in a compact atomic field',
      (tester) async {
    final controller = RichHtmlEditorController(
        initialHtml: '<p>{{occasionTitle}}</p>',
        owner: const HtmlMediaOwner.none(),
        authoring: EmailAuthoringProvider(
            EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
            field: EmailTargetField.subject,
            scenario: scenario));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: RichHtmlEditor(controller: controller)))));
    expect(find.text(scenario.values['occasionTitle']!), findsOneWidget);
    expect(tester.getSize(find.byType(RichHtmlEditor)).height,
        lessThanOrEqualTo(96));
    expect(controller.plainText, '{{occasionTitle}}');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
      'rich token in existing paragraph displays actual component content',
      (tester) async {
    const source = '<p>Objednávka: {{fullOrder}}</p>';
    final controller = RichHtmlEditorController(
        initialHtml: source,
        owner: const HtmlMediaOwner.none(),
        authoring: EmailAuthoringProvider(
            EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
            field: EmailTargetField.body,
            scenario: scenario));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: RichHtmlEditor(controller: controller)))));
    await tester.pumpAndSettle();
    expect(find.byType(EmailPreviewHtml), findsOneWidget);
    expect(controller.html, source);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
      'choosing rich data inserts visible content and one undo restores query',
      (tester) async {
    final provider = EmailAuthoringProvider(
        EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
        field: EmailTargetField.body,
        scenario: scenario);
    final controller = RichHtmlEditorController(
        initialHtml: '<p></p>',
        owner: const HtmlMediaOwner.none(),
        authoring: provider);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: RichHtmlEditor(controller: controller)))));
    final node = controller.editor.document.first as TextNode;
    controller.focusNode.requestFocus();
    controller.editor.execute([
      ChangeSelectionRequest(
          DocumentSelection.collapsed(
              position: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 0))),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction)
    ]);
    for (final char in '@fullOrder'.split('')) {
      controller.editor.execute([
        InsertTextRequest(
            documentPosition: controller.editor.composer.selection!.extent,
            textToInsert: char,
            attributions: {})
      ]);
    }
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(ListTile, provider.entry('fullOrder')!.label));
    await tester.pumpAndSettle();
    expect(find.byType(EmailPreviewHtml), findsOneWidget);
    expect(
        find.textContaining('Dospělý vstup', findRichText: true), findsWidgets);
    expect(
        find.textContaining('Jana Nováková', findRichText: true), findsWidgets);
    expect(controller.html, contains('{{fullOrder}}'));
    expect(controller.html, isNot(contains('Dospělý vstup')));
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.plainText, '@fullOrder');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
      'explicit chooser after selecting rich block retains a usable text caret',
      (tester) async {
    final provider = EmailAuthoringProvider(
        EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
        field: EmailTargetField.body,
        scenario: scenario);
    final controller = RichHtmlEditorController(
        initialHtml: '<p>Intro {{fullOrder}}</p><p>{{balanceReasoning}}</p>',
        owner: const HtmlMediaOwner.none(),
        authoring: provider);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RichHtmlEditor(controller: controller, fullscreen: true))));
    final block = controller.editor.document.last;
    controller.editor.execute([
      ChangeSelectionRequest(
          DocumentSelection.collapsed(
              position: DocumentPosition(
                  nodeId: block.id, nodePosition: block.endPosition)),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction)
    ]);
    await tester.tap(find.byIcon(Icons.alternate_email));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'amount');
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(ListTile, provider.entry('amount')!.label));
    await tester.pumpAndSettle();
    expect(controller.html, contains('{{amount}}'));
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  for (final code in ['amount', 'order_overview_button']) {
    testWidgets(
        'all-rich loaded body inserts $code without mutating on chooser open',
        (tester) async {
      const source = '<p>{{fullOrder}}</p><p>{{balanceReasoning}}</p>';
      final provider = EmailAuthoringProvider(
          EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
          field: EmailTargetField.body,
          scenario: scenario);
      final controller = RichHtmlEditorController(
          initialHtml: source,
          owner: const HtmlMediaOwner.none(),
          authoring: provider);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: RichHtmlEditor(controller: controller, fullscreen: true))));
      expect(controller.editor.document.whereType<TextNode>(), isEmpty);
      await tester.tap(find.byIcon(Icons.alternate_email));
      await tester.pumpAndSettle();
      expect(controller.html, source);
      expect(controller.hasUserChanges, isFalse);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), code);
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(ListTile, provider.entry(code)!.label));
      await tester.pumpAndSettle();
      expect(controller.html, contains('{{$code}}'));
      expect(controller.html, isNot(contains('<p></p>')));
      expect(controller.html, isNot(contains('\uFFFC')));
      expect(find.byType(TextField), findsNothing);
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.html, source);
      expect(controller.hasUserChanges, isFalse);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
  testWidgets('preview surface follows dark app theme', (tester) async {
    final theme = ThemeData.dark();
    await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(
            body: EmailPreviewHtml(html: '<p>Jana Nováková</p>'))));
    final canvas = tester.widget<ColoredBox>(find
        .descendant(
            of: find.byType(EmailPreviewHtml),
            matching: find.byType(ColoredBox))
        .first);
    expect(canvas.color, theme.colorScheme.surface);
  });
}
