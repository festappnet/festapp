import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:fstapp/components/fonts/ticket_font_ids.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/ticket_layout/ticket_snapping.dart';
import 'package:flutter/rendering.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:fstapp/components/fonts/font_family_picker.dart';
import 'package:fstapp/components/fonts/ticket_font_catalog.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_dimensions_dialog.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_controller.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import 'package:fstapp/components/ticket_layout/ticket_text.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_layout_canvas.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_layout_editor.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_layout_properties.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_settings.dart';

final fixture = jsonDecode(
    File('test/fixtures/ticket_layout/resolve.json').readAsStringSync()) as Map;
TicketTemplate document() => TicketTemplate.fromJson(fixture['template']);
TicketLayoutResources resources({ui.Image? background}) =>
    TicketLayoutResources(
        background: background,
        fonts: legacyTicketFontIds.map((name, id) => MapEntry(
            id,
            TicketFontResource(
                id,
                {
                  'futura': 'Futura PT',
                  'robotoSlab': 'Roboto Slab (legacy)',
                  'roboto': 'Roboto (legacy)',
                  'russoOne': 'Russo One (legacy)'
                }[name]!,
                400,
                TicketFontMetrics.fromJson(fixture['metrics']),
                'TicketFont_${id.split(':').last}'))),
        template: document(),
        preset: document(),
        presets: (fixture['presets'] as Map).map((key, value) =>
            MapEntry(key as String, TicketTemplate.fromJson(value))),
        scenarios: (fixture['scenarios'] as Map).map((k, v) =>
            MapEntry(k as String, (v as Map).cast<String, String?>())),
        metrics: TicketFontMetrics.fromJson(fixture['metrics']),
        qrSize: fixture['qrMatrix']['size'],
        qrModules: (fixture['qrMatrix']['data'] as List).cast<int>());

class SettingsService extends TicketLayoutService {
  String? resolvedType;
  int resolveCalls = 0;
  Completer<TicketLayoutResources>? pendingResolve;
  @override
  Future<bool> openTemplatePickerOnce(int occasionId, String userId,
          {required bool configured}) async =>
      false;
  @override
  Future<TicketLayoutResources> resolve(int occasionId, String type,
      Map<String, dynamic>? layout, String? background) async {
    resolvedType = type;
    resolveCalls++;
    if (pendingResolve != null) return pendingResolve!.future;
    return resources();
  }
}

class FakeService extends TicketLayoutService {
  final fontResponses = <String, Completer<TicketFontResource>>{};
  @override
  Future<TicketFontResource> font(int occasionId, String id) =>
      fontResponses[id]!.future;
  int pdfCalls = 0;
  Completer<({Uint8List bytes, List<String> warnings})>? pending;
  @override
  Future<({Uint8List bytes, List<String> warnings})> preview(
      int occasionId,
      String type,
      Map<String, dynamic> layout,
      String scenario,
      String? background) async {
    pdfCalls++;
    if (pending != null) return pending!.future;
    throw StateError('offline');
  }
}

