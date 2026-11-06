import '../../support/fixtures/layout_canvas_fixture.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['FESTAPP_PLAN_FOCUS_CAPTURE'] == null) return;
    await (FontLoader(
      'Futura',
    )..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final dark in [false, true]) {
    testWidgets(
      'one-shot seat cue repaints without rebuilding the viewer dark=$dark',
      (tester) async {
        final pulse = AnimationController(
          vsync: tester,
          duration: const Duration(milliseconds: 1200),
        );
        addTearDown(pulse.dispose);
        final nodes = [
          for (var n = 1; n <= 144; n++)
            LayoutNode.fromJson({
              'id': '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
              'kind': 'seat',
              'width': 22,
              'height': 22,
              'transform': {
                'x': (n % 12 < 6 ? 110 : 540) + (n % 6) * 32,
                'y': 80 + (n ~/ 12) * 110,
                'rotation': 0,
              },
            }),
        ];
        final document = VenueLayoutDocument.empty().copyWith(
          canvas: {
            'x': 0,
            'y': 0,
            'width': 850,
            'height': 1450,
            'fill': '#ffffffff',
          },
          nodes: nodes,
        );
        final own = {nodes[123].id, nodes[124].id};
        var builds = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              fontFamily: 'Futura',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff253858),
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('seat-cue'),
                child: Container(
                  color: dark
                      ? const Color(0xff101518)
                      : const Color(0xfffaf9ff),
                  width: 520,
                  height: 400,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Aktuální uložený plánek'),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 300,
                          child: Builder(
                            builder: (context) {
                              builds++;
                              return VenueLayoutViewer(
                                document: document,
                                highlightedNodeIds: own,
                                highlightPulse: pulse,
                                focusNodeIds: own,
                                focusRevision: 1,
                                focusMaxZoomFactor: 2.6,
                                focusSeatPixelSize: 12,
                                seatPresentation: {
                                  for (var n = 0; n < nodes.length; n++)
                                    nodes[n].id: {
                                      'fill': n % 7 == 0
                                          ? '#267329FF'
                                          : '#412673FF',
                                      'stateMarker': 'none',
                                      'selectable': false,
                                    },
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final initialBuilds = builds;
        Future<List<int>> pixels(String name) async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('seat-cue')),
          );
          return (await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1.5);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final data = bytes!.buffer.asUint8List();
            final dir = Platform.environment['FESTAPP_PLAN_FOCUS_CAPTURE'];
            if (dir != null) {
              Directory(dir).createSync(recursive: true);
              File('$dir/$name-${dark ? 'dark' : 'light'}.png')
                  .writeAsBytesSync(data);
            }
            image.dispose();
            return data;
          }))!;
        }

        final initialPixels = await pixels('still');
        pulse.forward();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final cuePixels = await pixels('cue');
        expect(cuePixels, isNot(orderedEquals(initialPixels)));
        expect(
          builds,
          initialBuilds,
          reason: 'Animation ticks repaint only; they never rebuild or recompile the viewer',
        );
        await tester.pumpAndSettle();
        expect(pulse.status, AnimationStatus.completed);
        expect(await pixels('finished'), orderedEquals(initialPixels));
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final (canvasSize, seatSize) in [
    (800.0, 20.0),
    (1000.0, 20.0),
    (800.0, 80.0),
    (800.0, 0.0),
    (12000.0, 20.0),
  ]) {
    testWidgets(
      'seat readability uses selected chair pixels canvas=$canvasSize seat=$seatSize',
      (tester) async {
        const own = '00000000-0000-4000-8000-000000000001';
        final document = VenueLayoutDocument.empty().copyWith(
          canvas: {
            'x': 0,
            'y': 0,
            'width': canvasSize,
            'height': canvasSize,
            'fill': '#ffffffff',
          },
          nodes: [
            LayoutNode(
              id: own,
              kind: seatSize == 0 ? 'table' : 'seat',
              width: seatSize == 0 ? 80 : seatSize,
              height: seatSize == 0 ? 80 : seatSize,
              x: canvasSize / 2,
              y: canvasSize / 2,
            ),
            LayoutNode(
              id: '00000000-0000-4000-8000-000000000002',
              kind: 'seat',
              width: 1,
              height: 1,
              x: 100,
              y: 100,
            ),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 300,
                child: VenueLayoutViewer(
                  document: document,
                  focusNodeIds: {own},
                  focusRevision: 1,
                  focusMaxZoomFactor: 2.6,
                  focusSeatPixelSize: 12,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final painter = layoutPainter(tester);
        final zoom = painter.camera!.value.entry(0, 0);
        final pixels = seatSize * painter.scale * zoom;
        if (seatSize == 80 || seatSize == 0) {
          expect(
            zoom,
            1,
            reason: 'Already readable chairs keep the full-plan camera',
          );
        } else if (canvasSize == 12000) {
          expect(
            zoom,
            closeTo(2.6, .0001),
            reason: 'Keep a modest context cap on unusually large plans',
          );
        } else {
          expect(
            pixels,
            closeTo(12, .0001),
            reason: 'Chair readability is independent of canvas size or unrelated tiny seats',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'focused readonly viewer toggles one fit control between overview and places',
    (tester) async {
      final document = VenueLayoutDocument.empty().copyWith(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 2000,
          'height': 2000,
          'fill': '#ffffffff',
        },
        nodes: [
          LayoutNode.fromJson({
            'id': '00000000-0000-4000-8000-000000000001',
            'kind': 'seat',
            'width': 20,
            'height': 20,
            'transform': {'x': 1100, 'y': 1100, 'rotation': 0},
          }),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 300,
              child: VenueLayoutViewer(
                document: document,
                focusNodeIds: const {'00000000-0000-4000-8000-000000000001'},
                focusSeatPixelSize: 12,
                focusMaxZoomFactor: 2.6,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double zoom() => layoutPainter(tester).camera.value.entry(0, 0) as double;
      final focused = zoom();
      expect(focused, greaterThan(1));
      await tester.tap(find.byTooltip('Fit plan'));
      await tester.pumpAndSettle();
      expect(zoom(), closeTo(1, .00001));
      expect(find.byTooltip('Focus places'), findsOneWidget);
      await tester.tap(find.byTooltip('Focus places'));
      await tester.pumpAndSettle();
      expect(zoom(), closeTo(focused, .00001));
      expect(find.byTooltip('Fit plan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'embedded focus zoom is capped and whole-plan reset restores scale',
    (tester) async {
      final document = VenueLayoutDocument.empty().copyWith(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 2000,
          'height': 2000,
          'fill': '#ffffffff',
        },
        nodes: [
          LayoutNode.fromJson({
            'id': '00000000-0000-4000-8000-000000000001',
            'kind': 'seat',
            'width': 20,
            'height': 20,
            'transform': {'x': 1100, 'y': 1100, 'rotation': 0},
          }),
        ],
      );
      double scale = 0;
      Future<void> show(int revision, Set<String> focus) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: 300,
                child: VenueLayoutViewer(
                  document: document,
                  focusRevision: revision,
                  focusNodeIds: focus,
                  focusMaxZoomFactor: 1.6,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        scale = layoutPainter(tester).camera.value.entry(0, 0) as double;
      }

      await show(1, {});
      final baseline = scale;
      await show(2, {document.nodes.single.id});
      expect(scale, greaterThan(baseline));
      expect(scale, closeTo(baseline * 1.6, .00001));
      await show(3, {});
      expect(scale, closeTo(baseline, .00001));
    },
  );

  testWidgets(
    'public readonly viewer focuses exact nodes and reports hits without changing geometry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = VenueLayoutDocument.empty().copyWith(
        nodes: [
          LayoutNode.fromJson({
            'id': '00000000-0000-4000-8000-000000000001',
            'kind': 'seat',
            'width': 40,
            'height': 40,
            'transform': {'x': 250, 'y': 250, 'rotation': 0},
          }),
          LayoutNode.fromJson({
            'id': '00000000-0000-4000-8000-000000000002',
            'kind': 'seat',
            'width': 40,
            'height': 40,
            'transform': {'x': 750, 'y': 750, 'rotation': 0},
          }),
        ],
        canvas: {
          'x': 0,
          'y': 0,
          'width': 1000,
          'height': 1000,
          'fill': '#ffffffff',
        },
      );
      final before = document.toJson();
      String? hit;
      Future<void> show(int revision, String focus) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueLayoutViewer(
                document: document,
                highlightedNodeIds: document.nodes.map((n) => n.id).toSet(),
                activeNodeIds: {focus},
                focusNodeIds: {focus},
                focusRevision: revision,
                onNodeTap: (id) => hit = id,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getCenter(find.byType(VenueLayoutViewer)));
        await tester.pumpAndSettle();
      }

      await show(1, document.nodes.first.id);
      expect(hit, document.nodes.first.id);
      await show(2, document.nodes.last.id);
      expect(hit, document.nodes.last.id);
      expect(document.toJson(), before);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'embedded map passes ordinary wheel scrolling to its page and reserves modifier zoom',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  SizedBox(
                    height: 300,
                    child: VenueLayoutViewer(
                      document: VenueLayoutDocument.empty(),
                      wheelZoomRequiresModifier: true,
                    ),
                  ),
                  const SizedBox(height: 1400),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final position = tester.getCenter(find.byType(VenueLayoutViewer));
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 120),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
