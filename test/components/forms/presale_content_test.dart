import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_editor/super_editor.dart';
import 'package:festapp_core/time.dart' as core_time;
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/presale_content_draft.dart';
import 'package:fstapp/components/forms/views/presale_content_editor.dart';
import 'package:fstapp/components/forms/views/sale_opening_settings.dart';
import 'package:fstapp/components/forms/widgets_view/presale_content.dart';
import 'package:fstapp/components/forms/widgets_view/sale_opening_notification.dart';
import 'package:fstapp/components/forms/widgets_view/countdown_widget.dart';
import 'package:fstapp/components/html/html_embedded_block.dart';
import 'package:fstapp/components/html/html_editor_document.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(core_time.OccasionTimeContext.initializeTimeZones);
  final translations = jsonDecode(
    File('assets/translations/cs.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  WidgetEnvironmentFixture env() => WidgetEnvironmentFixture(
    locale: const Locale('cs'),
    translations: translations,
  );
  FormEditorDraft form({bool paused = false, bool enabled = true}) =>
      FormEditorDraft(
        title: 'Form',
        isOpen: true,
        data: {
          'schedule': {
            'start_time': '2099-01-01T12:00:00Z',
            'countdown_title': '<p>Intro</p>$saleOpeningBlockHtml<p>End</p>',
          },
          'sale_opening_notifications': {
            'enabled': enabled,
            'collection_paused': paused,
          },
          'design': {'presale_header': 'event_and_date'},
        },
      );
  RichHtmlEditorController controller(FormEditorDraft f) =>
      RichHtmlEditorController(
        initialHtml: f.definition.presaleContent,
        owner: const HtmlMediaOwner.none(),
        embeddedBlocks: [
          HtmlEmbeddedBlock(
            cssClass: 'form-countdown',
            builder: (_) => const SizedBox(),
          ),
          HtmlEmbeddedBlock(
            cssClass: 'form-sale-opening-notification',
            builder: (_) => const SizedBox(),
          ),
        ],
        historyBinding: PresaleContentDraft.binding(f, () {}),
      );
  for (final paused in [false, true]) {
    test(
      'native remove/undo/redo restores exact collection state paused=$paused',
      () {
        final f = form(paused: paused);
        final original = jsonEncode(f.definition.toJson());
        final c = controller(f);
        addTearDown(c.dispose);
        final node = c.editor.document.whereType<PreservedHtmlNode>().single;
        c.removeAtomic(node.id);
        expect(f.definition.saleOpeningPaused, true);
        expect(
          f.definition.presaleContent,
          isNot(contains('form-sale-opening-notification')),
        );
        c.undo();
        expect(jsonEncode(f.definition.toJson()), original);
        c.redo();
        expect(f.definition.saleOpeningPaused, true);
        c.undo();
        final text = c.editor.document.first as TextNode;
        c.editor.execute([
          InsertTextRequest(
            documentPosition: DocumentPosition(
              nodeId: text.id,
              nodePosition: const TextNodePosition(offset: 0),
            ),
            textToInsert: 'New ',
            attributions: {},
          ),
        ]);
        c.redo();
        expect(f.definition.presaleContent, contains('New Intro'));
        expect(f.definition.saleOpeningPaused, paused);
      },
    );
  }
  test(
    'selection and opening history session never change the parent draft',
    () {
      final f = form();
      final original = jsonEncode(f.toEditedJson());
      final c = controller(f);
      addTearDown(c.dispose);
      c.selectAtomic(c.editor.document.whereType<PreservedHtmlNode>().single);
      expect(jsonEncode(f.toEditedJson()), original);
    },
  );
  test(
    'keyboard range deletion and Cut share native history with text and flags',
    () async {
      final f = form();
      final c = controller(f);
      addTearDown(c.dispose);
      final original = c.html;
      final node = c.editor.document.whereType<PreservedHtmlNode>().single;
      c.selectAtomic(node);
      c.editor.execute([
        DeleteContentRequest(documentRange: c.editor.composer.selection!),
      ]);
      expect(f.definition.saleOpeningPaused, true);
      c.undo();
      expect(f.definition.saleOpeningPaused, false);
      expect(c.html, original);
      c.selectAtomic(c.editor.document.whereType<PreservedHtmlNode>().single);
      await c.copy(cut: true);
      expect(f.definition.saleOpeningPaused, true);
      c.undo();
      expect(c.html, original);
      expect(f.definition.saleOpeningPaused, false);
    },
  );
  test(
    'activation preserves authored order and never duplicates or enables timer',
    () {
      final f = form(enabled: false);
      final c = controller(f);
      addTearDown(c.dispose);
      final d = PresaleContentDraft(f, editor: c);
      final original = c.html;
      d.collect();
      d.collect();
      expect(c.html, original);
      expect(f.definition.enableCountdown, false);
      expect(f.definition.saleOpeningEnabled, true);
      d.pause();
      expect(c.html, original);
      expect(f.definition.saleOpeningPaused, true);
      c.undo();
      expect(f.definition.saleOpeningPaused, false);
    },
  );
  test('pasted notification stays inert until explicit activation', () {
    final f = FormEditorDraft(
      data: {
        'schedule': {'countdown_title': '<p>Text</p>'},
      },
    );
    final c = controller(f);
    addTearDown(c.dispose);
    c.appendHtml(saleOpeningBlockHtml);
    expect(f.definition.saleOpeningEnabled, false);
  });
  test('pasting a slot into an enabled page without one pauses instead of activating collection', () {
    final f = FormEditorDraft(
      isOpen: true,
      data: {
        'schedule': {
          'start_time': '2099-01-01T12:00:00Z',
          'countdown_title':
              '<p>Text mentions form-sale-opening-notification</p>',
        },
        'sale_opening_notifications': {
          'enabled': true,
          'collection_paused': false,
        },
      },
    );
    final c = controller(f);
    addTearDown(c.dispose);
    c.appendHtml(saleOpeningBlockHtml);
    expect(f.definition.saleOpeningPaused, true);
    c.undo();
    expect(f.definition.saleOpeningPaused, false);
    PresaleContentDraft(f, editor: c).collect();
    expect(f.definition.saleOpeningPaused, false);
    expect(hasPresaleSlot(c.html, 'form-sale-opening-notification'), true);
  });
  test('recovered secondary markers cannot activate collection', () {
    final html = inertPresaleSecondary(
      '<p>Private</p>$saleOpeningBlockHtml$countdownBlockHtml',
    );
    expect(html, contains('Private'));
    expect(html, isNot(contains('html-editor-block')));
  });
  for (final width in [375.0, 1024.0])
    for (final dark in [false, true]) {
      testWidgets(
        'collapsed editor keeps one parent draft width=$width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final f = form(enabled: false);
          final before = jsonEncode(f.toEditedJson());
          final media = HtmlSaveCoordinator();
          addTearDown(media.dispose);
          await env().pumpWidget(
            tester,
            MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              builder: DependencyMaterialBridge.builder,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: PresaleContentEditor(
                    form: f,
                    coordinator: media,
                    canEdit: true,
                    onChanged: () {},
                    loadSummary: (_) async => {},
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(RichHtmlEditorController), findsNothing);
          expect(find.byType(PresaleContent), findsNothing);
          expect(find.byType(SaleOpeningSettings), findsNothing);
          await tester.tap(find.byKey(const ValueKey('presale-section')));
          await tester.pumpAndSettle();
          expect(find.byType(PresaleContent), findsOneWidget);
          expect(find.text('Standardní hlavička'), findsNothing);
          expect(jsonEncode(f.toEditedJson()), before);
          expect(media.hasActiveDraft, false);
          await tester.ensureVisible(
            find.byKey(const ValueKey('presale-customize')),
          );
          await tester.tap(find.byKey(const ValueKey('presale-customize')));
          await tester.pump();
          expect(find.text('Standardní hlavička'), findsOneWidget);
          expect(jsonEncode(f.toEditedJson()), before);
          expect(media.hasActiveDraft, false);
          await tester.ensureVisible(
            find.byKey(const ValueKey('presale-customize')),
          );
          await tester.tap(find.byKey(const ValueKey('presale-customize')));
          await tester.pump();
          expect(find.text('Standardní hlavička'), findsNothing);
          expect(jsonEncode(f.toEditedJson()), before);
          await tester.ensureVisible(find.text('Stránka před otevřením'));
          await tester.tap(find.text('Stránka před otevřením'));
          await tester.pumpAndSettle();
          expect(find.byType(PresaleContent), findsNothing);
          expect(find.byType(SaleOpeningSettings), findsNothing);
          expect(jsonEncode(f.toEditedJson()), before);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  test('editing a migrated system title preserves authored text and Undo restores localization', () {
    final f = form();
    const original =
        '<p class="form-presale-system-title">Začátek přihlašování</p>';
    f.definition = f.definition.withPresaleContent(original);
    final c = controller(f);
    addTearDown(c.dispose);
    final node = c.editor.document.first as TextNode;
    c.editor.execute([
      InsertTextRequest(
        documentPosition: DocumentPosition(
          nodeId: node.id,
          nodePosition: const TextNodePosition(offset: 0),
        ),
        textToInsert: 'Vítejte! ',
        attributions: {},
      ),
    ]);
    expect(f.definition.presaleContent, contains('Vítejte!'));
    expect(
      f.definition.presaleContent,
      isNot(contains('form-presale-system-title')),
    );
    c.undo();
    expect(f.definition.presaleContent, original);
    expect(
      presaleEditedHtml(
        '<p class="form-presale-system-title"><strong>Začátek přihlašování</strong></p>',
        original,
      ),
      '<p><strong>Začátek přihlašování</strong></p>',
    );
  });
  testWidgets('email-only preview stays content-sized inside a tall editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await env().pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: SingleChildScrollView(
            child: PresaleContent(
              targetTime: DateTime(2099),
              onFinished: () {},
              html: saleOpeningBlockHtml,
              header: 'none',
              showTimer: false,
              canSubscribe: true,
              preview: true,
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(PresaleContent)).height, lessThan(400));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final adminDark in [false, true]) {
    testWidgets(
      'preview text remains readable against the opposite admin theme $adminDark',
      (tester) async {
        final f = form(enabled: false);
        f.definition = f.definition.withThemeMode(adminDark ? 'light' : 'dark');
        final media = HtmlSaveCoordinator();
        addTearDown(media.dispose);
        await env().pumpWidget(
          tester,
          MaterialApp(
            theme: ThemeData(
              brightness: adminDark ? Brightness.dark : Brightness.light,
            ),
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: SingleChildScrollView(
                child: PresaleContentEditor(
                  form: f,
                  coordinator: media,
                  canEdit: true,
                  onChanged: () {},
                  loadSummary: (_) async => {},
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Stránka před otevřením'));
        await tester.pumpAndSettle();
        final title = find.text('Form');
        final paragraph = tester.renderObject<RenderParagraph>(title);
        final foreground = paragraph.text.style!.color!.computeLuminance();
        final background = Theme.of(tester.element(title))
            .scaffoldBackgroundColor
            .computeLuminance();
        final ratio = foreground > background
            ? (foreground + .05) / (background + .05)
            : (background + .05) / (foreground + .05);
        expect(ratio, greaterThanOrEqualTo(4.5));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'email-only preview hydrates when summary arrives after the HTML was mounted',
    (tester) async {
      final summary = Completer<Map<String, dynamic>>();
      final f = form();
      f.definition = f.definition
          .withPresaleHeader('none')
          .withPresaleContent(saleOpeningBlockHtml)
          .withThemeMode('dark');
      final media = HtmlSaveCoordinator();
      addTearDown(media.dispose);
      await env().pumpWidget(
        tester,
        MaterialApp(
          theme: ThemeData.light(),
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PresaleContentEditor(
                form: f,
                coordinator: media,
                canEdit: true,
                onChanged: () {},
                loadSummary: (_) => summary.future,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      summary.complete({
        'phase': 'armed',
        'subscribers': {'active': 1},
      });
      await tester.pump();
      await tester.tap(find.text('Stránka před otevřením'));
      await tester.pumpAndSettle();
      expect(find.byType(SaleOpeningNotification), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  final fixtures = jsonDecode(
    File('shared/presale/render-cases.json').readAsStringSync(),
  ) as List;
  for (final f in fixtures)
    testWidgets('shared public fixture: ${f['name']}', (tester) async {
      await env().pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              child: PresaleContent(
                targetTime: DateTime(2099, 1, 1, 12),
                onFinished: () {},
                html: f['html'],
                header: f['header'],
                eventTitle: 'Event',
                showTimer: f['timer'],
                canSubscribe: f['email'],
                preview: true,
              ),
            ),
          ),
        ),
      );
      expect(
        find.byType(CountdownWidget),
        f['timer'] ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(SaleOpeningNotification),
        f['email'] &&
                (f['html'] as String).contains('form-sale-opening-notification')
            ? findsOneWidget
            : findsNothing,
      );
      expect(find.text('Event'), f['title'] ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
}
