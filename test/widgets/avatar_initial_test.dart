import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/widgets/avatar_initial.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final (family, path) in [
      ('AvatarFutura', 'automation/fonts/Gill Sans Bold.otf'),
      ('AvatarCerebri', 'test/fixtures/fonts/avatar-cerebri-m.ttf'),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
  });

  for (final (family, ratio) in [
    ('AvatarFutura', 0.682),
    ('AvatarCerebri', 1445 / 2048),
  ]) {
    for (final (diameter, fontSize) in [(38.0, 20.0), (60.0, 24.0)]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets('$family capital is centered at $diameter / $scale', (
          tester,
        ) async {
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: DefaultTextStyle(
                  style: const TextStyle(),
                  child: Center(
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: SizedBox.square(
                        dimension: diameter,
                        child: ColoredBox(
                          color: const Color(0xff335577),
                          child: AvatarInitial(
                            initial: 'M',
                            capHeightRatio: ratio,
                            style: TextStyle(
                              fontFamily: family,
                              fontSize: fontSize,
                              fontWeight: FontWeight.bold,
                              height: 1,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 3);
            final pixels = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            var top = image.height;
            var bottom = -1;
            for (var y = 0; y < image.height; y++) {
              for (var x = 0; x < image.width; x++) {
                final offset = (y * image.width + x) * 4;
                if (pixels[offset] > 240 &&
                    pixels[offset + 1] > 240 &&
                    pixels[offset + 2] > 240) {
                  if (y < top) top = y;
                  if (y > bottom) bottom = y;
                }
              }
            }
            expect(
              bottom,
              greaterThan(top),
              reason: 'the real glyph must render',
            );
            expect(
              (top + bottom + 1) / 6,
              closeTo(diameter / 2, 0.75),
              reason: 'center visible capital ink, not the font line box',
            );
            if (const bool.fromEnvironment('CAPTURE_AVATAR_UI') &&
                diameter == 38 &&
                scale == 1) {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('/tmp/festapp-avatar-$family.png')
                  .writeAsBytes(png!.buffer.asUint8List());
            }
            image.dispose();
          });
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
