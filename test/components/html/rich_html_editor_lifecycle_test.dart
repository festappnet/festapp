import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as test_image;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/html/html_media_service.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/html/rich_html_editor_dialog.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/super_editor_test.dart';

void insert(RichHtmlEditorController controller, String text) {
  final node = controller.editor.document.first as TextNode;
  controller.editor.execute([
    InsertTextRequest(
      documentPosition: DocumentPosition(
        nodeId: node.id,
        nodePosition: TextNodePosition(offset: node.text.length),
      ),
      textToInsert: text,
      attributions: {},
    ),
  ]);
}

void _ignoreHtml(String _) {}

void main() {
  testWidgets(
    'inline actions share the toolbar on desktop and Save tracks changes',
    (tester) async {
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EditableHtmlField(
                html: '<p>Original</p>',
                onChanged: _ignoreHtml,
                onSave: (_) async {
                  writes++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      final controller =
          tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
      final save = find.widgetWithText(FilledButton, 'Common.save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      final tools = find.byIcon(Icons.format_bold).first;
      expect(tester.getCenter(save).dy, tester.getCenter(tools).dy);
      await tester.binding.setSurfaceSize(const Size(600, 600));
      await tester.pump();
      expect(tester.getBottomLeft(save).dy,
          lessThanOrEqualTo(tester.getTopLeft(tools).dy));
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
      await tester.pump();
      insert(controller, ' changed');
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      controller.editor.undo();
      await tester.pump();
      expect(controller.hasUserChanges, isFalse);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      controller.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(RichHtmlEditor), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'inline Escape and Storno confirm changes and retain declined drafts',
    (tester) async {
      var html = '<p>Original</p>';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditableHtmlField(
              html: html,
              onChanged: (value) => html = value,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      final controller =
          tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
      insert(controller, ' changed');
      controller.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('HtmlEditor.discardDraft'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.html, '<p>Original changed</p>');
      expect(controller.focusNode.hasFocus, isTrue);
      await tester.tap(find.text('Common.storno'));
      await tester.pumpAndSettle();
      expect(find.text('HtmlEditor.discardDraft'), findsOneWidget);
      await tester.tap(find.text('Common.ok'));
      await tester.pumpAndSettle();
      expect(find.byType(RichHtmlEditor), findsNothing);
      expect(html, '<p>Original</p>');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'fullscreen Save tracks edits and Escape confirms before cancelling',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EditableHtmlField(
              html: '<p>Original</p>',
              onChanged: _ignoreHtml,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      final controller =
          tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
      await tester.tap(find.byIcon(Icons.open_in_full));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Common.save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      insert(controller, ' changed');
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('HtmlEditor.discardDraft'), findsOneWidget);
      await tester.tap(find.text('Common.ok'));
      await tester.pumpAndSettle();
      expect(find.byType(RichHtmlEditorDialog), findsNothing);
      expect(find.byType(RichHtmlEditor), findsNothing);
      expect(find.byIcon(Icons.edit), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('selection toolbar formats text and follows selection lifetime', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final controller = RichHtmlEditorController(
      initialHtml: '<p>Selected text</p>',
      owner: const HtmlMediaOwner.none(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RichHtmlEditor(controller: controller)),
      ),
    );
    controller.focusNode.requestFocus();
    await tester.pump();
    final node = controller.editor.document.first as TextNode;
    final selection = DocumentSelection(
      base: DocumentPosition(
        nodeId: node.id,
        nodePosition: const TextNodePosition(offset: 0),
      ),
      extent: DocumentPosition(
        nodeId: node.id,
        nodePosition: const TextNodePosition(offset: 8),
      ),
    );
    controller.editor.execute([
      ChangeSelectionRequest(
        selection,
        SelectionChangeType.expandSelection,
        SelectionReason.userInteraction,
      ),
    ]);
    await tester.pump();
    await tester.pump();
    final toolbar = find.byKey(const ValueKey('html-selection-toolbar'));
    expect(toolbar, findsOneWidget);
    await tester.tap(
      find.descendant(of: toolbar, matching: find.byIcon(Icons.format_bold)),
    );
    await tester.pump();
    expect(controller.html, contains('<strong>Selected</strong>'));
    expect(controller.editor.composer.selection, selection);
    expect(controller.focusNode.hasFocus, isTrue);
    controller.editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(position: selection.extent),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    await tester.pump();
    await tester.pump();
    expect(toolbar, findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('existing images reuse the reading view image cache', (
    tester,
  ) async {
    const source = 'https://a.img.festapp.net/images/643/existing.png';
    // Seed the exact provider used by HtmlView, so this checks decoded-cache
    // reuse without starting a real HTTP request in widget-test fake time.
    final image = await tester.runAsync(
      () => decodeImageFromList(
        Uint8List.fromList(
          test_image.encodePng(test_image.Image(width: 1, height: 1)),
        ),
      ),
    );
    final provider = CachedNetworkImageProvider(
      source,
      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
    );
    PaintingBinding.instance.imageCache.putIfAbsent(
      provider,
      () =>
          OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image!))),
    );
    addTearDown(() => PaintingBinding.instance.imageCache.evict(provider));
    var fetches = 0;
    final media = HtmlMediaDraft(
      fetch: (_, __) async {
        fetches++;
        throw StateError('Existing preview must use the reading cache');
      },
      owns: (_, __) async => true,
    );
    final controller = RichHtmlEditorController(
      initialHtml: '<p>Original</p><img src="$source">',
      owner: const HtmlMediaOwner.occasion(12),
      media: media,
    );
    addTearDown(controller.dispose);
    addTearDown(media.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RichHtmlEditor(controller: controller)),
      ),
    );
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(fetches, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('writer may remove the field before save completes', (
    tester,
  ) async {
    final complete = Completer<void>();
    final coordinator = HtmlSaveCoordinator();
    addTearDown(coordinator.dispose);
    var visible = true;
    late StateSetter rebuild;
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HtmlEditingScope(
            coordinator: coordinator,
            child: StatefulBuilder(
              builder: (_, setState) {
                rebuild = setState;
                return visible
                    ? EditableHtmlField(
                        html: '<p>Original</p>',
                        onChanged: (_) => changes++,
                        onSave: (_) => complete.future,
                      )
                    : const Text('Refreshed');
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    final controller =
        tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
    insert(controller, ' saved');
    await tester.pump();
    await tester.tap(find.text('Common.save'));
    await tester.pump();
    rebuild(() => visible = false);
    await tester.pump();
    complete.complete();
    await tester.pump();
    expect(changes, 0);
    expect(tester.takeException(), isNull);
    expect(coordinator.hasDraft, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('expand opens a whole page and retains the inline draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: EditableHtmlField(
                  html: '<p>Original</p>',
                  onChanged: _ignoreHtml,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    final controller =
        tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
    insert(controller, ' draft');
    await tester.pump();
    controller.focusNode.requestFocus();
    await tester.pump();
    final node = controller.editor.document.first as TextNode;
    controller.editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: node.id,
            nodePosition: const TextNodePosition(offset: 3),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    await tester.pump();
    final selection = controller.editor.composer.selection;
    expect(controller.focusNode.hasFocus, isTrue);
    final expandButton = find.byIcon(Icons.open_in_full);
    expect(tester.getCenter(expandButton).dx, greaterThan(1100));
    expect(
      tester.getCenter(expandButton).dy,
      tester.getCenter(find.byIcon(Icons.format_bold).first).dy,
    );
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final page = find.byType(RichHtmlEditorDialog);
    expect(page, findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(controller.focusNode.hasFocus, isTrue);
    expect(controller.editor.composer.selection, selection);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.getSize(page), const Size(1200, 800));
    final route = ModalRoute.of(tester.element(page))!;
    expect(route, isA<PageRoute<HtmlEditorFullscreenAction>>());
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    expect(
      tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller,
      same(controller),
    );
    await tester.typeImeText('x');
    await tester.pump();
    expect(controller.html, '<p>Orixginal draft</p>');
    insert(controller, ' expanded');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_fullscreen));
    await tester.pump();
    await tester.pump(
      route.reverseTransitionDuration + const Duration(milliseconds: 100),
    );
    await tester.pump();
    expect(find.byType(RichHtmlEditorDialog), findsNothing);
    expect(controller.html, '<p>Orixginal draft expanded</p>');
    expect(
      tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller,
      same(controller),
    );
    await tester.pumpWidget(const SizedBox());
  });
  for (final save in [true, false]) {
    testWidgets(
      'fullscreen ${save ? "save" : "cancel"} returns original modal HTML to viewing',
      (tester) async {
        var html = '<p>Original</p>';
        var writes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: StatefulBuilder(
                        builder: (context, setState) => EditableHtmlField(
                          html: html,
                          onChanged: (value) => setState(() => html = value),
                          onSave: (_) async {
                            writes++;
                          },
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open parent modal'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open parent modal'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.edit));
        await tester.pump();
        final controller = tester
            .widget<RichHtmlEditor>(find.byType(RichHtmlEditor))
            .controller;
        insert(controller, ' changed');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.open_in_full));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text(save ? 'Common.save' : 'Common.storno'));
        await tester.pumpAndSettle();
        if (!save) {
          await tester.tap(find.text('Common.ok'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(RichHtmlEditorDialog), findsNothing);
        expect(find.byType(RichHtmlEditor), findsNothing);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byIcon(Icons.edit), findsOneWidget);
        expect(html, save ? '<p>Original changed</p>' : '<p>Original</p>');
        expect(writes, save ? 1 : 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('modal editor expands and returns with its draft and caret', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await RichHtmlEditorDialog.show(
                  context,
                  initialHtml: '<p>Original</p>',
                  title: 'Datagrid',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    final controller =
        tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
    controller.focusNode.requestFocus();
    await tester.pump();
    final selection = controller.editor.composer.selection;
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    expect(
      tester.getSize(find.byType(RichHtmlEditorDialog)),
      const Size(1200, 800),
    );
    expect(
      tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).fullscreen,
      isTrue,
    );
    expect(controller.focusNode.hasFocus, isTrue);
    expect(controller.editor.composer.selection, selection);
    await tester.typeImeText(' draft');
    await tester.pump();
    expect(controller.html, '<p>Original draft</p>');
    await tester.tap(find.byIcon(Icons.close_fullscreen));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Dialog), findsOneWidget);
    expect(controller.focusNode.hasFocus, isTrue);
    expect(controller.html, '<p>Original draft</p>');
    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.text('Common.save'));
    await tester.pumpAndSettle();
    expect(saved, '<p>Original draft</p>');
    expect(find.byType(RichHtmlEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'fullscreen left toolbar stays fixed while the document scrolls',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final html = List.generate(80, (i) => '<p>Paragraph $i</p>').join();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EditableHtmlField(html: html, onChanged: _ignoreHtml),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      await tester.ensureVisible(find.byIcon(Icons.open_in_full));
      await tester.tap(find.byIcon(Icons.open_in_full));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final toolbar = find.byIcon(Icons.format_bold);
      final before = tester.getTopLeft(toolbar);
      final italic = tester.getTopLeft(find.byIcon(Icons.format_italic));
      expect(italic.dx, before.dx);
      expect(italic.dy, greaterThan(before.dy));
      final document = find.byType(CustomScrollView);
      expect(document, findsOneWidget);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: document, matching: find.byType(Scrollable)).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(300));
      scrollable.position.jumpTo(300);
      await tester.pump();
      expect(scrollable.position.pixels, 300);
      expect(tester.getTopLeft(toolbar), before);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
      '$platform keeps one editor in light/dark compact and desktop layouts',
      (tester) async {
        final controller = RichHtmlEditorController(
          initialHtml: '<p>Český 👩🏽‍💻 text</p>',
          owner: const HtmlMediaOwner.none(),
        );
        addTearDown(controller.dispose);
        for (final brightness in Brightness.values) {
          tester.view.physicalSize = Size(
            brightness == Brightness.light ? 360 : 1000,
            800,
          );
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: RichHtmlEditor(controller: controller),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(SuperEditor), findsOneWidget);
          expect(tester.takeException(), isNull);
          controller.focusNode.requestFocus();
          await tester.pump();
          expect(tester.testTextInput.hasAnyClients, isTrue);
          controller.reset('<p>Reset</p>');
          await tester.pump();
          insert(controller, ' další');
          await tester.pump();
          expect(controller.html, contains('Reset další'));
        }
        await tester.pumpWidget(const SizedBox());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
      variant: TargetPlatformVariant({platform}),
    );
  }
  testWidgets(
    'parent save flushes an active field while Cancel restores its snapshot',
    (tester) async {
      final coordinator = HtmlSaveCoordinator();
      addTearDown(coordinator.dispose);
      var html = '<p>Original</p>';
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HtmlEditingScope(
              coordinator: coordinator,
              child: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                  child: Column(
                    children: [
                      EditableHtmlField(
                        html: html,
                        owner: const HtmlMediaOwner.none(),
                        onChanged: (value) => setState(() => html = value),
                      ),
                      TextButton(
                        onPressed: () => coordinator.save(() async {
                          writes++;
                          coordinator.markSaved();
                        }),
                        child: const Text('Parent Save'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      final controller =
          tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
      insert(controller, ' changed');
      await tester.pump();
      expect(coordinator.hasDraft, isTrue);
      await tester.tap(find.text('Common.storno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Common.ok'));
      await tester.pumpAndSettle();
      expect(html, '<p>Original</p>');
      expect(coordinator.hasDraft, isFalse);
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      insert(controller, ' saved');
      await tester.pump();
      await tester.tap(find.text('Parent Save'));
      await tester.pump();
      expect(writes, 1);
      expect(html, '<p>Original saved</p>');
      expect(find.byType(RichHtmlEditor), findsNothing);
      expect(coordinator.hasDraft, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'read field preserves draft on writer failure and awaits a successful retry',
    (tester) async {
      var attempts = 0;
      var html = '<p>Original</p>';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: EditableHtmlField(
                  html: html,
                  owner: const HtmlMediaOwner.none(),
                  onChanged: (value) => setState(() => html = value),
                  onSave: (value) async {
                    attempts++;
                    if (attempts == 1) throw StateError('Writer failed');
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      final controller =
          tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
      insert(controller, ' retry');
      await tester.pump();
      await tester.tap(find.text('Common.save'));
      await tester.pumpAndSettle();
      expect(find.byType(RichHtmlEditor), findsOneWidget);
      expect(html, '<p>Original</p>');
      expect(controller.html, '<p>Original retry</p>');
      await tester.tap(find.text('Common.save'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(html, '<p>Original retry</p>');
      expect(find.byType(RichHtmlEditor), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
