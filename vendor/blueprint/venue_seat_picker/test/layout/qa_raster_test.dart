import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  const enabled = bool.hasEnvironment('QA_FIXTURES');
  testWidgets(
    'actual Flutter painter fixed camera raster motion corpus',
    (tester) async {
      final dir = const String.fromEnvironment(
        'QA_FIXTURES',
        defaultValue: 'build/qa/fixtures',
      );
      final fixture =
          jsonDecode(File('$dir/report.json').readAsStringSync()) as Map;
      final out = Directory('$dir/raster')..createSync(recursive: true);
      final resources = Map<String, dynamic>.from(fixture['resources']);
      final images = <String, ui.Image>{};
      await tester.runAsync(() async {
        for (final entry in (resources['assets'] as Map? ?? {}).entries) {
          final codec = await ui.instantiateImageCodec(
            Uri.parse(entry.value['url'] as String).data!.contentAsBytes(),
          );
          images[entry.key as String] = (await codec.getNextFrame()).image;
          codec.dispose();
        }
      });
      resources['images'] = images;
      addTearDown(() {
        for (final image in images.values) {
          image.dispose();
        }
      });

      for (final f in fixture['fixtures'] as List) {
        for (final motion in f['motion'] as List) {
          for (final width in fixture['widths'] as List? ?? [360, 900, 1440]) {
            for (final dpr in fixture['dprs'] as List? ?? [1, 2]) {
              for (final zoom
                  in motion['zoom'] != null
                      ? [motion['zoom']]
                      : [.5, 1.0, 2.0]) {
                final key = GlobalKey();
                await tester.binding.setSurfaceSize(
                  Size(
                    (width as num).toDouble(),
                    (fixture['viewportHeight'] as num? ?? 900).toDouble(),
                  ),
                );
                await tester.pumpWidget(
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: RepaintBoundary(
                      key: key,
                      child: ColoredBox(
                        color: Colors.white,
                        child: CustomPaint(
                          painter: LayoutScenePainter(
                            scene: Map<String, dynamic>.from(motion['scene']),
                            resources: resources,
                            selected: {},
                            scale: (zoom as num).toDouble(),
                            offset: Offset.zero,
                            canvasColor: Colors.white,
                            selectionColor: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pump();
                final boundary =
                    key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = (await tester.runAsync(
                  () => boundary.toImage(pixelRatio: (dpr as num).toDouble()),
                ))!;
                final bytes = (await tester.runAsync(
                  () => image.toByteData(format: ui.ImageByteFormat.png),
                ))!;
                final name =
                    '${f['name']}-${((motion['t'] as num) * 240).round()}-$width-$dpr-$zoom';
                File(
                  '${out.path}/$name.png',
                ).writeAsBytesSync(bytes.buffer.asUint8List());
                image.dispose();
              }
            }
          }
        }
      }
      await tester.binding.setSurfaceSize(null);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
