import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    VenueLayoutController controller, {
    Future<TextStyle> Function(LayoutNode)? inlineTextStyleBuilder,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(
            controller: controller,
            showGallery: false,
            inlineTextStyleBuilder: inlineTextStyleBuilder,
          ),
        ),
      ),
    );
  }

  LayoutSceneSurface surface(WidgetTester tester) =>
      tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onTap != null,
        ),
      );
  final inline = find.byKey(const ValueKey('layout-inline-label'));

  testWidgets(
    'canonical native input waits for its actual face and commits composed source in one undo',
    (tester) async {
      final fixture =
          jsonDecode(
                File(
                  'web/test/fixtures/canonical_rendering.json',
                ).readAsStringSync(),
              )
              as Map;
      final document = VenueLayoutDocument.fromJson(
        Map<String, dynamic>.from(fixture['document']),
      );
      final node = document.nodes.firstWhere((n) => n.kind == 'text');
      final c = VenueLayoutController(
        document.copyWith(
          nodes: [node],
          attachments: [],
          selectionUnits: [],
          sections: [],
          presets: [],
        ),
        resources: Map<String, dynamic>.from(fixture['resources']),
      );
      final ready = Completer<TextStyle>();
      var loads = 0;
      await tester.runAsync(() async {
        final bytes = await File(
          'assets/layout_fonts/Roboto-400-normal.ttf',
        ).readAsBytes();
        final loader = FontLoader('CanonicalActualInputFace')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      });
      await open(
        tester,
        c,
        inlineTextStyleBuilder: (requested) {
          loads++;
          expect(requested.id, node.id);
          return ready.future;
        },
      );
      surface(tester).onDoubleTapAt!(Offset(node.x, node.y));
      await tester.pump();
      expect(inline, findsNothing);
      expect(loads, greaterThan(0));
      ready.complete(
        const TextStyle(
          fontFamily: 'CanonicalActualInputFace',
          fontWeight: FontWeight.normal,
          fontStyle: FontStyle.normal,
        ),
      );
      await tester.pump();
      await tester.pump();
      final field = tester.widget<TextField>(inline);
      expect(field.style!.fontFamily, 'CanonicalActualInputFace');
      expect(field.style!.fontWeight, FontWeight.normal);
      expect(field.style!.fontStyle, FontStyle.normal);
      field.controller!.value = const TextEditingValue(
        text: 'Židle AV ffi',
        selection: TextSelection.collapsed(offset: 12),
        composing: TextRange(start: 0, end: 5),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        c.document.nodes.single.properties['text'],
        node.properties['text'],
      );
      field.controller!.clearComposing();
      field.focusNode!.unfocus();
      await tester.pump();
      expect(c.document.nodes.single.properties['text'], 'Židle AV ffi');
      expect(c.document.nodes.single.style, node.style);
      expect(c.document.nodes.single.x, node.x);
      c.undo();
      expect(c.document.nodes.single.toJson(), node.toJson());
      expect(c.canUndo, isFalse);
    },
  );

  testWidgets(
    'inline editor keeps an independent accessible text-field boundary',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 300,
        y: 200,
        label: 'Table 1',
        surface: const {'type': 'rect'},
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(
          nodes: [node],
          attachments: [],
          selectionUnits: [],
          sections: [],
          presets: [],
        ),
      );
      c.select({node.id});
      await open(tester, c);
      surface(tester).onTap!(const Offset(300, 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final field = tester.getSemantics(inline);
      expect(field.getSemanticsData().flagsCollection.isTextField, isTrue);
      expect(
        field.getSemanticsData().flagsCollection.isFocused,
        ui.Tristate.isTrue,
      );
      expect(field.getSemanticsData().value, 'Table 1');
      final canvas = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label ?? '').startsWith('Layout canvas.'),
      );
      expect(tester.getSemantics(canvas).id, isNot(field.id));
      expect(
        tester
            .getSemantics(canvas)
            .getSemanticsData()
            .flagsCollection
            .isTextField,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(inline, findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('inline table rename preserves geometry and commits one undo', (
    tester,
  ) async {
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      x: 300,
      y: 200,
      width: 180,
      height: 100,
      rotation: 30,
      label: 'Table 1',
      surface: const {'type': 'rect'},
    );
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(
        nodes: [node],
        attachments: [],
        selectionUnits: [],
        sections: [],
        presets: [],
      ),
    );
    c.select({node.id});
    await open(tester, c);
    surface(tester).onTap!(const Offset(300, 200));
    await tester.pump();
    expect(inline, findsOneWidget);
    await tester.enterText(inline, 'Family table');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(inline, findsNothing);
    expect(c.document.nodes.single.label, 'Family table');
    expect(c.document.nodes.single.id, node.id);
    expect(c.document.nodes.single.x, node.x);
    expect(c.document.nodes.single.y, node.y);
    expect(c.document.nodes.single.rotation, node.rotation);
    c.undo();
    expect(c.document.nodes.single.label, 'Table 1');
    expect(c.canUndo, isFalse);
  });

  testWidgets(
    'new text immediately edits inline and creation plus text is one undo',
    (tester) async {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(tester, c);
      final search = find
          .byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Find object',
          )
          .first;
      await tester.enterText(search, 'Text');
      await tester.pump();
      await tester.tap(find.text('Text').last);
      await tester.pump();
      surface(tester).onTap!(const Offset(300, 200));
      await tester.pump();
      expect(inline, findsOneWidget);
      final field = tester.widget<TextField>(inline);
      expect(
        field.controller!.selection,
        TextSelection(
          baseOffset: 0,
          extentOffset: field.controller!.text.length,
        ),
      );
      await tester.enterText(inline, 'Welcome');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(c.document.nodes.single.properties['text'], 'Welcome');
      expect(c.document.nodes.single.label, isEmpty);
      c.undo();
      expect(c.document.nodes, isEmpty);
      expect(c.canUndo, isFalse);
    },
  );

  testWidgets(
    'dragging new text opens inline and Escape rolls back insertion',
    (tester) async {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(tester, c);
      final search = find
          .byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Find object',
          )
          .first;
      await tester.enterText(search, 'Text');
      await tester.pump();
      final tile = find.byWidgetPredicate(
        (w) => w is Draggable<String> && w.data == 'Text',
      );
      final canvas = find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onDrop != null,
      );
      await tester.dragFrom(
        tester.getCenter(tile),
        tester.getCenter(canvas) - tester.getCenter(tile),
      );
      await tester.pumpAndSettle();
      expect(inline, findsOneWidget);
      expect(c.document.nodes.single.kind, 'text');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(inline, findsNothing);
      expect(c.document.nodes, isEmpty);
      expect(c.canUndo, isFalse);
    },
  );

  testWidgets('inline Escape cancels and IME composing Enter does not submit', (
    tester,
  ) async {
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'text',
      x: 300,
      y: 200,
      properties: {'text': 'Before'},
    );
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(
        nodes: [node],
        attachments: [],
        selectionUnits: [],
        sections: [],
        presets: [],
      ),
    );
    await open(tester, c);
    surface(tester).onDoubleTapAt!(const Offset(300, 200));
    await tester.pump();
    final field = tester.widget<TextField>(inline);
    field.controller!.value = const TextEditingValue(
      text: 'Draft',
      selection: TextSelection.collapsed(offset: 5),
      composing: TextRange(start: 0, end: 5),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(inline, findsOneWidget);
    expect(c.document.nodes.single.properties['text'], 'Before');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(inline, findsNothing);
    expect(c.document.nodes.single.properties['text'], 'Before');
    expect(c.canUndo, isFalse);
    surface(tester).onDoubleTapAt!(const Offset(300, 200));
    await tester.pump();
    await tester.enterText(inline, 'After blur');
    tester.widget<TextField>(inline).focusNode!.unfocus();
    await tester.pump();
    expect(c.document.nodes.single.properties['text'], 'After blur');
    c.undo();
    expect(c.document.nodes.single.properties['text'], 'Before');
  });

  testWidgets('locked objects have no handles or inline editing', (
    tester,
  ) async {
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      x: 300,
      y: 200,
      locked: true,
      surface: const {'type': 'rect'},
    );
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(
        nodes: [node],
        attachments: [],
        selectionUnits: [],
        sections: [],
        presets: [],
      ),
    );
    c.select({node.id});
    await open(tester, c);
    expect(find.byTooltip('Resize handle'), findsNothing);
    expect(find.byTooltip('Rotate handle'), findsNothing);
    surface(tester).onTap!(const Offset(300, 200));
    surface(tester).onDoubleTapAt!(const Offset(300, 200));
    await tester.pump();
    expect(inline, findsNothing);
  });

  testWidgets('eight compact handles resize from the opposite edge', (
    tester,
  ) async {
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'shape',
      x: 300,
      y: 200,
      width: 180,
      height: 100,
    );
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(
        nodes: [node],
        attachments: [],
        selectionUnits: [],
        sections: [],
        presets: [],
      ),
    );
    c.select({node.id});
    await open(tester, c);
    for (final mode in [
      'Resize',
      'Resize n',
      'Resize e',
      'Resize s',
      'Resize w',
      'Resize nw',
      'Resize ne',
      'Resize sw',
    ]) {
      final handle = find.byTooltip('$mode handle');
      expect(handle, findsOneWidget);
      final target = tester.getSize(handle);
      expect(target.width, inInclusiveRange(10, 24));
      expect(target.height, target.width);
    }
    surface(tester).onHandleStart!('Resize w', const Offset(210, 200));
    surface(tester).onDragUpdate!(const Offset(190, 200));
    surface(tester).onDragEnd!();
    expect(c.document.nodes.single.width, 200);
    expect(c.document.nodes.single.height, 100);
    expect(c.document.nodes.single.x, 290);
    expect(c.document.nodes.single.x + c.document.nodes.single.width / 2, 390);
    c.undo();
    expect(c.document.nodes.single.width, 180);
    expect(c.document.nodes.single.x, 300);
  });

  test(
    'selection outlines bounds without painting over object paths',
    () async {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 100,
        y: 100,
        width: 40,
        height: 40,
        properties: {'shape': 'ellipse'},
        style: {'fill': '#000000FF'},
      );
      final doc = VenueLayoutDocument.empty().copyWith(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 200,
          'height': 200,
          'fill': '#FFFFFFFF',
        },
        nodes: [node],
      );
      final painter = LayoutScenePainter(
        scene: compileScene(doc),
        resources: const {},
        selected: {node.id},
        selectionHulls: const [
          [
            [80, 80],
            [120, 80],
            [120, 120],
            [80, 120],
          ],
        ],
        scale: 1,
        offset: Offset.zero,
        canvasColor: Colors.white,
        selectionColor: Colors.blue,
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(200, 200));
      final picture = recorder.endRecording();
      final image = await picture.toImage(200, 200);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      // Near the ellipse curve, away from the rectangular selection outline.
      final at = (86 * 200 + 86) * 4;
      expect(pixels[at + 2], lessThan(80));
      image.dispose();
      picture.dispose();
    },
  );
}
