import 'dart:convert';
import 'dart:io';
import 'package:fstapp/components/images/recovering_image.dart';
import 'package:fstapp/components/images/image_url_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
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
  testWidgets('only the active editor owns a caret while both selections survive', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    List<CaretDocumentOverlay> visibleCarets() => tester.widgetList<CaretDocumentOverlay>(
        find.byType(CaretDocumentOverlay)).where((caret) => caret.caretStyle.color.a > 0).toList();
    final subject = RichHtmlEditorController(initialHtml: '<p>Subject</p>',
      owner: const HtmlMediaOwner.none(), authoring: EmailAuthoringProvider(
        EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'), field: EmailTargetField.subject));
    final body = RichHtmlEditorController(initialHtml: '<p>Body</p>', owner: const HtmlMediaOwner.none());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      RichHtmlEditor(controller: subject), RichHtmlEditor(controller: body),
    ]))));
    await tester.tap(find.text('Subject', findRichText: true));
    await tester.pumpAndSettle();
    final subjectSelection = subject.editor.composer.selection;
    expect(subjectSelection, isNotNull);
    expect(visibleCarets().single.composer, subject.editor.composer);
    await tester.tap(find.text('Body', findRichText: true));
    await tester.pumpAndSettle();
    final bodySelection = body.editor.composer.selection;
    expect(subject.focusNode.hasFocus, isFalse);
    expect(body.focusNode.hasFocus, isTrue);
    expect(subject.editor.composer.selection, subjectSelection);
    expect(visibleCarets().single.composer, body.editor.composer);
    subject.focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(body.editor.composer.selection, bodySelection);
    expect(visibleCarets().single.composer, subject.editor.composer);
    subject.focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(visibleCarets(), isEmpty);
    expect(subject.html, '<p>Subject</p>');
    expect(body.html, '<p>Body</p>');
    await tester.pumpWidget(const SizedBox());
    subject.dispose(); body.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('only approved wrapper banner uses canonical image delivery', (tester) async {
    const banner = 'https://img.festapp.net/images/preview-banner.png';
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: EmailReceivedMessage(
      subject: 'Subject', senderAddress: 'info@festapp.net',
      html: '<img src="$banner" alt="Banner"><img src="https://tracker.invalid/pixel.png"><img src="cid:qr">',
      allowedRemoteImageSources: {banner},
    ))));
    final image = tester.widget<RecoveringImage>(find.byType(RecoveringImage));
    expect((image.image as NetworkImage).url,
        ImageUrlHelper.transformImageUrl(banner, width: ImageUrlHelper.mediumWidth));
    expect(find.byIcon(Icons.image_outlined), findsNWidgets(2));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: EmailPreviewHtml(html: '<p>No banner</p>'))));
    expect(find.byType(RecoveringImage), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
  });
  testWidgets('fidelity email font does not inherit app typography',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: 'Futura'),
        home: const Scaffold(
            body: EmailPreviewHtml(html: '<p>Message text</p>'))));
    await tester.pumpAndSettle();
    final style = tester.widget<HtmlWidget>(find.byType(HtmlWidget)).textStyle!;
    expect(style.fontFamily, 'sans-serif');
    expect(style.fontSize, 16);
    expect(style.inherit, isFalse);
    expect(
        EmailAuthoringProvider(
                EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
                field: EmailTargetField.body)
            .textStyle
            .fontFamily,
        'sans-serif');
  });
  testWidgets('fidelity preserves fragment edge margins', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Align(alignment: Alignment.topLeft,
      child: EmailPreviewHtml(html: '<div style="margin:20px 0"><p style="margin:0">Canonical card</p></div>')))));
    await tester.pumpAndSettle();
    final preview = tester.getRect(find.byType(EmailPreviewHtml));
    final text = tester.getRect(find.text('Canonical card', findRichText: true));
    expect(text.top - preview.top, closeTo(20, 1));
    expect(preview.bottom - text.bottom, closeTo(20, 1));
  });
  testWidgets('fidelity preserves canonical empty spacer heights',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: EmailPreviewHtml(
                html:
                    '<p style="margin:0">First sentence</p><div style="height:40px"></div><p style="margin:0">Second sentence</p>'))));
    await tester.pumpAndSettle();
    final first =
        tester.getRect(find.text('First sentence', findRichText: true));
    final second =
        tester.getRect(find.text('Second sentence', findRichText: true));
    expect(second.top - first.bottom, closeTo(40, 1));
  });
  for (final brightness in Brightness.values) {
    testWidgets('fidelity component chrome is transient without content movement $brightness',
        (tester) async {
      final controller = RichHtmlEditorController(
          initialHtml: '<p>{{fullOrder}}</p>',
          owner: const HtmlMediaOwner.none(),
          authoring: EmailAuthoringProvider(
              EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
              field: EmailTargetField.body,
              scenario: scenario));
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: RichHtmlEditor(controller: controller)))));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.info_outline), findsNothing);
      final before = tester.getRect(find.byType(EmailPreviewHtml));
      final primary = Theme.of(tester.element(find.byType(RichHtmlEditor))).colorScheme.primary;
      Finder outline(Color color, double width) => find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox || widget.decoration is! BoxDecoration) return false;
        final border = (widget.decoration as BoxDecoration).border;
        return border is Border && border.top.color == color && border.top.width == width;
      });
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(before.topLeft + const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(tester.getRect(find.byType(EmailPreviewHtml)), before);
      expect(outline(primary.withValues(alpha: .7), 1.5), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(controller.focusNode.hasFocus, isFalse);
      await tester.tapAt(before.topLeft + const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(tester.getRect(find.byType(EmailPreviewHtml)), before);
      expect(outline(primary, 2), findsOneWidget);
      expect(outline(primary.withValues(alpha: .7), 1.5), findsNothing);
      expect(controller.html, '<p>{{fullOrder}}</p>');
      final node = controller.editor.document.first;
      expect(controller.editor.composer.selection, DocumentSelection(
        base: DocumentPosition(nodeId: node.id, nodePosition: node.beginningPosition),
        extent: DocumentPosition(nodeId: node.id, nodePosition: node.endPosition),
      ));
      expect(controller.focusNode.hasFocus, isTrue);
      expect(controller.hasUserChanges, isFalse);
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.html, '<p>{{fullOrder}}</p>');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
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
        lessThanOrEqualTo(52));
    expect(tester.getTopLeft(find.text('@')).dx,
        lessThanOrEqualTo(16));
    expect(controller.plainText, '{{occasionTitle}}');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  for (final field in [EmailTargetField.subject, EmailTargetField.body]) {
    testWidgets('variable indicator shares baseline and preserves $field chip semantics', (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const title = 'Podzimní slavnost a společné setkání všech přátel';
      final provider = EmailAuthoringProvider(
          EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'), field: field,
          scenario: scenario.withContext(const EmailPreviewContext(occasionTitle: title)));
      final controller = RichHtmlEditorController(initialHtml: '<p>{{occasionTitle}}</p>',
          owner: const HtmlMediaOwner.none(), authoring: provider);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
          alignment: Alignment.topLeft, child: RichHtmlEditor(controller: controller)))));
      await tester.pumpAndSettle();
      expect(find.text('@'), findsOneWidget);
      final marker = tester.getRect(find.text('@'));
      final sample = tester.getRect(find.text(title));
      expect(sample.left - marker.right, closeTo(4, .1));
      expect(sample.top, closeTo(marker.top, 1));
      expect(sample.right, lessThanOrEqualTo(375));
      expect(sample.height, greaterThan(marker.height * 1.5));
      final text = tester.widget<Text>(find.text(title));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
      final semantics = tester.widgetList<Semantics>(find.byType(Semantics))
          .where((widget) => widget.properties.label?.contains(title) == true).single;
      expect(semantics.excludeSemantics, isTrue);
      expect(semantics.properties.label, isNot(contains('@')));
      expect(controller.html, '<p>{{occasionTitle}}</p>');
      expect(controller.hasUserChanges, isFalse);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets(
      'used unique components stay visible while repeatable buttons remain insertable',
      (tester) async {
    final provider = EmailAuthoringProvider(
        EmailTemplateModel(code: 'TICKET_ORDER_CONFIRMATION'),
        field: EmailTargetField.body,
        scenario: scenario);
    final controller = RichHtmlEditorController(
        initialHtml:
            '<p>{{fullOrder}}</p><p>{{order_overview_button}}</p><p>Text</p>',
        owner: const HtmlMediaOwner.none(),
        authoring: provider);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: RichHtmlEditor(controller: controller)))));
    await tester.tap(find.byIcon(Icons.alternate_email));
    await tester.pumpAndSettle();
    final ranked = provider.search('', controller.templateUsage);
    expect(ranked.last.code, 'fullOrder');
    await tester.enterText(find.byType(TextField), 'fullOrder');
    await tester.pumpAndSettle();
    final unique = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .firstWhere((tile) =>
            (tile.title as Text).data == provider.entry('fullOrder')!.label);
    await tester.enterText(find.byType(TextField), 'order_overview_button');
    await tester.pumpAndSettle();
    final button = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .firstWhere((tile) =>
            (tile.title as Text).data ==
            provider.entry('order_overview_button')!.label);
    expect(unique.enabled, isFalse);
    expect(button.enabled, isTrue);

    expect(controller.insertTemplateToken('fullOrder'), isFalse);
    expect(tester.getTopLeft(find.byIcon(Icons.alternate_email)).dy,
        tester.getTopLeft(find.byIcon(Icons.format_bold)).dy);
    await tester.tap(find.byWidget(button));
    await tester.pumpAndSettle();
    expect(RegExp(r'\{\{order_overview_button\}\}').allMatches(controller.html),
        hasLength(2));
    controller.undo();
    expect(RegExp(r'\{\{order_overview_button\}\}').allMatches(controller.html),
        hasLength(1));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('received message is phone width and retains completed content',
      (tester) async {
    final html = scenario.composeHtml('<p>{{fullOrder}}</p>');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: EmailReceivedMessage(
                    subject: 'Vstupenky na ples',
                    html: html,
                    senderAddress: 'sender@organizer.test')))));
    await tester.pumpAndSettle();
    expect(find.textContaining('sender@organizer.test'), findsOneWidget);
    expect(
        find.textContaining('jana.novakova@example.com'), findsOneWidget);
    expect(tester.getSize(find.byType(EmailPreviewHtml)).width,
        lessThanOrEqualTo(400));
    expect(tester.widget<EmailPreviewHtml>(find.byType(EmailPreviewHtml)).html,
        html);
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
    expect(controller.focusNode.hasFocus, isFalse);
    await tester.tapAt(tester.getTopLeft(find.byType(EmailPreviewHtml)) + const Offset(20, 20));
    await tester.pumpAndSettle();
    final node = controller.editor.document.first as TextNode;
    final offset = node.text.placeholders.keys.single;
    expect(controller.editor.composer.selection, DocumentSelection(
      base: DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: offset)),
      extent: DocumentPosition(nodeId: node.id, nodePosition: TextNodePosition(offset: offset + 1)),
    ));
    expect(controller.focusNode.hasFocus, isTrue);
    expect(controller.hasUserChanges, isFalse);
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
      await tester.tap(find.byWidgetPredicate((widget) =>
          widget is ListTile &&
          (widget.title as Text).data == provider.entry(code)!.label));
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
