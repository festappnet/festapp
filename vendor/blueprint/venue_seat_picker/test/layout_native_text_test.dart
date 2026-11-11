import 'package:material_ui/material_ui.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/layout_native_text.dart';
import 'package:venue_seat_picker/src/layout_editor/layout_scene_cache.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets('native labels preserve cached geometry while a round table moves', (
    tester,
  ) async {
    final moving = tableLayout(
      shape: 'ellipse',
      count: 0,
      x: 400,
      y: 400,
      width: 160,
      height: 160,
    ).nodes.first.copyWith(label: '32');
    final stationary = tableLayout(
      shape: 'rect',
      count: 0,
      x: 1000,
      y: 400,
      width: 200,
      height: 100,
    ).nodes.first;
    final fixture =
        jsonDecode(File('assets/layout_fonts/fixtures.json').readAsStringSync())
            as Map;
    final resources = <String, dynamic>{
      'protocol': 2,
      'fontFamilies': fixture['fontFamilies'],
      'textLayouts': <String, dynamic>{},
      'numberSymbols': <String, dynamic>{},
    };
    final document = VenueLayoutDocument(
      nodes: [moving, stationary],
      styles: {
        'label': {'fontFamilyId': (fixture['fontFamilies'] as Map).keys.first},
      },
    );
    final geometry = LayoutSceneCache();
    final native = LayoutNativeTextCache();
    addTearDown(native.dispose);
    const fonts = {'font': TextStyle(fontFamily: 'Ahem')};
    final firstGeometry = geometry.update(
      document,
      resources: resources,
      nativeTextPreview: true,
    );
    expect(
      (firstGeometry['issues'] as List).single['reason'],
      'text_layout_unavailable',
    );
    final first = native.update(firstGeometry, document, fonts, (_) => 'font');
    expect(
      (first['items'] as List).any((i) => i['kind'] == 'nativeText'),
      isTrue,
    );
    Map path(Map scene, String id) =>
        (scene['items'] as List).cast<Map>().firstWhere(
          (item) =>
              (item['nodeId'] ?? item['id']) == id && item['path'] is List,
        );
    final stationaryPath = path(firstGeometry, stationary.id);
    expect(
      path(first, stationary.id),
      same(stationaryPath),
      reason: 'The painter caches parsed paths by scene-item identity',
    );
    final movingPath = path(first, moving.id);
    for (var step = 1; step <= 3; step++) {
      final next = document.copyWith(
        nodes: [
          moving.copyWith(x: 400.0 + step),
          stationary,
        ],
      );
      final compiled = geometry.update(
        next,
        resources: resources,
        nativeTextPreview: true,
      );
      expect(
        compiled,
        compileScene(next, resources: resources),
        reason:
            'Editor caching preserves canonical geometry and pending-text diagnostics',
      );
      final rendered = native.update(compiled, next, fonts, (_) => 'font');
      expect(path(compiled, stationary.id), same(stationaryPath));
      expect(path(rendered, stationary.id), same(stationaryPath));
      expect(
        path(rendered, moving.id),
        isNot(same(movingPath)),
        reason:
            'The moving table must still receive fresh transformed geometry',
      );
      expect(
        (compiled['items'] as List).any((i) => i['kind'] == 'nativeText'),
        isFalse,
        reason: 'Native decoration must not mutate the canonical cached scene',
      );
    }
    final invalid = document.copyWith(
      nodes: [moving.copyWith(width: 0), stationary],
    );
    final rejected = geometry.update(
      invalid,
      resources: resources,
      nativeTextPreview: true,
    );
    expect(rejected, compileScene(invalid, resources: resources));
    expect(
      rejected['items'],
      isEmpty,
      reason:
          'Allowing pending text must never retain geometry after invalid input',
    );
    final viewing = document.copyWith(
      nodes: [moving.copyWith(x: 410), stationary],
    );
    final canonical = geometry.update(viewing, resources: resources);
    expect(
      canonical,
      compileScene(viewing, resources: resources),
      reason: 'Viewers retain the complete canonical text-resource contract',
    );
  });

  testWidgets('native custom table label stays entirely on the tabletop', (
    tester,
  ) async {
    final table = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      width: 160,
      height: 100,
      label: 'Table 1',
      surface: const {
        'type': 'grid',
        'moduleSize': 1,
        'outer': [
          [0, 0],
          [160, 0],
          [160, 100],
          [108, 100],
          [108, 50],
          [54, 50],
          [54, 100],
          [0, 100],
        ],
        'holes': [],
      },
    );
    final document = VenueLayoutDocument(nodes: [table]);
    final cache = LayoutNativeTextCache();
    addTearDown(cache.dispose);
    final scene = cache.update(compileScene(document), document, {
      'font': const TextStyle(fontFamily: 'Ahem'),
    }, (_) => 'font');
    final item = (scene['items'] as List).singleWhere(
      (i) => i['kind'] == 'nativeText',
    );
    final painter = item['nativeParagraph'] as TextPainter;
    final offset = item['nativeOffset'] as Offset;
    final matrix = List<double>.from(item['matrix']);
    final ring = nodeOutlineContours(table).first;
    for (final box in painter.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 7),
    )) {
      final rect = box.toRect().shift(offset);
      for (final x in [rect.left, rect.center.dx, rect.right]) {
        for (final y in [rect.top, rect.center.dy, rect.bottom]) {
          final p = transformPoint(matrix, x, y);
          expect(pointInPolygon(ring, p[0], p[1]), isTrue);
        }
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editing uses cached actual fonts while resizing without prepared text; viewing keeps vectors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final base = tableLayout(
        shape: 'rect',
        count: 0,
        x: 600,
        y: 400,
        width: 300,
        height: 200,
      );
      final d = base.copyWith(
        nodes: [
          for (final n in base.nodes)
            n.kind == 'table' ? n.copyWith(label: 'Editor table') : n,
        ],
      );
      final table = d.nodes.firstWhere((n) => n.kind == 'table');
      final c = VenueLayoutController(d)..select({table.id});
      addTearDown(c.dispose);
      var fonts = 0;
      Future<TextStyle> font(LayoutNode _) async {
        fonts++;
        return const TextStyle(fontFamily: 'Ahem');
      }

      Future<void> render(bool editing) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueLayoutEditor(
                controller: c,
                showGallery: false,
                interactionEnabled: editing,
                inlineTextStyleBuilder: font,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      LayoutScenePainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .firstWhere(
            (p) => (p.scene['items'] as List).any(
              (i) => (i['nodeId'] ?? i['id']) == table.id,
            ),
          );
      await render(true);
      expect(
        (painter().scene['items'] as List).where(
          (i) => i['kind'] == 'nativeText',
        ),
        hasLength(1),
      );
      expect(
        (painter().scene['items'] as List).any(
          (i) => i['kind'] == 'glyphs' && '${i['id']}'.endsWith(':text'),
        ),
        isFalse,
      );
      expect(find.text('Text is not ready yet.'), findsNothing);
      for (final height in [250.0, 300.0, 400.0]) {
        c.resizeObject(table.id, 300, height);
        await tester.pumpAndSettle();
        expect(c.error, isNull);
        expect((painter().scene['issues'] as List), isEmpty);
      }
      expect(fonts, 1);
      expect(c.resources['textLayouts'] ?? {}, isEmpty);
      Offset center() =>
          (tester.getCenter(
                find.byKey(const ValueKey('layout-handle-Resize n')),
              ) +
              tester.getCenter(
                find.byKey(const ValueKey('layout-handle-Resize s')),
              )) /
          2;
      final rotate = find.byKey(const ValueKey('layout-handle-Rotate'));
      expect(tester.getCenter(rotate).dy, lessThan(center().dy));
      c.rotateSelection(90);
      await tester.pumpAndSettle();
      expect(tester.getCenter(rotate).dx, greaterThan(center().dx));
      expect(tester.getCenter(rotate).dy, closeTo(center().dy, 1));
      await render(false);
      expect(
        (painter().scene['items'] as List).any(
          (i) => i['kind'] == 'nativeText',
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'draft text preview does not enable geometry and viewers default to vectors',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = tableLayout(shape: 'rect', count: 0);
      final table = document.nodes.first;
      final controller = VenueLayoutController(
        document.copyWith(nodes: [table.copyWith(label: 'Draft table')]),
      );
      addTearDown(controller.dispose);
      var fontLoads = 0;
      Future<void> mount({bool nativeTextPreview = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueLayoutEditor(
                controller: controller,
                showGallery: false,
                interactionEnabled: false,
                nativeTextPreview: nativeTextPreview,
                inlineTextStyleBuilder: (_) async {
                  fontLoads++;
                  return const TextStyle(fontFamily: 'Ahem');
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      LayoutScenePainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<LayoutScenePainter>()
          .firstWhere(
            (p) => (p.scene['items'] as List).any(
              (item) => (item['nodeId'] ?? item['id']) == table.id,
            ),
          );
      List nativeItems() => (painter().scene['items'] as List)
          .where((item) => item['kind'] == 'nativeText')
          .toList();

      await mount();
      expect(nativeItems(), isEmpty);
      expect(fontLoads, 0);
      await mount(nativeTextPreview: true);
      expect(nativeItems(), hasLength(1));
      expect(fontLoads, 1);
      expect(find.byKey(const ValueKey('layout-tool-Select')), findsNothing);
      final beforeDrag = controller.document.toJson();
      await tester.drag(find.byType(LayoutSceneSurface), const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(controller.document.toJson(), beforeDrag);
      expect(controller.canUndo, isFalse);

      controller.apply(
        controller.document.copyWith(
          nodes: [table.copyWith(label: 'Renamed draft table')],
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = nativeItems().single['nativeParagraph'] as TextPainter;
      expect(paragraph.text!.toPlainText(), 'Renamed draft table');
      expect(fontLoads, 1, reason: 'Renaming reuses the loaded face');
      expect(controller.resources['textLayouts'] ?? {}, isEmpty);
      await mount();
      expect(nativeItems(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