void main() {
  final localizationWarnings = <String>[];
  final originalPrinter = EasyLocalization.logger.printer;
  setUp(() {
    localizationWarnings.clear();
    EasyLocalization.logger.printer = (object, {name, stackTrace, level}) {
      if (level.toString().contains('warning') ||
          level.toString().contains('error')) {
        localizationWarnings.add(object.toString());
      }
      originalPrinter?.call(object,
          name: name, stackTrace: stackTrace, level: level);
    };
  });
  tearDown(() {
    EasyLocalization.logger.printer = originalPrinter;
    expect(localizationWarnings, isEmpty,
        reason:
            'Editor tests must resolve real translations without warnings.');
  });
  testWidgets(
      'selected tools and dimensions dialog use the editor dark palette',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(TicketFontCatalog.load);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeConfig.theme(brightness: Brightness.dark),
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'wide',
            resources: resources(),
            service: FakeService())));
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'TicketLayout.snap'.tr()));
    final foreground = button.style!.foregroundColor!.resolve({})!;
    final background = button.style!.backgroundColor!.resolve({})!;
    final a = foreground.computeLuminance(), b = background.computeLuminance();
    expect(((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
        greaterThanOrEqualTo(4.5));
    final editorTheme = Theme.of(tester.element(find.byType(Scaffold)));
    await tester.tap(find.text('TicketLayout.canvasSize'.tr()).first);
    await tester.pumpAndSettle();
    final dialogTheme =
        Theme.of(tester.element(find.byType(TicketDimensionsDialog)));
    expect(dialogTheme.colorScheme, editorTheme.colorScheme);
    expect(dialogTheme.useMaterial3, isTrue);
  });
  testWidgets(
      'paper dialog has separated fields on desktop and mobile in both themes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(() async {
      final loader = FontLoader('Futura')
        ..addFont(Future.value(ByteData.sublistView(
            File('fonts/Futura PT Book.ttf').readAsBytesSync())))
        ..addFont(Future.value(ByteData.sublistView(
            File('fonts/Futura PT Medium.ttf').readAsBytesSync())));
      await loader.load();
    });
    for (final brightness in Brightness.values) {
      for (final screenWidth in [360.0, 1000.0]) {
        tester.view.physicalSize = Size(screenWidth, 900);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
                theme: ThemeConfig.theme(brightness: brightness).copyWith(
                    inputDecorationTheme: const InputDecorationTheme(
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(8))))),
                home: Scaffold(
                    body: TicketDimensionsDialog(
                        document: document().withPaper(true,
                            margin: TicketTemplate.defaultPageMargin),
                        type: 'wide')))));
        await tester.pumpAndSettle();
        final width = tester.getRect(
            find.widgetWithText(TextField, 'TicketLayout.widthMm'.tr()));
        final height = tester.getRect(
            find.widgetWithText(TextField, 'TicketLayout.heightMm'.tr()));
        final heading =
            tester.getRect(find.text('TicketLayout.designSize'.tr()));
        expect(width.top - heading.bottom, greaterThanOrEqualTo(20));
        if (screenWidth < 380) {
          expect(height.top - width.bottom, greaterThanOrEqualTo(20));
        } else {
          expect(height.left - width.right, greaterThanOrEqualTo(16));
          expect(height.top, width.top);
        }
        expect(tester.takeException(), isNull);
        final capture = Platform.environment['TICKET_DIALOG_CAPTURE_DIR'];
        if (capture != null) {
          final boundary = boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          final image =
              (await tester.runAsync(() => boundary.toImage(pixelRatio: 1.5)))!;
          final bytes = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png)))!;
          File('$capture/dialog-${brightness.name}-${screenWidth.toInt()}.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
          image.dispose();
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
  });
  testWidgets(
      'old ticket templates propose a margin but explicit zero is retained',
      (tester) async {
    final old = document().withPaper(true).toJson()..remove('pageMargin');
    TicketTemplate? preview;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TicketDimensionsDialog(
                document: TicketTemplate.fromJson(old),
                type: 'wide',
                onPreview: (value) => preview = value))));
    await tester.pumpAndSettle();
    expect(preview!.pageMargin, TicketTemplate.defaultPageMargin);
    await tester.enterText(
        find.widgetWithText(TextField, 'TicketLayout.marginMm'.tr()), '0');
    await tester.pumpAndSettle();
    expect(preview!.toJson()['pageMargin'], 0);
    final saved = TicketTemplate.fromJson(preview!.toJson());
    await tester.pumpWidget(const SizedBox());
    preview = null;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TicketDimensionsDialog(
                document: saved,
                type: 'wide',
                onPreview: (value) => preview = value))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(
                find.widgetWithText(TextField, 'TicketLayout.marginMm'.tr()))
            .controller!
            .text,
        '0.0');
    expect(preview, isNull);
  });
  testWidgets(
      'paper dialog previews ticket-sized output without moving elements',
      (tester) async {
    final original = document().withPaper(false);
    TicketTemplate? preview;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TicketDimensionsDialog(
                document: original,
                type: 'wide',
                onPreview: (value) => preview = value))));
    await tester.tap(find.text('TicketLayout.paperTicket'.tr()));
    await tester.pumpAndSettle();
    expect(preview!.fitPageToTicket, isTrue);
    expect(preview!.page.width,
        closeTo(original.area.width + 6 * 72 / 25.4, .001));
    expect(preview!.area.left, closeTo(3 * 72 / 25.4, .001));
    expect(preview!.elements, original.elements);
    await tester.enterText(
        find.widgetWithText(TextField, 'TicketLayout.marginMm'.tr()), '5');
    await tester.pumpAndSettle();
    expect(preview!.pageMargin, closeTo(5 * 72 / 25.4, .001));
    expect(preview!.elements, original.elements);
    final lastValid = preview;
    await tester.enterText(
        find.widgetWithText(TextField, 'TicketLayout.marginMm'.tr()), '-1');
    await tester.pumpAndSettle();
    expect(preview, same(lastValid));
    expect(find.text('TicketLayout.invalidMargin'.tr()), findsOneWidget);
    await tester.tap(find.text('TicketLayout.paperA4'.tr()));
    await tester.pumpAndSettle();
    expect(preview!.page, const Size(595.28, 841.89));
    expect(preview!.fitPageToTicket, isFalse);
  });
  test(
      'paper margins round-trip, preserve content, and reject invalid contracts',
      () {
    final original = document();
    final bordered = original.withPaper(true, margin: 9);
    expect(bordered.validate('wide'), isEmpty);
    expect(bordered.area.topLeft, const Offset(9, 9));
    expect(bordered.page,
        Size(original.area.width + 18, original.area.height + 18));
    expect(bordered.elements, original.elements);
    expect(
        TicketTemplate.fromJson(bordered.toJson()).toJson(), bordered.toJson());
    final resized = bordered.resizeArea(bordered.area.size * .9);
    expect(resized.validate('wide'), isEmpty);
    expect(resized.page.width, resized.area.width + 18);
    expect(bordered.withPaper(false).appearance.containsKey('pageMargin'),
        isFalse);
    for (final value in [-1, 73, '9', null]) {
      expect(
          TicketTemplate.fromJson(bordered.toJson()..['pageMargin'] = value)
              .validate('wide'),
          contains('geometry'));
    }
  });
  test(
      'all image handles preserve aspect and opposite anchor with one undo step',
      () {
    const image = Size(400, 200);
    for (var corner = 0; corner < 4; corner++) {
      final c = TicketLayoutController(document());
      final original = c.document;
      final box = original.backgroundRect(image);
      final corners = [
        box.topLeft,
        box.topRight,
        box.bottomRight,
        box.bottomLeft
      ];
      final anchor = corners[(corner + 2) % 4];
      final drag = (anchor - corners[corner]) * .1;
      c.beginGesture();
      c.transformBackground(image, drag, corner: corner, snap: false);
      c.transformBackground(image, drag, corner: corner, snap: false);
      c.endGesture();
      final next = c.document.backgroundRect(image);
      expect(next.width, closeTo(box.width * .8, .001));
      expect(next.width / next.height, closeTo(2, .001));
      expect(
          ([
                    next.topLeft,
                    next.topRight,
                    next.bottomRight,
                    next.bottomLeft
                  ][(corner + 2) % 4] -
                  anchor)
              .distance,
          lessThan(.001));
      expect(c.document.elements, original.elements);
      c.undo();
      expect(c.document.toJson(), original.toJson());
      c.redo();
      c.beginGesture();
      c.transformBackground(image, drag, corner: corner, snap: false);
      c.cancelGesture();
      expect(c.document.backgroundRect(image), next);
      c.dispose();
    }
  });
  test('image snapping accumulates slow drag and respects disabled magnets',
      () {
    const image = Size(400, 200);
    final c = TicketLayoutController(document());
    final box = c.document.backgroundRect(image);
    c.beginGesture();
    c.transformBackground(image, const Offset(2, 0), zoom: 1);
    expect(c.document.backgroundRect(image).left, closeTo(box.left, .001));
    for (var i = 0; i < 12; i++) {
      c.transformBackground(image, const Offset(1, 0), zoom: 1);
    }
    expect(c.document.backgroundRect(image).left, greaterThan(box.left + 5));
    c.cancelGesture();
    c.beginGesture();
    c.transformBackground(image, const Offset(2, 0), snap: false);
    expect(c.document.backgroundRect(image).left, closeTo(box.left + 2, .001));
    c.cancelGesture();
    c.dispose();
  });
  test(
      'shared resize magnets snap to elements and grid while preserving aspect',
      () {
    final element = snapTicketBox(const Rect.fromLTWH(0, 0, 98, 49),
        const Size(500, 300), [const Rect.fromLTWH(100, 100, 40, 30)],
        zoom: 1, anchor: Offset.zero);
    expect(element.box, const Rect.fromLTWH(0, 0, 100, 50));
    expect(element.x, 100);
    final grid = snapTicketBox(
        const Rect.fromLTWH(12, 13, 86, 43), const Size(500, 300), [],
        zoom: 1, gridStep: 20, anchor: const Offset(12, 13));
    expect(grid.box.right, 100);
    expect(grid.box.width / grid.box.height, 2);
    final zoomed = snapTicketBox(const Rect.fromLTWH(0, 0, 98, 49),
        const Size(500, 300), [const Rect.fromLTWH(100, 100, 40, 30)],
        zoom: 4, anchor: Offset.zero);
    expect(zoomed.box.width, 98);
  });
  test(
      'crop corners, bounded movement, serialization, cancel and undo preserve the source',
      () {
    const image = Size(400, 200);
    for (var corner = 0; corner < 4; corner++) {
      final c = TicketLayoutController(document());
      final original = c.document;
      final full = original.backgroundRect(image);
      final corners = [
        full.topLeft,
        full.topRight,
        full.bottomRight,
        full.bottomLeft
      ];
      final drag = (corners[(corner + 2) % 4] - corners[corner]) * .25;
      c.beginGesture();
      c.cropBackground(image, drag, corner: corner, snap: false);
      c.endGesture();
      expect(c.document.backgroundCrop.width, closeTo(.75, .000001));
      expect(c.document.backgroundCrop.height, closeTo(.75, .000001));
      expect(c.document.backgroundRect(image), full);
      expect(c.document.elements, original.elements);
      expect(c.document.validate('wide'), isEmpty);
      final saved = TicketTemplate.fromJson(c.document.toJson());
      expect(saved.backgroundCrop, c.document.backgroundCrop);
      c.beginGesture();
      c.cropBackground(
          image,
          Offset(saved.backgroundCrop.left > 0 ? -9999 : 9999,
              saved.backgroundCrop.top > 0 ? -9999 : 9999),
          snap: false);
      c.endGesture();
      expect(c.document.backgroundCrop.left,
          closeTo(saved.backgroundCrop.left > 0 ? 0 : .25, .000001));
      expect(c.document.backgroundCrop.top,
          closeTo(saved.backgroundCrop.top > 0 ? 0 : .25, .000001));
      c.undo();
      expect(c.document.toJson(), saved.toJson());
      c.beginGesture();
      c.cropBackground(image, drag, corner: corner, snap: false);
      c.cancelGesture();
      expect(c.document.toJson(), saved.toJson());
      c.undo();
      expect(c.document.toJson(), original.toJson());
      c.dispose();
    }
    for (final crop in [
      null,
      {},
      {'x': -.1, 'y': 0, 'width': 1, 'height': 1},
      {'x': 0, 'y': 0, 'width': 0, 'height': 1},
      {'x': .5, 'y': 0, 'width': 1, 'height': 1}
    ]) {
      expect(
          TicketTemplate.fromJson(
                  document().toJson()..['backgroundCrop'] = crop)
              .validate('wide'),
          contains('background'));
    }
  });
  test('cropped artwork resizes around its visible opposite corner', () {
    const image = Size(400, 200), crop = Rect.fromLTWH(.2, .1, .5, .6);
    for (var corner = 0; corner < 4; corner++) {
      final c = TicketLayoutController(document().withBackgroundCrop(crop));
      final visible = c.document.croppedBackgroundRect(image);
      final corners = [
        visible.topLeft,
        visible.topRight,
        visible.bottomRight,
        visible.bottomLeft
      ];
      final anchor = corners[(corner + 2) % 4];
      c.beginGesture();
      c.transformBackground(image, (corners[corner] - anchor) * .5,
          corner: corner, snap: false);
      c.endGesture();
      final next = c.document.croppedBackgroundRect(image);
      expect(next.width, closeTo(visible.width * 1.5, .000001));
      expect(
          ([
                    next.topLeft,
                    next.topRight,
                    next.bottomRight,
                    next.bottomLeft
                  ][(corner + 2) % 4] -
                  anchor)
              .distance,
          lessThan(.000001));
      expect(c.document.backgroundCrop, crop);
      c.undo();
      expect(c.document.croppedBackgroundRect(image), visible);
      c.dispose();
    }
  });
  testWidgets('moving cropped artwork does not paint discarded pixels',
      (tester) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
        .drawRect(const Rect.fromLTWH(0, 0, 8, 8), Paint()..color = Colors.red);
    final picture = recorder.endRecording();
    final source = (await tester.runAsync(() => picture.toImage(8, 8)))!;
    picture.dispose();
    final json = document().toJson();
    for (final element in json['elements']) {
      element['visible'] = false;
    }
    final doc = TicketTemplate.fromJson(json)
        .withBackgroundCrop(const Rect.fromLTWH(.25, .25, .5, .5));
    final c = TicketLayoutController(doc);
    final r = resources(background: source);
    final paintRecorder = ui.PictureRecorder();
    TicketLayoutPainter(c, r, {}, editBackground: true)
        .paint(Canvas(paintRecorder), doc.page);
    final resultPicture = paintRecorder.endRecording();
    final rendered = (await tester.runAsync(() =>
        resultPicture.toImage(doc.page.width.ceil(), doc.page.height.ceil())))!;
    final bytes = (await tester.runAsync(
        () => rendered.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    final full = doc.backgroundRect(const Size(8, 8)).shift(doc.area.topLeft);
    List<int> pixel(Offset point) {
      final i = (point.dy.floor() * rendered.width + point.dx.floor()) * 4;
      return bytes.buffer.asUint8List().sublist(i, i + 3);
    }

    expect(pixel(full.topLeft + Offset(full.width * .1, full.height * .1)),
        [230, 230, 230]);
    expect(pixel(full.center), [244, 67, 54]);
    rendered.dispose();
    resultPicture.dispose();
    r.dispose();
    c.dispose();
  });
  test('crop magnets snap to ticket edges and can be disabled', () {
    const image = Size(400, 200);
    final c = TicketLayoutController(document().withBackground(2, Offset.zero));
    final full = c.document.backgroundRect(image);
    c.beginGesture();
    c.cropBackground(image, Offset(2 - full.left, 0), corner: 0);
    expect(c.document.croppedBackgroundRect(image).left, closeTo(0, .000001));
    c.cancelGesture();
    c.beginGesture();
    c.cropBackground(image, Offset(2 - full.left, 0), corner: 0, snap: false);
    expect(c.document.croppedBackgroundRect(image).left, closeTo(2, .000001));
    c.cancelGesture();
    c.dispose();
  });
  test('paper and artwork edits retain element geometry and undo together', () {
    final original = document();
    final placed = original.withBackground(2, const Offset(-.3, .2));
    final restored = TicketTemplate.fromJson(placed.toJson());
    expect(restored.backgroundScale, 2);
    expect(restored.backgroundOffset, const Offset(-.3, .2));
    final ticket = placed.withPaper(true);
    expect(ticket.page, placed.area.size);
    expect(ticket.area.topLeft, Offset.zero);
    expect(ticket.withPaper(false).page, const Size(595.28, 841.89));
    expect(ticket.elements, placed.elements);
    expect(ticket.validate('wide'), isEmpty);
    final c = TicketLayoutController(original);
    c.beginGesture();
    c.changeBackground(2, const Offset(-.3, .2));
    c.changeBackground(3, const Offset(-.4, .2));
    c.endGesture();
    c.undo();
    expect(c.document.toJson(), original.toJson());
    c.redo();
    expect(c.document.backgroundScale, 3);
    c.beginGesture();
    c.changeBackground(.5, Offset.zero);
    c.cancelGesture();
    expect(c.document.backgroundScale, 3);
    for (final value in [
      null,
      {},
      {'scale': 0, 'x': 0, 'y': 0},
      {'scale': 1, 'x': 11, 'y': 0}
    ]) {
      final raw = original.toJson()..['backgroundTransform'] = value;
      expect(TicketTemplate.fromJson(raw).validate('wide'),
          contains('background'));
    }
    c.dispose();
  });
  testWidgets('editor follows dark theme and moves only artwork in image mode',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(TicketFontCatalog.load);
    final image = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
          File('test/fixtures/ticket_layout/background.png').readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      return image;
    });
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'wide',
            background: 'fixture.png',
            resources: resources(background: image),
            service: FakeService())));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark);
    final dynamic state = tester.state(find.byType(TicketLayoutEditor));
    final before =
        state.controller.document.elements.map((e) => e.toJson()).toList();
    final positionButton =
        find.widgetWithText(OutlinedButton, 'TicketLayout.positionImage'.tr());
    final cropButton =
        find.widgetWithText(OutlinedButton, 'TicketLayout.cropImage'.tr());
    final positionRect = tester.getRect(positionButton),
        cropRect = tester.getRect(cropButton);
    expect(cropRect.top - positionRect.bottom, greaterThanOrEqualTo(12));
    expect(cropRect.left, positionRect.left);
    expect(cropRect.width, positionRect.width);
    await tester.ensureVisible(find.text('TicketLayout.positionImage'.tr()));
    await tester.tap(find.text('TicketLayout.positionImage'.tr()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TicketLayoutCanvas), const Offset(40, 20));
    await tester.pumpAndSettle();
    expect(state.controller.document.backgroundOffset, isNot(Offset.zero));
    expect(state.controller.document.elements.map((e) => e.toJson()).toList(),
        before);
    state.controller.undo();
    expect(state.controller.document.backgroundOffset, Offset.zero);
    await tester.pumpAndSettle();
    final view =
        tester.widget<TicketLayoutCanvas>(find.byType(TicketLayoutCanvas));
    final box = view.controller.document
        .backgroundRect(Size(image!.width.toDouble(), image.height.toDouble()));
    final scene = box.bottomRight + view.controller.document.area.topLeft;
    final point = MatrixUtils.transformPoint(view.transform.value, scene) +
        tester.getTopLeft(find.byType(TicketLayoutCanvas));
    await tester.dragFrom(point, const Offset(-60, -30));
    await tester.pumpAndSettle();
    expect(view.controller.document.backgroundScale, lessThan(1));
    expect(view.controller.document.elements.map((e) => e.toJson()).toList(),
        before);
    view.controller.undo();
    expect(view.controller.document.backgroundScale, 1);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'TicketLayout.cropImage'.tr()));
    await tester.tap(
        find.widgetWithText(OutlinedButton, 'TicketLayout.cropImage'.tr()));
    await tester.pumpAndSettle();
    final cropPoint = MatrixUtils.transformPoint(view.transform.value, scene) +
        tester.getTopLeft(find.byType(TicketLayoutCanvas));
    await tester.dragFrom(cropPoint, const Offset(-60, -30));
    await tester.pumpAndSettle();
    expect(view.controller.document.backgroundCrop.width, lessThan(1));
    final thumbnail = tester.widget<CustomPaint>(find.byWidgetPredicate((w) =>
        w is CustomPaint && w.painter is TicketBackgroundPreviewPainter));
    expect((thumbnail.painter! as TicketBackgroundPreviewPainter).crop,
        view.controller.document.backgroundCrop);

    expect(view.controller.document.backgroundScale, 1);
    expect(view.controller.document.elements.map((e) => e.toJson()).toList(),
        before);
    await tester.tap(find.text('TicketLayout.resetCrop'.tr()));
    await tester.pumpAndSettle();
    expect(view.controller.document.backgroundCrop,
        const Rect.fromLTWH(0, 0, 1, 1));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('editor shows one font picker and a contrasting Apply action',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(TicketFontCatalog.load);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0D1323))),
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: FakeService())));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(TicketLayoutEditor));
    await tester.runAsync(() async {
      await state.fontCatalog;
    });
    state.controller.select('food');
    await tester.pumpAndSettle();
    expect(find.byType(FontFamilyPicker), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'TicketLayout.apply'.tr()));
    expect(button.onPressed, isNotNull);
    final buttonContext = tester
        .element(find.widgetWithText(FilledButton, 'TicketLayout.apply'.tr()));
    final style = button.defaultStyleOf(buttonContext);
    final background = style.backgroundColor!.resolve({})!;
    final foreground = style.foregroundColor!.resolve({})!;
    final light = foreground.computeLuminance();
    final dark = background.computeLuminance();
    expect((light + .05) / (dark + .05), greaterThanOrEqualTo(4.5));
    expect(
        background, isNot(Theme.of(buttonContext).appBarTheme.backgroundColor));
    expect(find.text('TicketLayout.elementFont'.tr()), findsNothing);
    expect(find.text('TicketLayout.downloadPdf'.tr()), findsNothing);
  });
  testWidgets(
      'font A/B race preserves draft, commits one undo step, isolates editors, blocks pending PDF and Apply',
      (tester) async {
    final catalog = jsonDecode(File('assets/fonts/ticket-font-catalog.json')
        .readAsStringSync())['fonts'] as List;
    final a = (catalog.firstWhere((f) => f['family'] == 'Roboto') as Map)
        .cast<String, dynamic>();
    final b = (catalog.firstWhere((f) => f['family'] == 'Russo One') as Map)
        .cast<String, dynamic>();
    final service = FakeService();
    service.fontResponses[a['id']] = Completer();
    service.fontResponses[b['id']] = Completer();
    final separate = TicketLayoutController(document());
    await tester.pumpWidget(MaterialApp(
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: service)));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(TicketLayoutEditor));
    final before = state.controller.document.toJson();
    final first = state.selectFont(a) as Future<void>;
    final second = state.selectFont(b) as Future<void>;
    await tester.pump();
    expect(state.fontBusy, true);
    expect(state.controller.document.toJson(), before);
    await state.preview();
    state.apply();
    expect(service.pdfCalls, 0);
    expect(find.byType(TicketLayoutEditor), findsOneWidget);
    TicketFontResource resource(Map asset) => TicketFontResource(
        asset['id'],
        asset['family'],
        400,
        resources().metrics,
        'TicketFont_${asset['id'].split(':').last}');
    service.fontResponses[b['id']]!.complete(resource(b));
    await second;
    await tester.pump();
    expect(state.controller.document.fontId, b['id']);
    expect(state.fontBusy, false);
    service.fontResponses[a['id']]!.complete(resource(a));
    await first;
    await tester.pump();
    expect(state.controller.document.fontId, b['id']);
    expect(separate.document.fontId, isNull);
    state.controller.undo();
    expect(state.controller.document.toJson(), before);
    expect(state.controller.canUndo, false);
    state.controller.redo();
    expect(state.controller.document.fontId, b['id']);
    await state.selectFont(a);
    expect(state.controller.document.fontId, a['id']);
    state.controller.select('ticketSymbol');
    state.controller.change(state.controller.selection.copyWith(locked: true));
    await state.selectFont(b, elementId: 'ticketSymbol');
    expect(state.controller.selection.fontId, isNull);
    final failed = Completer<TicketFontResource>();
    service.fontResponses[b['id']] = failed;
    final pending = state.selectFont(b) as Future<void>;
    final failure = expectLater(pending, throwsStateError);
    failed.completeError(StateError('offline'));
    await failure;
    expect(state.controller.document.fontId, a['id']);
    expect(state.fontBusy, false);
    final disposed = Completer<TicketFontResource>();
    service.fontResponses[b['id']] = disposed;
    final last = state.selectFont(b) as Future<void>;
    await tester.pumpWidget(const SizedBox());
    disposed.complete(resource(b));
    await last;
    expect(tester.takeException(), isNull);
    separate.dispose();
  });
  testWidgets('Cancel invalidates pending font and leaves original untouched',
      (tester) async {
    final asset = (jsonDecode(File('assets/fonts/ticket-font-catalog.json')
            .readAsStringSync())['fonts'] as List)
        .firstWhere((f) => f['family'] == 'Roboto') as Map;
    final service = FakeService();
    final loaded = Completer<TicketFontResource>();
    service.fontResponses[asset['id']] = loaded;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showDialog(
                    context: context,
                    builder: (_) => Dialog.fullscreen(
                        child: TicketLayoutEditor(
                            occasionId: 1,
                            type: 'named',
                            resources: resources(),
                            service: service))),
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(TicketLayoutEditor));
    final pending =
        state.selectFont(asset.cast<String, dynamic>()) as Future<void>;
    await state.cancel();
    await tester.pumpAndSettle();
    loaded.complete(TicketFontResource(asset['id'], asset['family'], 400,
        resources().metrics, 'TicketFont_${asset['id'].split(':').last}'));
    await pending;
    expect(find.byType(TicketLayoutEditor), findsNothing);
    expect(state.controller.document.fontId, isNull);
    expect(tester.takeException(), isNull);
  });
  test(
      'shared Dart registration reuses bytes for A/B/A across service instances',
      () async {
    final catalog = jsonDecode(File('assets/fonts/ticket-font-catalog.json')
        .readAsStringSync())['fonts'] as List;
    final calls = <String>[];
    Future<Map<String, dynamic>> transport(Map<String, dynamic> request) async {
      expect(request['mode'], 'font');
      expect(request['fontProtocol'], 2);
      final asset = catalog.firstWhere((f) => f['id'] == request['fontId']);
      calls.add(asset['id']);
      return {
        'id': asset['id'],
        'family': asset['family'],
        'weight': asset['weight'],
        'font': base64Encode(File(
                'test/fixtures/ticket_fonts/${asset['family'].replaceAll(' ', '-')}.ttf')
            .readAsBytesSync()),
        'metrics': fixture['metrics']
      };
    }

    final first = TicketLayoutService(transport: transport),
        second = TicketLayoutService(transport: transport);
    final a =
            catalog.firstWhere((f) => f['family'] == 'Roboto')['id'] as String,
        b = catalog.firstWhere((f) => f['family'] == 'Russo One')['id']
            as String;
    final concurrent = await Future.wait([first.font(1, a), second.font(1, a)]);
    expect(identical(concurrent[0], concurrent[1]), true);
    await first.font(1, b);
    expect(identical(await first.font(1, a), concurrent[0]), true);
    expect(calls, [a, b]);
    expect(concurrent[0].loaderName, 'TicketFont_${a.split(':').last}');
  });

  test(
      'template picker opens once per user and occasion, including after cancelling',
      () async {
    final preferences = <String, String>{};
    TicketLayoutService service() => TicketLayoutService(
        readPreference: (key) async => preferences[key],
        writePreference: (key, value) async {
          preferences[key] = value;
        });
    expect(await service().openTemplatePickerOnce(7, 'user', configured: false),
        isTrue);
    // A new service instance models leaving and reopening the settings page.
    expect(await service().openTemplatePickerOnce(7, 'user', configured: false),
        isFalse);
    expect(await service().openTemplatePickerOnce(8, 'user', configured: true),
        isFalse);
    expect(await service().openTemplatePickerOnce(8, 'user', configured: false),
        isFalse);
    expect(await service().openTemplatePickerOnce(9, 'user', configured: false),
        isTrue);
    expect(
        await service()
            .openTemplatePickerOnce(7, 'another-user', configured: false),
        isTrue);
  });
  test('custom QR colors use white-background contrast rather than a palette',
      () {
    for (final color in ['445566', '5A245A', '003F88', '767676']) {
      expect(ticketQrColorReadable(color), isTrue);
    }
    for (final color in ['777777', 'FFFFFF', 'FFFF00', 'oops']) {
      expect(ticketQrColorReadable(color), isFalse);
    }
  });
  testWidgets('mobile palettes align left and scroll on one row',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = TicketLayoutController(document())..select('occasionTitle');
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: false),
        home: Scaffold(
            body: SingleChildScrollView(
                child: TicketLayoutProperties(controller: c)))));
    await tester.tap(find.text('TicketLayout.color'.tr()));
    await tester.pumpAndSettle();
    final first = find.byTooltip('#000000').last;
    final last = find.byTooltip('#FFFFFF').last;
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(last).dy);
    expect(tester.getTopLeft(find.text('TicketLayout.usedColors'.tr())).dx,
        tester.getTopLeft(find.text('TicketLayout.basicColors'.tr())).dx);
    final row = find
        .ancestor(of: last, matching: find.byType(SingleChildScrollView))
        .first;
    final previousX = tester.getCenter(last).dx;
    await tester.drag(row, const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(tester.getCenter(last).dx, lessThan(previousX));
    await tester.tap(last);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'FFFFFF');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('palette paints its colors in Material 2 and 3, light and dark',
      (tester) async {
    for (final material3 in [false, true]) {
      for (final brightness in Brightness.values) {
        final c = TicketLayoutController(document())..select('occasionTitle');
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
                theme:
                    ThemeData(useMaterial3: material3, brightness: brightness),
                home: Scaffold(
                    body: SingleChildScrollView(
                        child: TicketLayoutProperties(controller: c))))));
        await tester.tap(find.text('TicketLayout.color'.tr()));
        await tester.pumpAndSettle();
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        for (final hex in ticketQrColors) {
          final swatch = find.byTooltip('#$hex').last;
          await tester.ensureVisible(swatch);
          await tester.pumpAndSettle();
          final image = (await tester.runAsync(() => boundary.toImage()))!;
          final pixels = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
          final rect = tester.getRect(swatch);
          final point =
              boundary.globalToLocal(Offset(rect.center.dx, rect.top + 12));
          final offset =
              (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
          final rgb = (pixels.getUint8(offset) << 16) |
              (pixels.getUint8(offset + 1) << 8) |
              pixels.getUint8(offset + 2);
          expect(rgb, int.parse(hex, radix: 16),
              reason: '$hex material3=$material3 brightness=$brightness');
          image.dispose();
        }
        await tester.tap(find.byTooltip('#17365D').last);
        await tester.pump();
        expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '17365D');
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    }
  });
  testWidgets('text and QR share the color picker and HEX entry',
      (tester) async {
    for (final binding in ['qr', 'occasionTitle']) {
      final c = TicketLayoutController(document())..select(binding);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFF204060), BlendMode.src);
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(8, 8)))!;
      picture.dispose();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: TicketLayoutProperties(
                      controller: c, backgroundImage: image)))));
      await tester.tap(find.text(binding == 'qr'
          ? 'TicketLayout.qrColors'.tr()
          : 'TicketLayout.color'.tr()));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byType(ColorPicker), findsOneWidget);
      expect(find.text('TicketLayout.usedColors'.tr()), findsOneWidget);
      expect(find.text('TicketLayout.imageColors'.tr()), findsOneWidget);
      await tester.tap(find.byTooltip('#204060'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '204060');
      await tester.enterText(find.byType(TextField), 'FFFFFF');
      await tester.pump();
      final apply =
          find.widgetWithText(FilledButton, 'TicketLayout.apply'.tr());
      expect(tester.widget<FilledButton>(apply).onPressed == null,
          binding == 'qr');
      await tester.enterText(find.byType(TextField), '445566');
      await tester.pump();
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(c.selection!.color, '445566');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      image.dispose();
    }
  });
  test('styled text fitting matches the PDF renderer fixtures', () {
    final cases = jsonDecode(
        File('test/fixtures/ticket_layout/text-emphasis.json')
            .readAsStringSync()) as List;
    final r = resources();
    for (final item in cases) {
      final e = TicketElement.fromJson(item['element']);
      final fit = fitTicketText(item['text'], e, r.metrics);
      expect(fit.size, item['expected']['size']);
      expect(fit.lines, item['expected']['lines']);
      for (var i = 0; i < fit.widths.length; i++) {
        expect(fit.widths[i], closeTo(item['expected']['widths'][i], .000001));
      }
    }
    r.dispose();
  });
  test('group movement preserves relative placement, bounds and one undo step',
      () {
    final c = TicketLayoutController(document());
    c.select('qr');
    c.select('ticketSymbol', additive: true);
    final before = {for (final e in c.selections) e.id: e.box};
    c.beginGesture();
    c.move(const Offset(-10, -10), snap: false);
    c.move(const Offset(-1000, -1000), snap: false);
    c.endGesture();
    final shifts =
        c.selections.map((e) => e.box.topLeft - before[e.id]!.topLeft).toSet();
    expect(shifts.length, 1);
    for (final e in c.selections) {
      expect(e.box.left, greaterThanOrEqualTo(0));
      expect(e.box.top, greaterThanOrEqualTo(0));
    }
    final q = c.document.elements.firstWhere((e) => e.binding == 'qr');
    expect(q.box.width, q.box.height);
    c.undo();
    expect(c.document.toJson(), document().toJson());
    expect(c.canUndo, isFalse);
    c.redo();
    expect(c.document.toJson(), isNot(document().toJson()));
    c.dispose();
  });
  testWidgets('selection marquee and shift-click move QR and code together',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: FakeService())));
    await tester.pumpAndSettle();
    final state =
        tester.state<TicketLayoutCanvasState>(find.byType(TicketLayoutCanvas));
    final c = state.widget.controller;
    Offset screen(Offset p) =>
        tester.getTopLeft(find.byType(InteractiveViewer)) +
        MatrixUtils.transformPoint(
            state.widget.transform.value, c.document.area.topLeft + p);
    final qr = c.document.elements.firstWhere((e) => e.binding == 'qr');
    final code =
        c.document.elements.firstWhere((e) => e.binding == 'ticketSymbol');
    await tester.tapAt(screen(qr.box.center));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(screen(code.box.center));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(c.selectedIds, {'qr', 'ticketSymbol'});
    final drag = await tester.startGesture(screen(qr.box.center));
    await drag.moveBy(const Offset(-5, -5));
    await drag.up();
    await tester.pump();
    expect(c.selectedIds, {'qr', 'ticketSymbol'});
    expect(c.document.elements.firstWhere((e) => e.id == qr.id).box,
        isNot(qr.box));
    c.undo();
    c.select(null);
    await tester.pump();
    final bounds = qr.box.expandToInclude(code.box).inflate(2);
    final marquee = await tester.startGesture(screen(bounds.topLeft));
    await marquee.moveTo(screen(bounds.bottomRight));
    await marquee.up();
    await tester.pump();
    expect(c.selectedIds, containsAll(['qr', 'ticketSymbol']));
    await tester.tap(find.byTooltip('TicketLayout.viewOptions'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.multiSelect'.tr()));
    await tester.pumpAndSettle();
    final previous = c.document;
    final touchDrag = await tester.startGesture(screen(qr.box.center));
    await touchDrag.moveBy(const Offset(-8, -8));
    await touchDrag.up();
    await tester.pump();
    expect(c.selectedIds, containsAll(['qr', 'ticketSymbol']));
    expect(c.document.toJson(), isNot(previous.toJson()));
  });
  testWidgets('text emphasis round trips, updates the editor and supports undo',
      (tester) async {
    final c = TicketLayoutController(document())..select('occasionTitle');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TicketLayoutProperties(controller: c)))));
    for (final style in ['bold', 'italic', 'underline']) {
      await tester.tap(find.byTooltip('TicketLayout.$style'.tr()));
      await tester.pump();
      expect(c.selection!.toJson()['style'][style], isTrue);
    }
    final restored = TicketElement.fromJson(c.selection!.toJson());
    expect(restored.bold && restored.italic && restored.underline, isTrue);
    c.undo();
    expect(c.selection!.underline, isFalse);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  test('A4 template stays printable in the legacy named slot', () {
    final layouts = jsonDecode(
        File('test/fixtures/ticket_layout/layouts.json').readAsStringSync());
    final layout =
        TicketTemplate.fromJson(layouts['valid'][0]['templates']['wide']);
    expect(layout.page, const Size(595.28, 841.89));
    expect(layout.validate('named'), isEmpty);
    expect(layout.fitPageToTicket, isFalse);
  });

  testWidgets('settings expose templates without a second type selector',
      (tester) async {
    for (final type in <String?>['named', 'wide', null]) {
      final feature = TicketFeature(code: 'ticket', ticketType: type);
      final service = SettingsService();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: TicketSettings(
                      key: UniqueKey(),
                      feature: feature,
                      occasionId: 7,
                      service: service)))));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('TicketLayout.edit'.tr()), findsOneWidget);
      final paint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((paint) => paint.painter is TicketLayoutPainter);
      expect(paint.size, document().area.size);
      expect((paint.painter as TicketLayoutPainter).cropToTicket, isTrue);
      expect(service.resolvedType, type == 'named' ? 'named' : 'wide');
      expect(feature.ticketType, type);
      expect(feature.layout, isNull);
    }
  });

  testWidgets(
      'returning from the editor keeps its button ready while only changed thumbnails reload',
      (tester) async {
    RightsService.occasionLinkModelNotifier.value =
        OccasionLinkModel(unitUser: OccasionUserModel(isEditor: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
    final service = SettingsService();
    final feature = TicketFeature(code: 'ticket', ticketType: 'named');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TicketSettings(
                    feature: feature, occasionId: 7, service: service)))));
    await tester.pumpAndSettle();
    final edit = find.widgetWithText(FilledButton, 'TicketLayout.edit'.tr());
    expect(service.resolveCalls, 1);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TicketLayoutEditor), findsOneWidget,
        reason: 'system back must not dismiss a clean editor');
    await tester.tap(find.byTooltip('TicketLayout.cancel'.tr()).first);
    await tester.pumpAndSettle();
    expect(service.resolveCalls, 2,
        reason: 'cancel does not reload the thumbnail');
    expect(tester.widget<FilledButton>(edit).onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final editorController = tester
        .widget<TicketLayoutCanvas>(find.byType(TicketLayoutCanvas))
        .controller;
    editorController.replace(document().withFont('roboto'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TicketLayoutEditor), findsOneWidget);
    expect(find.text('TicketLayout.discard'.tr()), findsNothing,
        reason:
            'back gestures must not interrupt editing with a discard prompt');
    service.pendingResolve = Completer<TicketLayoutResources>();
    final changed = document().withFont('roboto');
    Navigator.of(tester.element(find.byType(TicketLayoutEditor)))
        .pop(TicketLayoutResult(changed, null));
    await tester.pumpAndSettle();
    expect(service.resolveCalls, 4);
    expect(tester.widget<FilledButton>(edit).onPressed, isNotNull,
        reason: 'thumbnail refresh must not block editing');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    service.pendingResolve!.complete(resources());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('artwork selection and geometry share undo history', () {
    final original = document();
    final controller = TicketLayoutController(original, artworkKey: 'cream');
    controller.replace(original, artworkKey: 'forest');
    expect(controller.dirty, isTrue);
    final element = controller.document.elements.first;
    controller.change(element.copyWith(locked: !element.locked));
    controller.undo();
    expect(controller.artworkKey, 'forest');
    expect(controller.document.toJson(), original.toJson());
    controller.undo();
    expect(controller.artworkKey, 'cream');
    expect(controller.dirty, isFalse);
    controller.redo();
    expect(controller.artworkKey, 'forest');
    controller.redo();
    expect(controller.document.elements.first.locked, !element.locked);
    controller.dispose();
  });
  test('portrait millimeter resize keeps QR dimensions exactly square in JSON',
      () {
    final catalog = jsonDecode(
        File('test/fixtures/ticket_layout/historical/catalog.json')
            .readAsStringSync()) as List;
    final portrait = TicketTemplate.fromJson(
        catalog.firstWhere((v) => v['id'] == 'portrait')['template']);
    final resized =
        portrait.resizeArea(Size(90 * (72 / 25.4), 160 * (72 / 25.4)));
    expect(resized.validate('wide'), isEmpty);
    expect(resized.page, resized.area.size);
    expect(resized.toJson()['pageFit'], 'ticket');
    final q = resized
        .toJson()['elements']
        .firstWhere((e) => e['binding'] == 'qr')['box'];
    expect(q['width'], q['height']);
  });
  testWidgets('unchanged dimensions preserve exact geometry without rounding',
      (tester) async {
    final template =
        TicketTemplate.fromJson(fixture['presetsByType']['wide']['classic']);
    TicketTemplate? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showDialog<TicketTemplate>(
                          context: context,
                          builder: (_) => TicketDimensionsDialog(
                              document: template, type: 'wide'));
                    },
                    child: const Text('dimensions'))))));
    await tester.tap(find.text('dimensions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.apply'.tr()));
    await tester.pumpAndSettle();
    expect(result!.toJson(), template.toJson());
  });
  testWidgets(
      'dimension edits preview immediately and cancel restores the ticket',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: FakeService())));
    await tester.pumpAndSettle();
    final view =
        tester.widget<TicketLayoutCanvas>(find.byType(TicketLayoutCanvas));
    final original = view.controller.document;
    final resized = original.resizeArea(original.area.size * .95);
    view.controller.replace(resized);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.canvasSize'.tr()).first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'TicketLayout.widthMm'.tr()), '70');
    await tester.pumpAndSettle();
    expect(view.controller.document.area.width, closeTo(70 * 72 / 25.4, .001));
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('TicketLayout.cancel'.tr())));
    await tester.pumpAndSettle();
    expect(view.controller.document.toJson(), resized.toJson());
    view.controller.undo();
    expect(view.controller.document.toJson(), original.toJson());
    view.controller.replace(resized);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.canvasSize'.tr()).first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'TicketLayout.widthMm'.tr()), '70');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('TicketLayout.apply'.tr())));
    await tester.pumpAndSettle();
    expect(view.controller.document.area.width, closeTo(70 * 72 / 25.4, .001));
    view.controller.undo();
    expect(view.controller.document.toJson(), resized.toJson());
  });
  testWidgets('new ticket opens the template picker first', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: FakeService(),
            showTemplatePicker: true)));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('TicketLayout.style_compact'.tr()), findsOneWidget);
  });
  test('canvas resize preserves square QR and shares geometry undo', () {
    final original = document();
    final resized = original
        .resizeArea(Size(original.area.width * .9, original.area.height * .9));
    expect(resized.validate('named'), isEmpty);
    expect(resized.page, original.page);
    final qr = resized.elements.firstWhere((e) => e.binding == 'qr');
    expect(qr.box.width, qr.box.height);
    final controller = TicketLayoutController(original)..replace(resized);
    controller.undo();
    expect(controller.document.toJson(), original.toJson());
    expect(original.resizeArea(const Size(800, 900)).validate('named'),
        isNotEmpty);
    controller.dispose();
  });
  testWidgets(
      'text color picker applies one undoable edit and cancel preserves color',
      (tester) async {
    final controller = TicketLayoutController(document())..select('orderName');
    final before = controller.selection!.color;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TicketLayoutProperties(controller: controller))));
    await tester.tap(find.text('TicketLayout.color'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(ColorPicker), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'AA1122');
    await tester.tap(find.text('TicketLayout.cancel'.tr()));
    await tester.pumpAndSettle();
    expect(controller.selection!.color, before);
    await tester.tap(find.text('TicketLayout.color'.tr()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'AA1122');
    await tester.tap(find.text('TicketLayout.apply'.tr()));
    await tester.pumpAndSettle();
    expect(controller.selection!.color, 'AA1122');
    controller.undo();
    expect(controller.selection!.color, before);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  setUpAll(() async {
    // Load the same catalog used by the app. An uninitialized translator returns
    // raw keys and floods otherwise passing widget tests with missing-key warnings.
    Localization.load(const Locale('cs'),
        translations: Translations(
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>));
    final bytes =
        await File('supabase/functions/_shared/ticket-assets/font.ttf')
            .readAsBytes();
    await (FontLoader('TicketLayoutFont')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });
  test('shared valid and invalid geometry fixtures agree with Dart', () {
    final fixtures = jsonDecode(
        File('test/fixtures/ticket_layout/layouts.json').readAsStringSync());
    for (final layout in fixtures['valid']) {
      for (final entry in (layout['templates'] as Map).entries) {
        final d = TicketTemplate.fromJson(entry.value);
        expect(d.validate(entry.key), isEmpty);
        expect(d.toJson(), entry.value);
      }
    }
    final allowed = (jsonDecode(File('assets/fonts/ticket-font-catalog.json')
            .readAsStringSync())['fonts'] as List)
        .map((f) => f['id'] as String)
        .toSet();
    for (final entry in (fixtures['invalid'] as Map).entries)
      expect(
          () => validateTicketLayout(
              (entry.value as Map).cast<String, dynamic>(),
              allowedFontIds: allowed),
          throwsFormatException,
          reason: entry.key);
  });
  test(
      'a drag is one undo step with immediate notifications and zoom independent coordinates',
      () {
    final c = TicketLayoutController(document())..select('qr');
    var notifications = 0;
    c.addListener(() => notifications++);
    final before = c.selection!.box;
    c.beginGesture();
    c.move(const Offset(3, 1), zoom: 2, snap: false);
    expect(c.selection!.box, before.shift(const Offset(3, 1)));
    expect(notifications, greaterThan(0));
    expect(c.canUndo, isFalse);
    c.move(const Offset(2, 1), zoom: .5, snap: false);
    c.endGesture();
    c.undo();
    expect(c.selection!.box, before);
    c.redo();
    expect(c.selection!.box, before.shift(const Offset(5, 2)));
    c.dispose();
  });
  test(
      'QR resize stays square, text resize changes font, locked elements do not move',
      () {
    final c = TicketLayoutController(document())..select('qr');
    c.beginGesture();
    c.resize(const Offset(10, 10));
    c.endGesture();
    expect(c.selection!.box.width, c.selection!.box.height);
    expect(c.selection!.box.width, greaterThan(100));
    c.select('occasionTitle');
    final size = c.selection!.fontSize;
    c.resize(const Offset(10, 10));
    expect(c.selection!.fontSize, greaterThan(size));
    c.resize(const Offset(-1000, -1000));
    expect(
        c.selection!.fontSize, greaterThanOrEqualTo(c.selection!.minFontSize));
    c.change(c.selection!.copyWith(locked: true));
    final b = c.selection!.box;
    c.move(const Offset(10, 10));
    expect(c.selection!.box, b);
    c.dispose();
  });
  test(
      'draft baseline and serialization survive failure and become clean only after success',
      () {
    final f = TicketFeature.fromJson({
      'code': 'ticket',
      'is_enabled': true,
      'layout': {
        'schemaVersion': 1,
        'templates': {'named': document().toJson()}
      }
    });
    expect(f.layoutChange, isNull);
    final expected = copyTicketJson(f.layout!);
    f.layout!['templates']['named']['elements'][0]['box']['x'] = 70;
    expect(f.layoutChange!['expected'], expected);
    expect(f.toJson().containsKey('ticket_layout_change'), isFalse);
    expect(f.layoutChange, isNotNull);
    f.markLayoutSaved();
    expect(f.layoutChange, isNull);
  });
  test(
      'long text and missing data use bounded boxes without leaking hidden notes',
      () {
    final d = document();
    final e = d.elements.firstWhere((e) => e.binding == 'occasionTitle');
    final r = resources();
    final fit = fitTicketText(
        List.filled(50, 'PřílišDlouhéSlovoBezMezer').join(), e, r.metrics);
    expect(fit.overflow, isTrue);
    expect(fit.lines.last.endsWith('…'), isTrue);
    expect(fit.widths.every((w) => w <= e.box.width), isTrue);
    r.dispose();
  });
  testWidgets('opening, live drag, resize, zoom and apply make zero PDF calls',
      (tester) async {
    final service = FakeService();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => Dialog.fullscreen(
                            child: TicketLayoutEditor(
                                occasionId: 1,
                                type: 'named',
                                resources: resources(),
                                service: service))),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(service.pdfCalls, 0);
    final state =
        tester.state<TicketLayoutCanvasState>(find.byType(TicketLayoutCanvas));
    final c = state.widget.controller;
    Offset screen(Offset p) =>
        tester.getTopLeft(find.byType(InteractiveViewer)) +
        MatrixUtils.transformPoint(
            state.widget.transform.value, c.document.area.topLeft + p);
    final original =
        c.document.elements.firstWhere((e) => e.binding == 'qr').box;
    final gesture = await tester.startGesture(screen(original.center));
    await gesture.moveBy(const Offset(8, -4));
    await tester.pump();
    expect(c.selection!.box, isNot(original),
        reason: 'canvas updates before pointer up');
    await gesture.up();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(c.selection!.box, original);
    c.redo();
    final qr = c.selection!.box;
    await tester.dragFrom(screen(qr.bottomRight), const Offset(8, 8));
    await tester.pump();
    expect(c.selection!.box.width, c.selection!.box.height);
    state.zoomAt(1.2);
    await tester.pump();
    expect(service.pdfCalls, 0);
    c.undo();
    c.undo();
    await tester.pump();
    final beforeTouch = c.document.toJson();
    final touch = await tester.startGesture(screen(c.selection!.box.center),
        pointer: 11, kind: PointerDeviceKind.touch);
    await touch.moveBy(const Offset(5, 0));
    final second = await tester.startGesture(
        screen(c.selection!.box.center + const Offset(45, 0)),
        pointer: 12,
        kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(c.document.toJson(), beforeTouch,
        reason: 'second touch cancels the element drag before pinch');
    await touch.up();
    await second.up();
    await tester.pump();
    await tester.tap(find.text('TicketLayout.apply'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(TicketLayoutEditor), findsNothing);
    expect(service.pdfCalls, 0);
  });
  testWidgets(
      'PDF request starts only from its explicit button and failure keeps draft',
      (tester) async {
    final service = FakeService();
    await tester.pumpWidget(MaterialApp(
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: service)));
    await tester.pumpAndSettle();
    expect(service.pdfCalls, 0);
    await tester.tap(find.byTooltip('TicketLayout.pdf'.tr()));
    await tester.pumpAndSettle();
    expect(service.pdfCalls, 1);
    expect(find.byType(TicketLayoutCanvas), findsOneWidget);
  });
  test('conflict refresh preserves draft for an explicit restoration', () {
    final f = TicketFeature.fromJson({
      'code': 'ticket',
      'is_enabled': true,
      'layout': {
        'schemaVersion': 1,
        'templates': {'named': document().toJson()}
      }
    });
    f.layout!['templates']['named']['elements'][0]['style']['color'] = '17365D';
    final local = copyTicketJson(f.layout!);
    final saved = {
      'schemaVersion': 1,
      'templates': {'named': document().toJson()}
    };
    f.loadSavedLayout(saved);
    expect(f.layoutChange, isNull);
    expect(f.conflictDraft, local);
    f.restoreConflictDraft();
    expect(f.layoutChange!['expected'], saved);
    expect(f.layoutChange!['next'], local);
  });
  test('gesture cancellation restores geometry without an undo entry', () {
    final c = TicketLayoutController(document())..select('qr');
    final initial = c.selection!.box;
    c.beginGesture();
    c.move(const Offset(4, 2), snap: false);
    c.cancelGesture();
    expect(c.selection!.box, initial);
    expect(c.canUndo, isFalse);
    c.dispose();
  });
  testWidgets('a PDF response for an edited draft is discarded',
      (tester) async {
    final service = FakeService()..pending = Completer();
    await tester.pumpWidget(MaterialApp(
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('TicketLayout.pdf'.tr()));
    await tester.pump();
    final c = tester
        .widget<TicketLayoutCanvas>(find.byType(TicketLayoutCanvas))
        .controller;
    c.select('qr');
    c.change(c.selection!.copyWith(color: '17365D'));
    service.pending!.complete((bytes: Uint8List(0), warnings: <String>[]));
    await tester.pumpAndSettle();
    expect(service.pdfCalls, 1);
    expect(tester.takeException(), isNull);
    expect(c.selection!.color, '17365D');
  });
  test('snapping can be disabled and slow drags escape magnets', () {
    final c = TicketLayoutController(document())..select('qr');
    c.beginGesture();
    c.move(const Offset(12.9, 0), gridStep: 10);
    expect(c.selection!.box.left, 60);
    expect(c.guideX, 60);
    for (var i = 0; i < 15; i++) {
      c.move(const Offset(1, 0), gridStep: 10);
    }
    expect(c.selection!.box.left, greaterThan(70));
    c.endGesture();
    expect(c.guideX, isNull);
    c.undo();
    c.beginGesture();
    c.move(const Offset(12.9, 0), snap: false, gridStep: 10);
    expect(c.selection!.box.left, closeTo(62.9, 1 / 1024));
    expect(c.guideX, isNull);
    c.endGesture();
    c.dispose();
  });
  testWidgets(
      'the ticket remains on screen at extreme pan positions and zoom levels',
      (tester) async {
    final c = TicketLayoutController(document()),
        transform = TransformationController();
    await tester.pumpWidget(MaterialApp(
        home: SizedBox(
            width: 500,
            height: 450,
            child: TicketLayoutCanvas(
                controller: c,
                resources: resources(),
                data: resources().scenarios['normal']!,
                transform: transform))));
    await tester.pumpAndSettle();
    final state =
        tester.state<TicketLayoutCanvasState>(find.byType(TicketLayoutCanvas));
    for (final scale in [.5, 4.0]) {
      for (final offset in [-10000.0, 10000.0]) {
        final matrix = Matrix4.identity()
          ..translateByDouble(offset, offset, 0, 1)
          ..scaleByDouble(scale, scale, 1, 1);
        transform.value = matrix;
        final b = MatrixUtils.transformRect(transform.value, c.document.area);
        final viewport = Offset.zero & state.viewportSize;
        expect(b.overlaps(viewport), isTrue);
        if (b.width < viewport.width - 32) {
          expect(b.left, greaterThanOrEqualTo(15.99),
              reason:
                  'scale=$scale matrix=${transform.value} area=${c.document.area}');
          expect(b.right, lessThanOrEqualTo(viewport.right - 15.99));
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    transform.dispose();
  });
  testWidgets(
      'style selection and grid controls change the local draft without PDF',
      (tester) async {
    final service = FakeService();
    await tester.pumpWidget(MaterialApp(
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('TicketLayout.viewOptions'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.grid'.tr()));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('TicketLayout.viewOptions'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.snap'.tr()));
    await tester.pump();
    final view =
        tester.widget<TicketLayoutCanvas>(find.byType(TicketLayoutCanvas));
    expect(view.grid, isTrue);
    expect(view.snap, isFalse);
    await tester.tap(find.text('TicketLayout.styles'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.style_compact'.tr()));
    await tester.pumpAndSettle();
    expect(view.controller.document.toJson(), fixture['presets']['compact']);
    expect(view.controller.canUndo, isTrue);
    view.controller.undo();
    expect(view.controller.document.toJson(), fixture['template']);
    expect(service.pdfCalls, 0);
  });
  testWidgets(
      'double click restores the template font size as one undoable change',
      (tester) async {
    final c = TicketLayoutController(document())..select('occasionTitle');
    final initial = c.selection!.fontSize;
    c.change(c.selection!.copyWith(fontSize: 20));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body:
                TicketLayoutProperties(controller: c, defaults: document()))));
    final slider = find.byType(Slider).first;
    final point = tester.getCenter(slider);
    await tester.tapAt(point);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    expect(c.selection!.fontSize, initial);
    c.undo();
    expect(c.selection!.fontSize, 20);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('phone editor keeps canvas usable and opens selected properties',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: FakeService(),
            showTemplatePicker: true)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('TicketLayout.style_classic'.tr()));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TicketLayoutCanvas)).height,
        greaterThan(400));
    await tester.tap(find.text('TicketLayout.elements'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.occasionTitle'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(TicketLayoutProperties).hitTestable(), findsOneWidget);
    expect(find.text('TicketLayout.color'.tr()).hitTestable(), findsOneWidget);
    await tester.tap(find.text('TicketLayout.color'.tr()));
    await tester.pumpAndSettle();
    expect(find.byType(ColorPicker), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('text alignment controls update selected text and support undo',
      (tester) async {
    final c = TicketLayoutController(document())..select('ticketSymbol');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TicketLayoutProperties(controller: c)))));
    for (final align in ['left', 'right', 'center']) {
      await tester.tap(find.byTooltip('TicketLayout.$align'.tr()));
      await tester.pump();
      expect(c.selection!.align, align);
    }
    c.undo();
    expect(c.selection!.align, 'right');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  test(
      'imported appearance round trips and compact rows retain editable geometry',
      () {
    final source = jsonDecode(File('test/fixtures/ticket_layout/imported.json')
        .readAsStringSync()) as Map;
    final t = TicketTemplate.fromJson(source);
    expect(t.validate('wide'), isEmpty);
    expect(t.toJson()['qrAppearance'], source['qrAppearance']);
    expect(t.toJson()['flow'], source['flow']);
    expect(TicketTemplate.fromJson(t.toJson()).validate('wide'), isEmpty);
    expect(t.font, 'robotoSlab');
    final data = <String, String?>{
      'food': 'Večeře',
      'price': 'Cena',
      'spotGroup': 'Stůl'
    };
    final visible = t.positionedElements(data);
    final food = visible.firstWhere((e) => e.binding == 'food');
    final price = visible.firstWhere((e) => e.binding == 'price');
    expect(price.box.top - food.box.top,
        closeTo(t.appearance['flowStep'] as double, .001));
    final c = TicketLayoutController(t)..select('price');
    c.move(const Offset(0, 5), snap: false);
    expect(
        c.document
            .positionedElements(data)
            .firstWhere((e) => e.binding == 'price')
            .box
            .top,
        closeTo(price.box.top + 5, .001));
    c.replace(c.document.withFont('roboto'));
    expect(c.document.fontId, legacyTicketFontIds['roboto']);
    c.undo();
    expect(c.document.font, 'robotoSlab');
    final resized = t.resizeArea(Size(t.area.width * .9, t.area.height * .9));
    expect(resized.appearance['flowStep'],
        closeTo((t.appearance['flowStep'] as num) * .9, .001));
    c.dispose();
  });

  testWidgets(
      'sidebar eyes toggle visibility without changing selection and support undo',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: FakeService())));
    await tester.pumpAndSettle();
    final c = tester
        .widget<TicketLayoutCanvas>(find.byType(TicketLayoutCanvas))
        .controller;
    c.select('logo');
    await tester.pump();
    final titleRow =
        find.widgetWithText(ListTile, 'TicketLayout.occasionTitle'.tr());
    final eye =
        find.descendant(of: titleRow, matching: find.byType(IconButton));
    bool titleVisible() =>
        c.document.elements.singleWhere((e) => e.id == 'occasionTitle').visible;
    await tester.tap(eye);
    await tester.pump();
    expect(titleVisible(), isFalse);
    expect(c.selectedIds, {'logo'});
    expect(
        find.descendant(
            of: titleRow, matching: find.byIcon(Icons.visibility_off)),
        findsOneWidget);
    c.undo();
    await tester.pump();
    expect(titleVisible(), isTrue);
    await tester.tap(eye);
    await tester.pump();
    await tester.tap(eye);
    await tester.pump();
    expect(titleVisible(), isTrue);
    await tester
        .tap(find.descendant(of: titleRow, matching: find.byType(Text)));
    await tester.pump();
    expect(c.selectedIds, {'occasionTitle'});
    for (final binding in ['qr', 'ticketSymbol']) {
      final button = find.descendant(
          of: find.widgetWithText(ListTile, 'TicketLayout.$binding'.tr()),
          matching: find.byType(IconButton));
      expect(tester.widget<IconButton>(button).onPressed, isNull);
    }
  });

  testWidgets(
      'editor history shortcuts work from properties and preserve text field history',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: TicketLayoutEditor(
            occasionId: 1,
            type: 'named',
            resources: resources(),
            service: FakeService())));
    await tester.pumpAndSettle();
    final c = tester
        .widget<TicketLayoutCanvas>(find.byType(TicketLayoutCanvas))
        .controller;
    c.select('occasionTitle');
    await tester.pump();
    final original = c.selection!.bold;
    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pump();
    Focus.of(tester.element(find.byIcon(Icons.format_bold))).requestFocus();
    await tester.pump();
    Future<void> shortcut(LogicalKeyboardKey modifier, LogicalKeyboardKey key,
        {bool shift = false}) async {
      await tester.sendKeyDownEvent(modifier);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    expect(c.selection!.bold, !original);
    await shortcut(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ);
    expect(c.selection!.bold, original);
    await shortcut(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyY);
    expect(c.selection!.bold, !original);
    await shortcut(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyZ);
    expect(c.selection!.bold, original);
    await shortcut(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyZ,
        shift: true);
    expect(c.selection!.bold, !original);
    await tester.tap(find.text('TicketLayout.color'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '123456');
    await shortcut(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ);
    expect(c.selection!.bold, !original);
    await tester.tap(find.text('TicketLayout.cancel'.tr()));
    await tester.pumpAndSettle();
    await shortcut(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyZ);
    expect(c.selection!.bold, original);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'QR foreground and background edit atomically on mobile with contrast and undo',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = TicketLayoutController(document())..select('qr');
    final initial = c.document.toJson();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TicketLayoutProperties(controller: c)))));
    await tester.tap(find.text('TicketLayout.qrColors'.tr()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'FFFFFF');
    await tester.pump();
    final apply = find.widgetWithText(FilledButton, 'TicketLayout.apply'.tr());
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    final background = find.text('TicketLayout.qrBackground'.tr());
    await tester.ensureVisible(background);
    await tester.tap(background);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '17365D');
    await tester.pump();
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    expect(c.document.toJson(), initial);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(c.selection!.color, 'FFFFFF');
    expect(c.document.qrAppearance['background'], '17365D');
    expect(c.document.qrAppearance['opacity'], 1);
    expect(c.document.validate('named'), isEmpty);
    expect(
        TicketTemplate.fromJson(c.document.toJson()).qrAppearance['background'],
        '17365D');
    c.undo();
    await tester.pumpAndSettle();
    expect(c.document.toJson(), initial);
    await tester.tap(find.text('TicketLayout.qrColors'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('TicketLayout.swapColors'.tr()));
    await tester.pump();
    await tester.tap(find.text('TicketLayout.cancel'.tr()));
    await tester.pumpAndSettle();
    expect(c.document.toJson(), initial);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
