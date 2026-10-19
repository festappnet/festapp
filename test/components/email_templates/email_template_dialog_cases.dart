import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/email_templates/email_templates_strings.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_templates/db_email_templates.dart';
import 'package:fstapp/components/email_templates/email_preview_examples.dart';
import 'package:fstapp/components/email_templates/email_preview_html.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/email_templates/views/email_templates_settings_page.dart';
import 'package:fstapp/components/html/rich_html_editor_dialog.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/html/html_strings.dart';
import 'package:super_editor/super_editor.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/widgets/app_dialog.dart';

Future<void> openTemplate(WidgetTester tester, {String? occasionTitle, String html = '<p>Content</p>', Future<EmailAuthoringContext> Function()? authoringContextLoader, Future<EmailPreviewExamples> Function()? previewExamplesLoader}) async {
  RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      unitUser: OccasionUserModel(isEditor: true),
      occasionUser: OccasionUserModel(isEditor: true));
  addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => EmailTemplateSettingsPage(
              authoringContextLoader: authoringContextLoader,
              previewExamplesLoader: previewExamplesLoader,
              template: EmailTemplateModel(
                code: occasionTitle == null
                    ? 'SIGN_IN_CODE'
                    : 'TICKET_ORDER_CONFIRMATION',
                subject: 'Subject',
                html: html,
              ),
              emailTemplatesResponse: EmailTemplatesResponse(
                unit: UnitModel(id: 1, title: 'Unit'),
                organization: UnitModel(id: 2, title: 'Organization'),
                occasion: occasionTitle == null
                    ? null
                    : OccasionModel(
                        id: 3,
                        title: occasionTitle,
                        isOpen: true,
                        isHidden: false,
                        isPromoted: false),
                templates: [],
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('automatic completion follows live draft and survives fullscreen without persistence',
      (tester) async {
    final metadata = Completer<EmailAuthoringContext>();
    await openTemplate(tester, occasionTitle: 'Festival',
        previewExamplesLoader: () async => EmailPreviewExamples.fromJson(jsonDecode(File('assets/email_templates/preview_examples.json').readAsStringSync())),
        authoringContextLoader: () => metadata.future);
    const footerKey = ValueKey('email-automatic-completion');
    expect(find.byKey(footerKey), findsNothing);
    final body = tester.widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor)).last.controller;
    metadata.complete(const EmailAuthoringContext(senderAddress: 'sender@test.invalid'));
    await tester.pumpAndSettle();
    expect(find.byKey(footerKey), findsOneWidget);
    final automatic = tester.widget<EmailPreviewHtml>(find.byKey(footerKey)).html;
    expect(automatic, contains('href='));
    expect(body.html, '<p>Content</p>');
    expect(body.hasUserChanges, isFalse);
    final node = body.editor.document.first;
    body.editor.execute([ChangeSelectionRequest(
        DocumentSelection.collapsed(position: DocumentPosition(
            nodeId: node.id, nodePosition: node.endPosition)),
        SelectionChangeType.placeCaret, SelectionReason.userInteraction)]);
    expect(body.insertTemplateToken('order_overview_button'), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(footerKey), findsNothing);
    expect(body.html, contains('{{order_overview_button}}'));
    body.undo();
    await tester.pumpAndSettle();
    expect(find.byKey(footerKey), findsOneWidget);
    expect(body.html, '<p>Content</p>');
    await tester.ensureVisible(find.byIcon(Icons.open_in_full));
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    expect(find.byKey(footerKey), findsOneWidget);
    expect(tester.widget<EmailPreviewHtml>(find.byKey(footerKey)).html, automatic);
    expect(body.html, '<p>Content</p>');
  });

  testWidgets('wrapper overview action suppresses automatic editor completion', (tester) async {
    final examples = EmailPreviewExamples.fromJson(jsonDecode(File('assets/email_templates/preview_examples.json').readAsStringSync()));
    final action = examples.scenariosFor('TICKET_ORDER_CONFIRMATION').first.requiredLinks.single.html;
    await openTemplate(tester, occasionTitle: 'Festival',
        previewExamplesLoader: () async => examples,
        authoringContextLoader: () async => EmailAuthoringContext(
            senderAddress: 'sender@test.invalid', wrapperHtml: '<body>{{content}}$action</body>'));
    expect(find.byKey(const ValueKey('email-automatic-completion')), findsNothing);
  });

  for (final inline in [false, true]) {
    testWidgets('card completion stays before signature, including legacy inline=$inline', (tester) async {
      final examples = EmailPreviewExamples.fromJson(jsonDecode(File('assets/email_templates/preview_examples.json').readAsStringSync()));
      final scenario = examples.scenariosFor('TICKET_ORDER_CONFIRMATION').first;
      final source = inline ? '<p>Intro {{fullOrder}}</p><p>Signature after card</p><p>{{fullOrder}}</p>'
          : '<p>{{fullOrder}}</p><p>Signature after card</p><p>{{fullOrder}}</p>';
      await openTemplate(tester, occasionTitle: 'Festival', html: source,
          previewExamplesLoader: () async => examples,
          authoringContextLoader: () async => const EmailAuthoringContext(senderAddress: 'sender@test.invalid',
              wrapperHtml: '<body><div style="padding:24px">{{content}}</div></body>'));
      final previews = tester.widgetList<EmailPreviewHtml>(find.byType(EmailPreviewHtml)).toList();
      expect(previews, hasLength(2));
      expect(previews.first.html, contains(scenario.requiredLinks.single.html));
      expect(previews.last.html, isNot(contains(scenario.requiredLinks.single.html)));
      expect(find.byKey(const ValueKey('email-automatic-completion')), findsNothing);
      final body = tester.widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor)).last.controller;
      expect(body.html, source);
      expect(body.hasUserChanges, isFalse);
      final node = body.editor.document.last;
      body.editor.execute([ChangeSelectionRequest(
          DocumentSelection.collapsed(position: DocumentPosition(nodeId: node.id, nodePosition: node.endPosition)),
          SelectionChangeType.placeCaret, SelectionReason.userInteraction)]);
      expect(body.insertTemplateToken('order_overview_button'), isTrue);
      await tester.pumpAndSettle();
      final rendered = tester.widgetList<EmailPreviewHtml>(find.byType(EmailPreviewHtml));
      expect(rendered.where((v) => v.html == scenario.values['order_overview_button']), hasLength(1));
      body.undo();
      await tester.pumpAndSettle();
      expect(tester.widgetList<EmailPreviewHtml>(find.byType(EmailPreviewHtml)).first.html,
          contains(scenario.requiredLinks.single.html));
      if (!inline) {
        body.editor.execute([DeleteNodeRequest(nodeId: body.editor.document.first.id)]);
        await tester.pumpAndSettle();
        expect(tester.widgetList<EmailPreviewHtml>(find.byType(EmailPreviewHtml)).single.html,
            contains(scenario.requiredLinks.single.html));
      }
    });
  }
  testWidgets('Escape closes mention menu before pristine parent', (tester) async {
    await openTemplate(tester);
    await tester.tap(find.byIcon(Icons.alternate_email).first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsNothing);
  });
  testWidgets('Escape from fullscreen returns inline without losing body draft', (tester) async {
    await openTemplate(tester);
    final body = tester.widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor)).last.controller;
    final node = body.editor.document.first;
    body.editor.execute([InsertTextRequest(
        documentPosition: DocumentPosition(nodeId: node.id, nodePosition: node.endPosition),
        textToInsert: ' Draft', attributions: {})]);
    await tester.ensureVisible(find.byIcon(Icons.open_in_full));
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    body.focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(RichHtmlEditorDialog), findsNothing);
    expect(find.byType(EmailTemplateSettingsPage), findsOneWidget);
    expect(body.plainText, 'Content Draft');
  });

  for (final editorIndex in [0, 1]) {
    for (final dirty in [false, true]) {
      testWidgets('Escape from focused editor $editorIndex preserves dirty=$dirty guard', (tester) async {
        await openTemplate(tester);
        final controller = tester.widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor)).elementAt(editorIndex).controller;
        final node = controller.editor.document.first;
        controller.editor.execute([ChangeSelectionRequest(
            DocumentSelection.collapsed(position: DocumentPosition(nodeId: node.id, nodePosition: node.endPosition)),
            SelectionChangeType.placeCaret, SelectionReason.userInteraction)]);
        controller.focusNode.requestFocus();
        if (dirty) controller.editor.execute([InsertTextRequest(
            documentPosition: DocumentPosition(nodeId: node.id, nodePosition: node.endPosition),
            textToInsert: ' Draft', attributions: {})]);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        if (dirty) {
          expect(find.text(HtmlStrings.discardDraft), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(EmailTemplateSettingsPage), findsOneWidget);
          expect(controller.plainText, contains('Draft'));
        } else {
          expect(find.byType(EmailTemplateSettingsPage), findsNothing);
        }
      });
    }
  }
  testWidgets('action gap stays outside scroll viewport at its bottom', (tester) async {
    tester.view.physicalSize = const Size(1000, 450);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openTemplate(tester, html: List.filled(15, '<p>Long email content</p>').join());
    final scroll = find.byType(ListView).first;
    final actions = find.byType(AppDialogActions);
    void expectGap() => expect(tester.getRect(actions).top - tester.getRect(scroll).bottom, greaterThanOrEqualTo(16));
    expectGap();
    await tester.drag(scroll, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expectGap();
  });

  testWidgets('subject-only edit is protected when closing parent',
      (tester) async {
    await openTemplate(tester);
    final editor = tester
        .widget<RichHtmlEditor>(find.byType(RichHtmlEditor).first)
        .controller;
    final node = editor.editor.document.first as TextNode;
    editor.editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: node.id, nodePosition: const TextNodePosition(offset: 0)),
          textToInsert: 'Draft ',
          attributions: {})
    ]);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text(HtmlStrings.discardDraft), findsOneWidget);
    expect(editor.plainText, 'Draft Subject');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsOneWidget);
    expect(editor.plainText, 'Draft Subject');
  });

  testWidgets(
      'title suggestion accepts once, undoes, and withdraws after leaving range',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openTemplate(tester, occasionTitle: 'Podzimní slavnost');
    final controller = tester
        .widget<RichHtmlEditor>(find.byType(RichHtmlEditor).first)
        .controller;
    final node = controller.editor.document.first as TextNode;
    controller.focusNode.requestFocus();
    await tester.pump();
    controller.editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: node.id,
              nodePosition: TextNodePosition(offset: node.text.length)),
          textToInsert: ' Podzimní slavnost',
          attributions: {})
    ]);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(find.text(EmailTemplatesStrings.replaceVariable), findsOneWidget);
    await tester
        .ensureVisible(find.text(EmailTemplatesStrings.replaceVariable));
    await tester.tap(find.text(EmailTemplatesStrings.replaceVariable));
    await tester.pump();
    expect(controller.plainText, 'Subject {{occasionTitle}}');
    controller.undo();
    expect(controller.plainText, 'Subject Podzimní slavnost');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    controller.editor.execute([
      ChangeSelectionRequest(
          DocumentSelection.collapsed(
              position: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: const TextNodePosition(offset: 0))),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction)
    ]);
    await tester.pump();
    expect(find.text(EmailTemplatesStrings.replaceVariable), findsNothing);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('email settings use the shared modal at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openTemplate(tester);
      expect(find.byType(AppAlertDialog), findsOneWidget);
      expect(find.byType(AppDialogHeader), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(EmailTemplateSettingsPage), findsNothing);
    });
  }

  testWidgets('one parent save owns subject and body across fullscreen',
      (tester) async {
    await openTemplate(tester);
    expect(find.text(CommonStrings.save), findsOneWidget);
    final editors =
        tester.widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor)).toList();
    final body = editors.last.controller;
    final node = body.editor.document.first as TextNode;
    body.editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: node.id, nodePosition: const TextNodePosition(offset: 0)),
          textToInsert: 'Draft ',
          attributions: {})
    ]);
    await tester.ensureVisible(find.byIcon(Icons.open_in_full));
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    expect(find.text(CommonStrings.save), findsNothing);
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.byType(RichHtmlEditorDialog), findsNothing);
    expect(body.plainText, 'Draft Content');
    expect(find.text(CommonStrings.save), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(HtmlStrings.discardDraft), findsOneWidget);
  });

  testWidgets('email HTML expands into the same editor as field descriptions',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openTemplate(tester);
    await tester.ensureVisible(find.byIcon(Icons.open_in_full));
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();
    expect(find.byType(RichHtmlEditorDialog), findsOneWidget);
    expect(find.byType(AppDialogAppBar), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(RichHtmlEditorDialog), findsNothing);
    expect(find.byType(EmailTemplateSettingsPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
