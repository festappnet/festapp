import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_palette_thumbnail.dart';

void main() {
  testWidgets(
    'desktop palette is visible and dragging a table is one undo step',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: controller, showGallery: false),
          ),
        ),
      );
      expect(find.text('Objects'), findsOneWidget);
      expect(find.text('Seating'), findsOneWidget);
      final tile = find.byWidgetPredicate(
        (w) => w is Draggable<String> && w.data == 'Table',
      );
      final canvas = find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onDrop != null,
      );
      final start = tester.getCenter(tile), end = tester.getCenter(canvas);
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(end);
      await tester.pump();
      final previewIds = controller.document.nodes.map((n) => n.id).toSet();
      expect(previewIds, hasLength(7));
      await gesture.moveTo(end + const Offset(12, 10));
      await tester.pump();
      expect(controller.document.nodes.map((n) => n.id).toSet(), previewIds);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        controller.document.nodes.where((n) => n.kind == 'table'),
        hasLength(1),
      );
      controller.undo();
      expect(controller.document.nodes, isEmpty);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets('translation snaps by default and can be disabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'seat',
      x: 100,
      y: 100,
      width: 32,
      height: 32,
    );
    final controller = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(
        nodes: [node],
        canvas: {
          'x': 0,
          'y': 0,
          'width': 208,
          'height': 208,
          'fill': '#FFFFFFFF',
        },
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: controller, showGallery: false),
        ),
      ),
    );
    LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
      find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onDragStart != null,
      ),
    );
    Future<void> move({required bool snapped}) async {
      surface().onDragStart!(const Offset(100, 100));
      surface().onDragUpdate!(const Offset(103, 103));
      await tester.pump();
      expect(surface().snapGuides, snapped ? isNotEmpty : isEmpty);
      surface().onDragEnd!();
      await tester.pump();
      expect(surface().snapGuides, isEmpty);
    }

    await move(snapped: true);
    expect(controller.document.nodes.single.x, 104);
    expect(controller.document.nodes.single.y, 104);
    controller.undo();
    await tester.pump();
    await tester.tap(find.text('Snap'));
    await tester.pump();
    await move(snapped: false);
    expect(controller.document.nodes.single.x, 103);
    expect(controller.document.nodes.single.y, 103);
  });

  testWidgets(
    'rotation snaps absolute angle and Alt temporarily bypasses snapping',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 100,
        y: 100,
        width: 80,
        height: 40,
        rotation: 7,
      );
      final controller = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [node]),
      );
      addTearDown(controller.dispose);
      controller.select({node.id});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: controller, showGallery: false),
          ),
        ),
      );
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onHandleStart != null,
        ),
      );
      void rotate() {
        surface().onHandleStart!('Rotate', const Offset(200, 100));
        surface().onDragUpdate!(
          Offset(
            100 + 100 * math.cos(20 * math.pi / 180),
            100 + 100 * math.sin(20 * math.pi / 180),
          ),
        );
        surface().onDragEnd!();
      }

      rotate();
      expect(controller.document.nodes.single.rotation, closeTo(30, .0001));
      controller.undo();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      rotate();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(controller.document.nodes.single.rotation, closeTo(27, .0001));
      controller.undo();
      await tester.pump();
      await tester.tap(find.text('Snap'));
      await tester.pump();
      rotate();
      expect(controller.document.nodes.single.rotation, closeTo(27, .0001));
    },
  );

  testWidgets('Couch palette inserts the canonical atomic two-seat assembly', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = VenueLayoutController(VenueLayoutDocument.empty());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: controller, showGallery: false),
        ),
      ),
    );
    await tester.tap(find.text('Couch'));
    await tester.pump();
    final canvas = find.byWidgetPredicate(
      (w) => w is LayoutSceneSurface && w.onTap != null,
    );
    await tester.tapAt(tester.getCenter(canvas));
    await tester.pump();
    final furniture = controller.document.nodes
        .where((n) => n.kind == 'furniture')
        .single;
    final seats = controller.document.nodes
        .where((n) => n.kind == 'seat')
        .toList();
    expect(seats, hasLength(2));
    expect(seats.every((n) => n.parentId == furniture.id), isTrue);
    expect(controller.document.nodes, hasLength(3));
    expect(controller.document.selectionUnits.single['kind'], 'atomic');
    expect(
      (controller.document.selectionUnits.single['nodeIds'] as List).toSet(),
      seats.map((n) => n.id).toSet(),
    );
    expect(validateDocument(controller.document), isEmpty);
    controller.undo();
    expect(controller.document.nodes, isEmpty);
    expect(controller.document.selectionUnits, isEmpty);
    expect(controller.canUndo, isFalse);
  });

  testWidgets('color well applies a swatch as one undoable property edit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'shape',
      x: 100,
      y: 100,
      properties: {},
      style: {'fill': '#CBD5E1FF'},
    );
    final controller = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(nodes: [node]),
    );
    addTearDown(controller.dispose);
    controller.select({node.id});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: controller, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final well = find.byKey(const ValueKey('canonical-style-fill'));
    await tester.ensureVisible(well);
    await tester.tap(well);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editor-color-Basic colors-2563EB')),
    );
    await tester.pump();
    expect(
      controller.document.nodes.single.style['fill'],
      '#2563EBFF',
      reason: 'The canonical color field previews the chosen swatch live.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(controller.document.nodes.single.style['fill'], '#2563EBFF');
    controller.undo();
    expect(controller.document.nodes.single.style['fill'], '#CBD5E1FF');
    expect(controller.canUndo, isFalse);
  });

  testWidgets(
    'palette thumbnails are transparent centered and non-interactive',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: controller, showGallery: false),
          ),
        ),
      );
      final search = find
          .byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Find object',
          )
          .first;
      for (final kind in [
        'Seat',
        'Table',
        'Round table',
        'Rows',
        'Arc',
        'Standing',
        'Couch',
        'Bar',
        'Bus',
        'Compartments',
        'Text',
        'Rectangle',
        'Ellipse',
        'Line',
        'Arrow',
        'Polyline',
        'Polygon',
      ]) {
        await tester.enterText(search, kind);
        await tester.pump();
        final thumbnails = find.byType(LayoutPaletteThumbnail);
        expect(thumbnails, findsWidgets, reason: kind);
        expect(find.byType(LayoutSceneSurface), findsOneWidget);
        for (final element in thumbnails.evaluate()) {
          final preview = element.widget as LayoutPaletteThumbnail;
          expect(validateDocument(preview.document), isEmpty, reason: kind);
          expect(preview.document.canvas['fill'], '#00000000');
          expect(preview.document.nodes.every((n) => n.label.isEmpty), true);
          if (kind == 'Text') {
            expect(
              find.descendant(
                of: find.byWidget(preview),
                matching: find.text('Aa'),
              ),
              findsOneWidget,
            );
            continue;
          }
          final paint = find.descendant(
            of: find.byWidget(preview),
            matching: find.byType(CustomPaint),
          );
          final painter =
              tester.widget<CustomPaint>(paint).painter! as LayoutScenePainter;
          final size = tester.getSize(paint);
          final bounds = selectionBounds(
            preview.document,
            preview.document.nodes.map((n) => n.id).toSet(),
          );
          expect(
            painter.offset.dx +
                (bounds['x']! + bounds['width']! / 2) * painter.scale,
            closeTo(size.width / 2, .001),
            reason: kind,
          );
          expect(
            painter.offset.dy +
                (bounds['y']! + bounds['height']! / 2) * painter.scale,
            closeTo(size.height / 2, .001),
            reason: kind,
          );
        }
      }
    },
  );

  testWidgets('rotation blur and Apply submit once and undo once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final id = newLayoutId();
    final controller = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(
        nodes: [LayoutNode(id: id, kind: 'shape', x: 300, y: 300)],
      ),
    );
    addTearDown(controller.dispose);
    controller.select({id});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: controller, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Position and size'));
    await tester.tap(find.text('Position and size'));
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Rotation',
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, '37');
    final textField = tester.widget<TextField>(field);
    // Browser pointer-down blur and suffix activation can precede one rebuild.
    textField.onTapOutside!(const PointerDownEvent());
    textField.onSubmitted!(textField.controller!.text);
    await tester.pump();
    expect(controller.document.nodes.single.rotation, 37);
    controller.undo();
    expect(controller.document.nodes.single.rotation, 0);
    expect(controller.canUndo, isFalse);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'canvas semantics omit synthetic taps and preserve real pointer coordinates',
    (tester) async {
      final semantics = tester.ensureSemantics();
      Offset? tapped;
      final document = VenueLayoutDocument.empty().copyWith(
        canvas: {'x': 0, 'y': 0, 'width': 400, 'height': 400},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 432,
              height: 432,
              child: Semantics(
                container: true,
                label: 'Layout canvas',
                child: LayoutSceneSurface(
                  document: document,
                  showControls: false,
                  pan: false,
                  onTap: (point) => tapped = point,
                ),
              ),
            ),
          ),
        ),
      );
      final canvas = tester.getSemantics(
        find.bySemanticsLabel('Layout canvas'),
      );
      expect(
        canvas.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isFalse,
      );
      final origin = tester.getTopLeft(find.byType(LayoutSceneSurface));
      await tester.tapAt(origin + const Offset(316, 96));
      await tester.pump();
      expect(tapped, const Offset(300, 80));
      semantics.dispose();
    },
  );

  testWidgets(
    'editor fits narrow and wide screens and inserts an undoable table',
    (tester) async {
      final controller = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(controller.dispose);
      for (final width in [360.0, 900.0, 1440.0]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueLayoutEditor(
                controller: controller,
                showGallery: false,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (width < 700) {
          expect(
            find.byKey(const ValueKey('layout-mobile-library')),
            findsOneWidget,
          );
        } else {
          expect(find.text(width < 900 ? 'Insert' : 'Objects'), findsOneWidget);
        }
      }

      await tester.tap(find.text('Table').last);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 400));
      await tester.pumpAndSettle();
      expect(
        controller.document.nodes.where((n) => n.kind == 'table'),
        hasLength(1),
      );
      expect(
        controller.document.nodes.where((n) => n.kind == 'seat'),
        hasLength(6),
      );
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(controller.document.nodes, isEmpty);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'paired selection stays pending and rolls back atomically on rejection',
    (tester) async {
      final a = newLayoutId(), b = newLayoutId();
      final doc = VenueLayoutDocument.empty().copyWith(
        nodes: [
          LayoutNode(id: a, kind: 'seat', x: 100, y: 100),
          LayoutNode(id: b, kind: 'seat', x: 150, y: 100),
        ],
        selectionUnits: [
          {
            'id': newLayoutId(),
            'nodeIds': [a, b],
          },
        ],
      );
      final response = Completer<LayoutSelectionResult>();
      Set<String>? requested;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutPicker(
              document: doc,
              seatPresentation: {
                a: {'label': 'A1'},
                b: {'label': 'A2'},
              },
              onSelectionRequested: (ids, selecting) {
                requested = ids;
                expect(selecting, isTrue);
                return response.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Accessible seat list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A1'));
      await tester.pump();
      expect(requested, {a, b});
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('2 seats selected'), findsOneWidget);
      response.complete(
        const LayoutSelectionResult(
          accepted: false,
          message: 'Already reserved',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 seats selected'), findsOneWidget);
      expect(find.text('Already reserved'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('multiline text can be committed with explicit apply', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final id = newLayoutId();
    final controller = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(
        nodes: [
          LayoutNode(
            id: id,
            kind: 'text',
            x: 200,
            y: 200,
            properties: {'text': 'Before'},
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    controller.select({id});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: controller, showGallery: false),
        ),
      ),
    );
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Text',
    );
    await tester.enterText(field, 'First line\nSecond line');
    tester.widget<TextField>(field).onEditingComplete!();
    await tester.pump();
    expect(
      controller.document.nodes.single.properties['text'],
      'First line\nSecond line',
    );
    controller.undo();
    expect(controller.document.nodes.single.properties['text'], 'Before');
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets(
    'polygon placement commits one command and cancels unfinished paths',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      final source = VenueLayoutDocument.empty().copyWith(
        nodes: [
          LayoutNode(
            id: newLayoutId(),
            kind: 'shape',
            x: 1200,
            y: 800,
            width: 2400,
            height: 1600,
            z: 900,
            properties: const {'shape': 'rect'},
            style: const {'fill': '#FFFFFFFF'},
          ),
        ],
      );
      final controller = VenueLayoutController(source);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: controller, showGallery: false),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'Polygon');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Polygon').last);
      for (final point in [
        const Offset(250, 350),
        const Offset(450, 350),
        const Offset(350, 500),
      ]) {
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 350));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final polygon = controller.document.nodes.singleWhere(
        (n) => n.properties['shape'] == 'polygon',
      );
      expect(
        effectiveNodeProperties(controller.document, polygon)['fill'],
        '#CBD5E1FF',
      );
      expect(orderedNodes(controller.document).last.id, polygon.id);
      expect(polygon.properties['points'], hasLength(3));
      controller.undo();
      await tester.pump();
      expect(controller.document.toJson(), source.toJson());
      await tester.tap(find.text('Polygon').last);
      await tester.tapAt(const Offset(250, 350));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tapAt(const Offset(450, 350));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.document.toJson(), source.toJson());
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('visible resize handle creates one undo transaction', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'shape',
      x: 700,
      y: 700,
      width: 180,
      height: 100,
    );
    final controller = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(nodes: [node]),
    );
    addTearDown(controller.dispose);
    controller.select({node.id});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: controller, showGallery: false),
        ),
      ),
    );
    await tester.drag(find.byTooltip('Resize handle'), const Offset(45, 30));
    await tester.pump();
    expect(controller.document.nodes.single.width, greaterThan(node.width));
    controller.undo();
    expect(controller.document.nodes.single.width, node.width);
    expect(controller.canUndo, isFalse);
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets(
    'background crop hides pixels without stretching or moving registration',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 400));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 50, 100),
        Paint()..color = Colors.red,
      );
      canvas.drawRect(
        const Rect.fromLTWH(50, 0, 50, 100),
        Paint()..color = Colors.blue,
      );
      final image = (await tester.runAsync(
        () => recorder.endRecording().toImage(100, 100),
      ))!;
      addTearDown(image.dispose);
      final document = VenueLayoutDocument.empty().copyWith(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 100,
          'fill': '#FFFFFFFF',
        },
        background: {
          'assetRef': 'test',
          'hash':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'x': 50,
          'y': 50,
          'width': 100,
          'height': 100,
          'scale': 1,
          'rotation': 0,
          'opacity': 1,
          'crop': {'x': .5, 'y': 0, 'width': .5, 'height': 1},
        },
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: VenueLayoutViewer(
              document: document,
              resources: {
                'images': {'test': image},
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final rendered = (await tester.runAsync(
        () => (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 1),
      ))!;
      final bytes = (await tester.runAsync(
        () => rendered.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.buffer.asUint8List();
      int channel(int x, int y, int c) =>
          bytes[(y * rendered.width + x) * 4 + c];
      expect(
        [channel(100, 200, 0), channel(100, 200, 1), channel(100, 200, 2)],
        [255, 255, 255],
      );
      expect(channel(300, 200, 2), greaterThan(200));
      expect(channel(300, 200, 0), lessThan(100));
      rendered.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'multi-selection alignment and distribution use atomic undo commands',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      final nodes = [
        for (final x in [200.0, 400.0, 700.0])
          LayoutNode(id: newLayoutId(), kind: 'shape', x: x, y: 300),
      ];
      final controller = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: nodes),
      );
      addTearDown(controller.dispose);
      controller.select(nodes.map((n) => n.id).toSet());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: controller, showGallery: false),
          ),
        ),
      );
      await tester.tap(find.text('Align and distribute'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Align left'));
      await tester.pumpAndSettle();
      expect(controller.document.nodes.map((n) => n.x).toSet(), {200.0});
      controller.undo();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Distribute horizontally'));
      await tester.tap(find.byTooltip('Distribute horizontally'));
      await tester.pumpAndSettle();
      expect(controller.document.nodes.map((n) => n.x).toList()..sort(), [
        200.0,
        450.0,
        700.0,
      ]);
      controller.undo();
      expect(controller.document.nodes.map((n) => n.x).toList(), [
        200.0,
        400.0,
        700.0,
      ]);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'background replacement aspect preview preserves positions and supports undo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        x: 50,
        y: 50,
        width: 20,
        height: 20,
      );
      final document = VenueLayoutDocument.empty().copyWith(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 100,
          'fill': '#FFFFFFFF',
        },
        nodes: [node],
      );
      final controller = VenueLayoutController(
        document,
        resources: {
          'protocol': 2,
          'fontFamilies': <String, dynamic>{},
          'textLayouts': <String, dynamic>{},
          'numberSymbols': <String, dynamic>{},
          'assets': {
            'image:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa': {
              'width': 200,
              'height': 100,
              'mimeType': 'image/png',
              'byteLength': 100,
              'url': 'https://example.invalid/wide.png',
              'hash':
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            },
          },
        },
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: controller, showGallery: false),
          ),
        ),
      );
      await tester.tap(find.text('Canvas'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose image'));
      await tester.tap(find.text('Choose image'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          'image:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep layout and canvas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Match image aspect ratio').last);
      await tester.pumpAndSettle();
      expect(controller.document.background, isNull);
      await tester.tap(find.text('Use image'));
      await tester.pumpAndSettle();
      expect(controller.document.canvas['width'], 200);
      expect(controller.document.canvas['height'], 100);
      expect(controller.document.nodes.single.x, node.x);
      expect(controller.document.nodes.single.y, node.y);
      controller.undo();
      expect(controller.document.background, isNull);
      expect(controller.document.canvas['width'], 100);
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets('painter LOD combines fit scale and camera zoom', (tester) async {
    final scene = <String, dynamic>{
      'canvas': {
        'x': 0,
        'y': 0,
        'width': 200,
        'height': 200,
        'fill': '#FFFFFFFF',
      },
      'items': <Map<String, dynamic>>[
        {
          'id': 'fixture',
          'matrix': [1, 0, 0, 1, 0, 0],
          'path': [
            ['M', 20, 20],
            ['L', 80, 20],
            ['L', 80, 80],
            ['L', 20, 80],
            ['Z'],
          ],
          'bounds': {'x': 20, 'y': 20, 'width': 60, 'height': 60},
          'fill': '#FF0000FF',
          'minZoom': 2,
        },
      ],
    };
    for (final zoom in [3.0, 5.0]) {
      final camera = TransformationController(
        Matrix4.diagonal3Values(zoom, zoom, 1),
      );
      final recorder = ui.PictureRecorder();
      LayoutScenePainter(
        scene: scene,
        resources: const {},
        selected: const {},
        scale: .5,
        offset: Offset.zero,
        canvasColor: Colors.white,
        selectionColor: Colors.blue,
        camera: camera,
      ).paint(Canvas(recorder), const Size(100, 100));
      final rendered = (await tester.runAsync(
        () => recorder.endRecording().toImage(100, 100),
      ))!;
      final pixels = (await tester.runAsync(
        () => rendered.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.buffer.asUint8List();
      expect(pixels[(75 * 100 + 75) * 4 + 1], zoom == 3 ? 255 : 0);
      rendered.dispose();
      camera.dispose();
    }
  });
}
