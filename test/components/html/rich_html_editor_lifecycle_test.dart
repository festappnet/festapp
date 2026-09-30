import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as test_image;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/html/html_media_service.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:super_editor/super_editor.dart';

void insert(RichHtmlEditorController controller, String text) {
  final node = controller.editor.document.first as TextNode;
  controller.editor.execute([
    InsertTextRequest(
        documentPosition: DocumentPosition(
            nodeId: node.id,
            nodePosition: TextNodePosition(offset: node.text.length)),
        textToInsert: text,
        attributions: {})
  ]);
}

void main() {
  testWidgets('existing images reuse the reading view image cache',
      (tester) async {
    const source = 'https://a.img.festapp.net/images/643/existing.png';
    // Seed the exact provider used by HtmlView, so this checks decoded-cache
    // reuse without starting a real HTTP request in widget-test fake time.
    final image = await tester.runAsync(() => decodeImageFromList(
        Uint8List.fromList(
            test_image.encodePng(test_image.Image(width: 1, height: 1)))));
    final provider = CachedNetworkImageProvider(source,
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet);
    PaintingBinding.instance.imageCache.putIfAbsent(
        provider,
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: image!))));
    addTearDown(() => PaintingBinding.instance.imageCache.evict(provider));
    var fetches = 0;
    final media = HtmlMediaDraft(
        fetch: (_, __) async {
          fetches++;
          throw StateError('Existing preview must use the reading cache');
        },
        owns: (_, __) async => true);
    final controller = RichHtmlEditorController(
        initialHtml: '<p>Original</p><img src="$source">',
        owner: const HtmlMediaOwner.occasion(12),
        media: media);
    addTearDown(controller.dispose);
    addTearDown(media.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RichHtmlEditor(controller: controller))));
    await tester.pump();
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(fetches, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('writer may remove the field before save completes',
      (tester) async {
    final complete = Completer<void>();
    final coordinator = HtmlSaveCoordinator();
    addTearDown(coordinator.dispose);
    var visible = true;
    late StateSetter rebuild;
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HtmlEditingScope(
                coordinator: coordinator,
                child: StatefulBuilder(builder: (_, setState) {
                  rebuild = setState;
                  return visible
                      ? EditableHtmlField(
                          html: '<p>Original</p>',
                          onChanged: (_) => changes++,
                          onSave: (_) => complete.future)
                      : const Text('Refreshed');
                })))));
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
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS
  ]) {
    testWidgets(
        '$platform keeps one editor in light/dark compact and desktop layouts',
        (tester) async {
      final controller = RichHtmlEditorController(
          initialHtml: '<p>Český 👩🏽‍💻 text</p>',
          owner: const HtmlMediaOwner.none());
      addTearDown(controller.dispose);
      for (final brightness in Brightness.values) {
        tester.view.physicalSize =
            Size(brightness == Brightness.light ? 360 : 1000, 800);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: RichHtmlEditor(controller: controller)))));
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
    }, variant: TargetPlatformVariant({platform}));
  }
  testWidgets(
      'parent save flushes an active field while Cancel restores its snapshot',
      (tester) async {
    final coordinator = HtmlSaveCoordinator();
    addTearDown(coordinator.dispose);
    var html = '<p>Original</p>';
    var writes = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HtmlEditingScope(
                coordinator: coordinator,
                child: StatefulBuilder(
                    builder: (context, setState) => SingleChildScrollView(
                            child: Column(children: [
                          EditableHtmlField(
                              html: html,
                              owner: const HtmlMediaOwner.none(),
                              onChanged: (value) =>
                                  setState(() => html = value)),
                          TextButton(
                              onPressed: () => coordinator.save(() async {
                                    writes++;
                                    coordinator.markSaved();
                                  }),
                              child: const Text('Parent Save')),
                        ])))))));
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    final controller =
        tester.widget<RichHtmlEditor>(find.byType(RichHtmlEditor)).controller;
    insert(controller, ' changed');
    await tester.pump();
    expect(coordinator.hasDraft, isTrue);
    await tester.tap(find.text('Common.storno'));
    await tester.pump();
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
  });
  testWidgets(
      'read field preserves draft on writer failure and awaits a successful retry',
      (tester) async {
    var attempts = 0;
    var html = '<p>Original</p>';
    await tester.pumpWidget(MaterialApp(
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
                        }))))));
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
  });
}
