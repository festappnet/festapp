import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
TicketLayoutResources resources() => TicketLayoutResources(
    template: document(),
    preset: document(),
    presets: (fixture['presets'] as Map).map((key, value) =>
        MapEntry(key as String, TicketTemplate.fromJson(value))),
    scenarios: (fixture['scenarios'] as Map).map(
        (k, v) => MapEntry(k as String, (v as Map).cast<String, String?>())),
    metrics: TicketFontMetrics.fromJson(fixture['metrics']),
    qrSize: fixture['qrMatrix']['size'],
    qrModules: (fixture['qrMatrix']['data'] as List).cast<int>());

class SettingsService extends TicketLayoutService {
  String? resolvedType;
  @override
  Future<TicketLayoutResources> resolve(int occasionId, String type,
      Map<String, dynamic>? layout, String? background) async {
    resolvedType = type;
    return resources();
  }
}

class FakeService extends TicketLayoutService {
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
  test('template picker opens once per user and occasion, including after cancelling', () async {
    final preferences = <String, String>{};
    TicketLayoutService service() => TicketLayoutService(
        readPreference: (key) async => preferences[key],
        writePreference: (key, value) async { preferences[key] = value; });
    expect(await service().openTemplatePickerOnce(7, 'user', configured: false), isTrue);
    // A new service instance models leaving and reopening the settings page.
    expect(await service().openTemplatePickerOnce(7, 'user', configured: false), isFalse);
    expect(await service().openTemplatePickerOnce(8, 'user', configured: true), isFalse);
    expect(await service().openTemplatePickerOnce(8, 'user', configured: false), isFalse);
    expect(await service().openTemplatePickerOnce(9, 'user', configured: false), isTrue);
    expect(await service().openTemplatePickerOnce(7, 'another-user', configured: false), isTrue);
  });
  test('custom QR colors use white-background contrast rather than a palette', () {
    for (final color in ['445566', '5A245A', '003F88', '767676']) {
      expect(ticketQrColorReadable(color), isTrue);
    }
    for (final color in ['777777', 'FFFFFF', 'FFFF00', 'oops']) {
      expect(ticketQrColorReadable(color), isFalse);
    }
  });
  testWidgets('text and QR share the color picker and HEX entry', (tester) async {
    for (final binding in ['qr', 'occasionTitle']) {
      final c = TicketLayoutController(document())..select(binding);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
          child: TicketLayoutProperties(controller: c)))));
      await tester.tap(find.text(binding == 'qr' ? 'TicketLayout.qrColor' : 'TicketLayout.color'));
      await tester.pumpAndSettle();
      expect(find.byType(ColorPicker), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'FFFFFF');
      await tester.pump();
      final apply = find.widgetWithText(FilledButton, 'TicketLayout.apply');
      expect(tester.widget<FilledButton>(apply).onPressed == null, binding == 'qr');
      await tester.enterText(find.byType(TextField), '445566'); await tester.pump();
      await tester.tap(apply); await tester.pumpAndSettle();
      expect(c.selection!.color, '445566');
      await tester.pumpWidget(const SizedBox()); c.dispose();
    }
  });
  test('styled text fitting matches the PDF renderer fixtures', () {
    final cases = jsonDecode(File('test/fixtures/ticket_layout/text-emphasis.json').readAsStringSync()) as List;
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
  test('group movement preserves relative placement, bounds and one undo step', () {
    final c = TicketLayoutController(document());
    c.select('qr'); c.select('ticketSymbol', additive: true);
    final before = {for (final e in c.selections) e.id: e.box};
    c.beginGesture();
    c.move(const Offset(-10, -10), snap: false);
    c.move(const Offset(-1000, -1000), snap: false);
    c.endGesture();
    final shifts = c.selections.map((e) => e.box.topLeft - before[e.id]!.topLeft).toSet();
    expect(shifts.length, 1);
    for (final e in c.selections) { expect(e.box.left, greaterThanOrEqualTo(0)); expect(e.box.top, greaterThanOrEqualTo(0)); }
    final q = c.document.elements.firstWhere((e) => e.binding == 'qr');
    expect(q.box.width, q.box.height);
    c.undo(); expect(c.document.toJson(), document().toJson());
    expect(c.canUndo, isFalse);
    c.redo(); expect(c.document.toJson(), isNot(document().toJson()));
    c.dispose();
  });
  testWidgets('selection marquee and shift-click move QR and code together', (tester) async {
    await tester.pumpWidget(MaterialApp(home: TicketLayoutEditor(
        occasionId: 1, type: 'named', resources: resources(), service: FakeService())));
    await tester.pumpAndSettle();
    final state = tester.state<TicketLayoutCanvasState>(find.byType(TicketLayoutCanvas));
    final c = state.widget.controller;
    Offset screen(Offset p) => tester.getTopLeft(find.byType(InteractiveViewer)) +
        MatrixUtils.transformPoint(state.widget.transform.value, c.document.area.topLeft + p);
    final qr = c.document.elements.firstWhere((e) => e.binding == 'qr');
    final code = c.document.elements.firstWhere((e) => e.binding == 'ticketSymbol');
    await tester.tapAt(screen(qr.box.center));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(screen(code.box.center));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(c.selectedIds, {'qr', 'ticketSymbol'});
    final drag = await tester.startGesture(screen(qr.box.center));
    await drag.moveBy(const Offset(-5, -5)); await drag.up(); await tester.pump();
    expect(c.selectedIds, {'qr', 'ticketSymbol'});
    expect(c.document.elements.firstWhere((e) => e.id == qr.id).box, isNot(qr.box));
    c.undo(); c.select(null); await tester.pump();
    final bounds = qr.box.expandToInclude(code.box).inflate(2);
    final marquee = await tester.startGesture(screen(bounds.topLeft));
    await marquee.moveTo(screen(bounds.bottomRight)); await marquee.up(); await tester.pump();
    expect(c.selectedIds, containsAll(['qr', 'ticketSymbol']));
    await tester.tap(find.byTooltip('TicketLayout.viewOptions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.multiSelect'));
    await tester.pumpAndSettle();
    final previous = c.document;
    final touchDrag = await tester.startGesture(screen(qr.box.center));
    await touchDrag.moveBy(const Offset(-8, -8)); await touchDrag.up(); await tester.pump();
    expect(c.selectedIds, containsAll(['qr', 'ticketSymbol']));
    expect(c.document.toJson(), isNot(previous.toJson()));

  });
  testWidgets('text emphasis round trips, updates the editor and supports undo', (tester) async {
    final c = TicketLayoutController(document())..select('occasionTitle');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: TicketLayoutProperties(controller: c)))));
    for (final style in ['bold', 'italic', 'underline']) {
      await tester.tap(find.byTooltip('TicketLayout.$style')); await tester.pump();
      expect(c.selection!.toJson()['style'][style], isTrue);
    }
    final restored = TicketElement.fromJson(c.selection!.toJson());
    expect(restored.bold && restored.italic && restored.underline, isTrue);
    c.undo(); expect(c.selection!.underline, isFalse);
    await tester.pumpWidget(const SizedBox()); c.dispose();
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
      expect(find.text('TicketLayout.edit'), findsOneWidget);
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
                              document: template,
                              defaults: template,
                              type: 'wide'));
                    },
                    child: const Text('dimensions'))))));
    await tester.tap(find.text('dimensions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.apply'));
    await tester.pumpAndSettle();
    expect(result!.toJson(), template.toJson());
  });
  testWidgets(
      'default dimensions preview immediately and cancel restores the ticket',
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
    await tester.tap(find.text('TicketLayout.canvasSize').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.defaultDimensions'));
    await tester.pumpAndSettle();
    expect(view.controller.document.area.size, original.area.size);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('TicketLayout.cancel')));
    await tester.pumpAndSettle();
    expect(view.controller.document.toJson(), resized.toJson());
    view.controller.undo();
    expect(view.controller.document.toJson(), original.toJson());
    view.controller.replace(resized);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.canvasSize').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.defaultDimensions'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('TicketLayout.apply')));
    await tester.pumpAndSettle();
    expect(view.controller.document.area.size, original.area.size);
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
    expect(find.text('TicketLayout.style_compact'), findsOneWidget);
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
    await tester.tap(find.text('TicketLayout.color'));
    await tester.pumpAndSettle();
    expect(find.byType(ColorPicker), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'AA1122');
    await tester.tap(find.text('TicketLayout.cancel'));
    await tester.pumpAndSettle();
    expect(controller.selection!.color, before);
    await tester.tap(find.text('TicketLayout.color'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'AA1122');
    await tester.tap(find.text('TicketLayout.apply'));
    await tester.pumpAndSettle();
    expect(controller.selection!.color, 'AA1122');
    controller.undo();
    expect(controller.selection!.color, before);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  setUpAll(() async {
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
    for (final entry in (fixtures['invalid'] as Map).entries) {
      final l = entry.value;
      if (l['schemaVersion'] != 1 || (l['templates'] as Map).isEmpty) continue;
      final templates = (l['templates'] as Map).entries;
      expect(
          templates.any((e) =>
              TicketTemplate.fromJson(e.value).validate(e.key).isNotEmpty),
          isTrue,
          reason: entry.key);
    }
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
    await tester.tap(find.text('TicketLayout.apply'));
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
    await tester.tap(find.byTooltip('TicketLayout.pdf'));
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
    await tester.tap(find.byTooltip('TicketLayout.pdf'));
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
    await tester.tap(find.byTooltip('TicketLayout.viewOptions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.grid'));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('TicketLayout.viewOptions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.snap'));
    await tester.pump();
    final view =
        tester.widget<TicketLayoutCanvas>(find.byType(TicketLayoutCanvas));
    expect(view.grid, isTrue);
    expect(view.snap, isFalse);
    await tester.tap(find.text('TicketLayout.styles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.style_compact'));
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
    await tester.tap(find.text('TicketLayout.style_classic'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TicketLayoutCanvas)).height,
        greaterThan(400));
    await tester.tap(find.text('TicketLayout.elements'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TicketLayout.occasionTitle'));
    await tester.pumpAndSettle();
    expect(find.byType(TicketLayoutProperties).hitTestable(), findsOneWidget);
    expect(find.text('TicketLayout.color').hitTestable(), findsOneWidget);
    await tester.tap(find.text('TicketLayout.color'));
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
      await tester.tap(find.byTooltip('TicketLayout.$align'));
      await tester.pump();
      expect(c.selection!.align, align);
    }
    c.undo();
    expect(c.selection!.align, 'right');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
