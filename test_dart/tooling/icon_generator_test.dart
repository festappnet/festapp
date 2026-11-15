import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:test/test.dart';

import '../../scripts/generate_icons.dart';

void main() {
  test(
    'one tenant artwork supplies every browser icon and ICO frame',
    () async {
      final root = await Directory.systemTemp.createTemp('festapp-icon-test-');
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/brand.png');
      await source.writeAsBytes(
        image.encodePng(
          image.Image(width: 64, height: 64)
            ..clear(image.ColorRgb8(211, 156, 10)),
        ),
      );
      await generateWebIcons(source, root);
      for (final entry in {
        'favicon-16x16.png': 16,
        'favicon-32x32.png': 32,
        'apple-touch-icon.png': 180,
        'android-chrome-192x192.png': 192,
        'android-chrome-512x512.png': 512,
        'web-app-manifest-192x192.png': 192,
        'web-app-manifest-512x512.png': 512,
      }.entries) {
        final icon = image.decodePng(
          await File('${root.path}/web/${entry.key}').readAsBytes(),
        )!;
        expect(icon.width, entry.value);
        expect(icon.height, entry.value);
        expect(icon.getPixel(0, 0).r, 211);
      }
      final ico = image.IcoDecoder().decode(
        await File('${root.path}/web/favicon.ico').readAsBytes(),
      )!;
      expect(ico.frames.map((frame) => frame.width), [16, 32, 48]);
      expect(
        await File('${root.path}/web/favicon.svg').readAsString(),
        contains('data:image/png;base64,'),
      );
      expect(
        File('${root.path}/assets/icons/fstappicon.png').existsSync(),
        isFalse,
        reason:
            'Web icon generation must not overwrite the tenant source artwork',
      );
    },
  );
}
