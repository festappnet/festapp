import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';

import 'dart:convert';

import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_email_preview.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'dart:io';
import 'dart:async';

import 'package:festapp_core/email_templates.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/email_templates/email_templates_strings.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';

import '../../support/fixtures/localization_log_fixture.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_templates/db_email_templates.dart';
import 'package:fstapp/components/email_templates/email_preview_examples.dart';
import 'package:fstapp/components/email_templates/email_preview_html.dart';
import 'package:fstapp/components/email_templates/email_template_model.dart';
import 'package:fstapp/components/email_templates/views/email_templates_settings_page.dart';
import 'package:fstapp/components/html/rich_html_editor_dialog.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/html/html_strings.dart';
import 'package:fstapp/components/html/template_authoring.dart';
import 'package:super_editor/super_editor.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/widgets/app_dialog.dart';

Future<void> openTemplate(
  WidgetTester tester, {
  String? occasionTitle,
  Future<void> Function(EmailTemplateModel)? saveTemplate,
  TicketFeature? ticketFeature,
  String? code,
  String html = '<p>Content</p>',
  Future<EmailAuthoringContext> Function()? authoringContextLoader,
  Future<EmailPreviewExamples> Function()? previewExamplesLoader,
}) async {
  RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
    capabilities: {
      AuthorizationCapabilities.emailTemplatesOccasionWrite: true,
      AuthorizationCapabilities.emailTemplatesUnitWrite: true,
    },
    unitUser: OccasionUserModel(isEditor: true),
    occasionUser: OccasionUserModel(isEditor: true),
  );
  addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
  await tester.pumpWidget(
    MaterialApp(
      builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EmailTemplateSettingsPage(
                saveTemplate: saveTemplate,
                authoringContextLoader: authoringContextLoader,
                previewExamplesLoader: previewExamplesLoader,
                template: EmailTemplateModel(
                  code:
                      code ??
                      (occasionTitle == null
                          ? 'SIGN_IN_CODE'
                          : 'TICKET_ORDER_CONFIRMATION'),
                  revision: 'a' * 64,
                  subject: 'Subject',
                  html: html,
                ),
                emailTemplatesResponse: EmailTemplatesResponse(
                  unit: UnitModel(id: 1, title: 'Unit'),
                  organization: UnitModel(id: 2, title: 'Organization'),
                  occasion: occasionTitle == null
                      ? null
                      : OccasionModel(
                          features: [if (ticketFeature != null) ticketFeature],
                          id: 3,
                          title: occasionTitle,
                          isOpen: true,
                          isHidden: false,
                          isPromoted: false,
                        ),
                  templates: [],
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('waitlist offer dialog renders inherited wording as atomic blocks',
      (tester) async {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final examples = EmailPreviewExamples.fromJson(jsonDecode(
        File('assets/email_templates/preview_examples.json').readAsStringSync()));
    final pendingExamples = Completer<EmailPreviewExamples>();
    const html = '<h2>{{waitlist_offer_heading}}</h2>'
        '<p>Pro přihlášku <strong>{{orderSymbol}}</strong> na '
        '{{occasionTitle}} nabízíme {{offered_places}}. Nabídka platí do '
        '{{offer_expires_at}}.</p><p>{{waitlist_offer_instructions}}</p>'
        '<p>{{offer_button}}</p>';
    await openTemplate(tester,
        code: 'waitlist_offer',
        occasionTitle: 'Adventní duchovní obnova',
        html: html,
        previewExamplesLoader: () => pendingExamples.future,
        authoringContextLoader: () async =>
            const EmailAuthoringContext(senderAddress: 'info@example.invalid'));
    final body = tester
        .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
        .last.controller;
    expect(body.editor.document.whereType<TemplateTokenBlock>(), hasLength(3));
    pendingExamples.complete(examples);
    await tester.pumpAndSettle();
    final scenario = examples.scenariosFor('waitlist_offer').first;
    for (final code in ['waitlist_offer_heading', 'waitlist_offer_instructions']) {
      expect(find.text(scenario.values[code]!, findRichText: true), findsOneWidget);
      expect(find.text('{{$code}}', findRichText: true), findsNothing);
    }
    expect(body.hasUnsupportedTokens, isFalse);
    expect(body.hasUserChanges, isFalse);
    expect(body.html, html);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('default waitlist preview follows the informal single application context', (tester) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final examples = EmailPreviewExamples.fromJson(
      jsonDecode(File('assets/email_templates/preview_examples.json').readAsStringSync()),
      context: const EmailPreviewContext(
        occasionTitle: 'Duchovní obnova', communicationTone: 'informal',
        ticketsEnabled: false, blueprintEnabled: false),
    );
    await openTemplate(tester, code: 'waitlist_offer', occasionTitle: 'Duchovní obnova',
      html: '<h2>{{waitlist_offer_heading}}</h2><p>{{offered_places}}</p><p>{{waitlist_offer_instructions}}</p>{{offer_button}}',
      previewExamplesLoader: () async => examples,
      authoringContextLoader: () async => const EmailAuthoringContext(senderAddress: 'poradatel@example.invalid'),
    );
    expect(find.text(EmailTemplatesStrings.toneName('informal')), findsOneWidget);
    await tester.ensureVisible(find.byIcon(Icons.preview_outlined).first);
    await tester.tap(find.byIcon(Icons.preview_outlined).first);
    await tester.pumpAndSettle();
    final received = examples.scenariosFor('waitlist_offer').firstWhere((s) => s.tone == 'informal');
    expect(find.byWidgetPredicate((w) => w is EmailPreviewHtml &&
      w.html.contains(received.values['waitlist_offer_heading']!) &&
      w.html.contains(received.values['offered_places']!) &&
      w.html.contains(received.values['waitlist_offer_instructions']!)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final code in [
    'waitlist_confirmation',
    'waitlist_offer',
    'TICKET_ORDER_CONFIRMATION',
    'TICKET_ORDER_UPDATE',
    'TICKET_ORDER_PAYMENT_DONE',
    'TICKET_ORDER_REMINDER',
    'TICKET_ORDER_STORNO',
  ]) {
    testWidgets('$code switches tone in the received preview and editor', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sql = File(
        code.startsWith('TICKET_')
            ? 'database/seeds/order_symbol_email_defaults.sql'
            : 'database/functions/eshop_waitlist/email_templates.sql',
      ).readAsStringSync();
      final html = RegExp("'$code','[^']*',\\s*'([^']*)'")
          .firstMatch(sql)!
          .group(1)!;
      final examples = EmailPreviewExamples.fromJson(
        jsonDecode(
          File('assets/email_templates/preview_examples.json')
              .readAsStringSync(),
        ),
      );
      await openTemplate(
        tester,
        code: code,
        occasionTitle: 'Podzimní slavnost',
        html: html,
        previewExamplesLoader: () async => examples,
        authoringContextLoader: () async => const EmailAuthoringContext(
          senderAddress: 'poradatel@example.invalid',
          wrapperHtml: '<main>{{content}}</main>',
        ),
      );
      final editor = tester
          .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
          .last
          .controller;
      final original = editor.html;
      final heading = code.startsWith('TICKET_')
          ? 'orderCommunication'
          : '${code}_heading';
      final scenarios = examples.scenariosFor(code);
      final formal = scenarios.firstWhere((s) => s.tone == 'formal');
      final informal = scenarios.firstWhere((s) => s.tone == 'informal');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is EmailPreviewHtml && w.html.contains(formal.values[heading]!),
        ),
        findsOneWidget,
      );
      expect(
        find.text(EmailTemplatesStrings.toneName('formal')),
        findsOneWidget,
      );
      expect(find.text('{{$heading}}', findRichText: true), findsNothing);
      await tester.ensureVisible(find.byIcon(Icons.preview_outlined).first);
      await tester.tap(find.byIcon(Icons.preview_outlined).first);
      await tester.pumpAndSettle();
      final selector = find.byWidgetPredicate(
        (w) => w is DropdownButtonFormField<EmailPreviewScenario>,
      );
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(
              '${EmailTemplatesStrings.scenarioName(informal.scenario)} · ${informal.locale == 'cs' ? 'Čeština' : 'English'} · ${EmailTemplatesStrings.toneName(informal.tone)}',
            )
            .last,
      );
      await tester.pumpAndSettle();
      final received = tester.widget<EmailReceivedMessage>(
        find.byType(EmailReceivedMessage),
      );
      expect(received.html, contains(informal.values[heading]));
      expect(received.html, isNot(contains(formal.values[heading])));
      expect(received.html, isNot(contains('{{')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is EmailPreviewHtml &&
              w.html.contains(informal.values[heading]!),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is EmailPreviewHtml && w.html.contains(formal.values[heading]!),
        ),
        findsNothing,
      );
      expect(
        find.text(EmailTemplatesStrings.toneName('informal')),
        findsOneWidget,
      );
      expect(editor.html, original);
      expect(editor.hasUserChanges, isFalse);
    });
  }
  for (final mode in TicketDeliveryMode.values) {
    testWidgets('paid template previews delivery mode ${mode.value}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openTemplate(
        tester,
        code: 'TICKET_ORDER_PAYMENT_DONE',
        occasionTitle: 'Festival',
        ticketFeature: TicketFeature(
          code: 'ticket',
          isEnabled: true,
          deliveryMode: mode,
        ),
        html: '<p>Payment received</p>{{tickets}}',
        previewExamplesLoader: () async => EmailPreviewExamples.fromJson(
          jsonDecode(
            File('assets/email_templates/preview_examples.json')
                .readAsStringSync(),
          ),
        ),
        authoringContextLoader: () async =>
            const EmailAuthoringContext(senderAddress: 'sender@test.invalid'),
      );
      final body = tester
          .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
          .last
          .controller;
      final provider = body.authoring!;
      expect(
        provider.search('', const {}).any((entry) => entry.code == 'tickets'),
        mode != TicketDeliveryMode.pdfAttachment,
      );
      await tester.ensureVisible(find.byIcon(Icons.preview_outlined).first);
      await tester.tap(find.byIcon(Icons.preview_outlined).first);
      await tester.pumpAndSettle();
      expect(find.byType(TicketEmailPreview), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TicketEmailPreview),
          matching: find.byType(QrImageView),
        ),
        mode == TicketDeliveryMode.pdfAttachment
            ? findsNothing
            : findsOneWidget,
      );
      expect(
        find.text('ticket_UKAZKA-1.pdf'),
        mode.includesPdf ? findsOneWidget : findsNothing,
      );
      expect(
        tester
            .widget<EmailReceivedMessage>(find.byType(EmailReceivedMessage))
            .senderAddress,
        'sender@test.invalid',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  for (final metadataFirst in [true, false]) {
    testWidgets(
      'bank metadata updates authoring examples independent of load order $metadataFirst',
      (tester) async {
        final metadata = Completer<EmailAuthoringContext>();
        final examples = Completer<EmailPreviewExamples>();
        const account = EmailPreviewPaymentAccount(
          accountNumber: '123456789/2010',
          iban: 'CZ65 2010 0000 0012 3456 7890',
          currencies: ['CZK'],
        );
        await openTemplate(
          tester,
          occasionTitle: 'Festival',
          html: '<p>{{accountNumber}} - {{iban}}</p>{{balanceReasoning}}',
          previewExamplesLoader: () => examples.future,
          authoringContextLoader: () => metadata.future,
        );
        void completeMetadata() => metadata.complete(
          const EmailAuthoringContext(
            senderAddress: 'sender@test.invalid',
            paymentAccounts: [account],
          ),
        );
        void completeExamples() => examples.complete(
          EmailPreviewExamples.fromJson(
            jsonDecode(
              File('assets/email_templates/preview_examples.json')
                  .readAsStringSync(),
            ),
          ),
        );
        if (metadataFirst) {
          completeMetadata();
        } else {
          completeExamples();
        }
        await tester.pumpAndSettle();
        if (metadataFirst) {
          completeExamples();
        } else {
          completeMetadata();
        }
        await tester.pumpAndSettle();
        expect(find.text(account.accountNumber), findsOneWidget);
        expect(find.text(account.iban), findsOneWidget);
        expect(
          tester.widget<EmailPreviewHtml>(find.byType(EmailPreviewHtml)).html,
          contains(account.iban),
        );
        final body = tester
            .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
            .last
            .controller;
        expect(
          body.html,
          '<p>{{accountNumber}} - {{iban}}</p>{{balanceReasoning}}',
        );
        expect(body.hasUserChanges, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final code in ['TICKET_ORDER_CONFIRMATION', 'TICKET_ORDER_STORNO']) {
    testWidgets('custom $code body omits overview until author inserts it', (
      tester,
    ) async {
      final metadata = Completer<EmailAuthoringContext>();
      await openTemplate(
        tester,
        code: code,
        occasionTitle: 'Festival',
        previewExamplesLoader: () async => EmailPreviewExamples.fromJson(
          jsonDecode(
            File('assets/email_templates/preview_examples.json')
                .readAsStringSync(),
          ),
        ),
        authoringContextLoader: () => metadata.future,
      );
      final body = tester
          .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
          .last
          .controller;
      metadata.complete(
        const EmailAuthoringContext(senderAddress: 'sender@test.invalid'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmailPreviewHtml), findsNothing);
      expect(body.html, '<p>Content</p>');
      expect(body.hasUserChanges, isFalse);
      void insert(String code) {
        final node = body.editor.document.first;
        body.editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: node.id,
                nodePosition: node.endPosition,
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);
        expect(body.insertTemplateToken(code), isTrue);
      }

      insert('order_overview_button');
      await tester.pumpAndSettle();
      expect(
        tester.widget<EmailPreviewHtml>(find.byType(EmailPreviewHtml)).html,
        contains('href='),
      );
      body.undo();
      await tester.pumpAndSettle();
      expect(find.byType(EmailPreviewHtml), findsNothing);
      expect(body.html, '<p>Content</p>');
      await tester.ensureVisible(find.byIcon(Icons.open_in_full));
      await tester.tap(find.byIcon(Icons.open_in_full));
      await tester.pumpAndSettle();
      expect(find.byType(EmailPreviewHtml), findsNothing);
      expect(body.html, '<p>Content</p>');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      if (code == 'TICKET_ORDER_CONFIRMATION') {
        insert('fullOrder');
        await tester.pumpAndSettle();
        expect(
          tester.widget<EmailPreviewHtml>(find.byType(EmailPreviewHtml)).html,
          contains('href='),
        );
        body.undo();
        await tester.pumpAndSettle();
        expect(find.byType(EmailPreviewHtml), findsNothing);
        expect(body.html, '<p>Content</p>');
      }
    });
  }

  testWidgets(
    'wrapper overview action suppresses automatic editor completion',
    (tester) async {
      final examples = EmailPreviewExamples.fromJson(
        jsonDecode(
          File('assets/email_templates/preview_examples.json')
              .readAsStringSync(),
        ),
      );
      final action = examples
          .scenariosFor('TICKET_ORDER_CONFIRMATION')
          .first
          .requiredLinks
          .single
          .html;
      await openTemplate(
        tester,
        occasionTitle: 'Festival',
        previewExamplesLoader: () async => examples,
        authoringContextLoader: () async => EmailAuthoringContext(
          senderAddress: 'sender@test.invalid',
          wrapperHtml: '<body>{{content}}$action</body>',
        ),
      );
      expect(
        find.byKey(const ValueKey('email-automatic-completion')),
        findsNothing,
      );
    },
  );

  for (final inline in [false, true]) {
    testWidgets(
      'card completion stays before signature, including legacy inline=$inline',
      (tester) async {
        final examples = EmailPreviewExamples.fromJson(
          jsonDecode(
            File('assets/email_templates/preview_examples.json')
                .readAsStringSync(),
          ),
        );
        final scenario = examples
            .scenariosFor('TICKET_ORDER_CONFIRMATION')
            .first;
        final source = inline
            ? '<p>Intro {{fullOrder}}</p><p>Signature after card</p><p>{{fullOrder}}</p>'
            : '<p>{{fullOrder}}</p><p>Signature after card</p><p>{{fullOrder}}</p>';
        await openTemplate(
          tester,
          occasionTitle: 'Festival',
          html: source,
          previewExamplesLoader: () async => examples,
          authoringContextLoader: () async => const EmailAuthoringContext(
            senderAddress: 'sender@test.invalid',
            wrapperHtml:
                '<body><div style="padding:24px">{{content}}</div></body>',
          ),
        );
        final previews = tester
            .widgetList<EmailPreviewHtml>(find.byType(EmailPreviewHtml))
            .toList();
        expect(previews, hasLength(2));
        expect(
          previews.first.html,
          contains(scenario.requiredLinks.single.html),
        );
        expect(
          previews.last.html,
          isNot(contains(scenario.requiredLinks.single.html)),
        );
        expect(
          find.byKey(const ValueKey('email-automatic-completion')),
          findsNothing,
        );
        final body = tester
            .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
            .last
            .controller;
        expect(body.html, source);
        expect(body.hasUserChanges, isFalse);
        final node = body.editor.document.last;
        body.editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: node.id,
                nodePosition: node.endPosition,
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);
        expect(body.insertTemplateToken('order_overview_button'), isTrue);
        await tester.pumpAndSettle();
        final rendered = tester.widgetList<EmailPreviewHtml>(
          find.byType(EmailPreviewHtml),
        );
        expect(
          rendered.where(
            (v) => v.html == scenario.values['order_overview_button'],
          ),
          hasLength(1),
        );
        body.undo();
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<EmailPreviewHtml>(find.byType(EmailPreviewHtml))
              .first
              .html,
          contains(scenario.requiredLinks.single.html),
        );
        if (!inline) {
          body.editor.execute([
            DeleteNodeRequest(nodeId: body.editor.document.first.id),
          ]);
          await tester.pumpAndSettle();
          expect(
            tester
                .widgetList<EmailPreviewHtml>(find.byType(EmailPreviewHtml))
                .single
                .html,
            contains(scenario.requiredLinks.single.html),
          );
        }
      },
    );
  }
  testWidgets('body toolbar chooser is usable in a long template dialog', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await openTemplate(tester, occasionTitle: 'Ples',
        html: '<p>{{orderCommunication}}</p><p>{{balanceReasoning}}</p>'
            '<p>{{fullOrder}}</p><p>Signature</p>');
    final bodyController = tester.widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor)).last.controller;
    final textNode = bodyController.editor.document.whereType<TextNode>().last;
    bodyController.editor.execute([
      ChangeSelectionRequest(DocumentSelection(
          base: DocumentPosition(nodeId: textNode.id, nodePosition: const TextNodePosition(offset: 0)),
          extent: DocumentPosition(nodeId: textNode.id, nodePosition: const TextNodePosition(offset: 5))),
          SelectionChangeType.expandSelection, SelectionReason.userInteraction),
    ]);
    final button = find.byIcon(Icons.alternate_email).last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'amount');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final body = tester.widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor)).last.controller;
    expect(body.html, contains('{{amount}}'));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('Escape closes mention menu before pristine parent', (
    tester,
  ) async {
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
  testWidgets(
    'Escape from fullscreen returns inline without losing body draft',
    (tester) async {
      await openTemplate(tester);
      final body = tester
          .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
          .last
          .controller;
      final node = body.editor.document.first;
      body.editor.execute([
        InsertTextRequest(
          documentPosition: DocumentPosition(
            nodeId: node.id,
            nodePosition: node.endPosition,
          ),
          textToInsert: ' Draft',
          attributions: {},
        ),
      ]);
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
    },
  );

  for (final editorIndex in [0, 1]) {
    for (final dirty in [false, true]) {
      testWidgets(
        'Escape from focused editor $editorIndex preserves dirty=$dirty guard',
        (tester) async {
          await openTemplate(tester);
          final controller = tester
              .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
              .elementAt(editorIndex)
              .controller;
          final node = controller.editor.document.first;
          controller.editor.execute([
            ChangeSelectionRequest(
              DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: node.endPosition,
                ),
              ),
              SelectionChangeType.placeCaret,
              SelectionReason.userInteraction,
            ),
          ]);
          controller.focusNode.requestFocus();
          if (dirty)
            controller.editor.execute([
              InsertTextRequest(
                documentPosition: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: node.endPosition,
                ),
                textToInsert: ' Draft',
                attributions: {},
              ),
            ]);
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
        },
      );
    }
  }
  for (final width in [1000.0, 375.0]) {
    for (final source in [
      '{{fullOrder}}\n<p>Přejeme pěkný den</p>',
      '<p>Ahoj,</p>\n{{balanceReasoning}}{{fullOrder}}\n'
          '<p>Přejeme pěkný den</p>\n<p>Organizační tým {{occasionTitle}}</p>',
    ]) {
      testWidgets(
        'bare rich blocks have no phantom line before signature $width ${source.length}',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await openTemplate(
            tester,
            code: 'TICKET_ORDER_REMINDER',
            html: source,
            occasionTitle: 'Sample event',
            previewExamplesLoader: () async => EmailPreviewExamples.fromJson(
              jsonDecode(
                File('assets/email_templates/preview_examples.json')
                    .readAsStringSync(),
              ),
            ),
            authoringContextLoader: () async => const EmailAuthoringContext(
              senderAddress: 'info@example.invalid',
            ),
          );
          final controller = tester
              .widget<RichHtmlEditor>(find.byType(RichHtmlEditor).last)
              .controller;
          expect(controller.html, source);
          expect(controller.hasUserChanges, isFalse);
          Future<void> expectSignatureGap(String signature) async {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, -10000),
            );
            await tester.pumpAndSettle();
            final signoff = tester.getRect(
              find.text(signature, findRichText: true),
            );
            final blocks =
                find
                    .byType(EmailPreviewHtml)
                    .evaluate()
                    .map(
                      (element) =>
                          tester.getRect(find.byWidget(element.widget)),
                    )
                    .where((rect) => rect.top < signoff.top)
                    .toList()
                  ..sort((a, b) => a.bottom.compareTo(b.bottom));
            expect(signoff.top - blocks.last.bottom, inInclusiveRange(0, 80));
          }

          await expectSignatureGap('Přejeme pěkný den');
          final signature = controller.editor.document
              .whereType<TextNode>()
              .firstWhere(
                (node) => node.text.toPlainText() == 'Přejeme pěkný den',
              );
          controller.editor.execute([
            InsertTextRequest(
              documentPosition: DocumentPosition(
                nodeId: signature.id,
                nodePosition: const TextNodePosition(offset: 0),
              ),
              textToInsert: 'Test ',
              attributions: {},
            ),
          ]);
          await tester.pumpAndSettle();
          await expectSignatureGap('Test Přejeme pěkný den');
          expect(
            controller.html,
            source.replaceFirst('Přejeme pěkný den', 'Test Přejeme pěkný den'),
          );
        },
      );
    }
  }

  testWidgets('action gap stays outside scroll viewport at its bottom', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 450);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openTemplate(
      tester,
      html: List.filled(15, '<p>Long email content</p>').join(),
    );
    final scroll = find.byType(ListView).first;
    final actions = find.byType(AppDialogActions);
    void expectGap() => expect(
      tester.getRect(actions).top - tester.getRect(scroll).bottom,
      equals(8),
    );
    expectGap();
    await tester.drag(scroll, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expectGap();
  });

  testWidgets('subject-only edit is protected when closing parent', (
    tester,
  ) async {
    await openTemplate(tester);
    final editor = tester
        .widget<RichHtmlEditor>(find.byType(RichHtmlEditor).first)
        .controller;
    final node = editor.editor.document.first as TextNode;
    editor.editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: node.id,
          nodePosition: const TextNodePosition(offset: 0),
        ),
        textToInsert: 'Draft ',
        attributions: {},
      ),
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
            nodePosition: TextNodePosition(offset: node.text.length),
          ),
          textToInsert: ' Podzimní slavnost',
          attributions: {},
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(find.text(EmailTemplatesStrings.replaceVariable), findsOneWidget);
      await tester.ensureVisible(
        find.text(EmailTemplatesStrings.replaceVariable),
      );
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
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      await tester.pump();
      expect(find.text(EmailTemplatesStrings.replaceVariable), findsNothing);
    },
  );

  for (final width in [320.0, 1200.0]) {
    testWidgets('email settings use the shared modal at width $width', (
      tester,
    ) async {
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

  testWidgets('one parent save owns subject and body across fullscreen', (
    tester,
  ) async {
    await openTemplate(tester);
    expect(find.text(CommonStrings.save), findsOneWidget);
    final editors = tester
        .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
        .toList();
    final body = editors.last.controller;
    final node = body.editor.document.first as TextNode;
    body.editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: node.id,
          nodePosition: const TextNodePosition(offset: 0),
        ),
        textToInsert: 'Draft ',
        attributions: {},
      ),
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

  testWidgets('email HTML expands into the same editor as field descriptions', (
    tester,
  ) async {
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
