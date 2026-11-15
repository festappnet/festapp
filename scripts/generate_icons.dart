// Generate browser icons from the selected tenant's canonical square PNG.
// Usage: fvm dart run scripts/generate_icons.dart <source.png> [--output-root <dir>]
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;

Future<void> generateWebIcons(File source, Directory root) async {
  final input = image.decodePng(await source.readAsBytes());
  if (input == null || input.width != input.height) {
    throw ArgumentError('Browser icon source must be a square PNG');
  }
  final web = Directory('${root.path}/web');
  await web.create(recursive: true);
  image.Image resize(int size) => image.copyResize(
    input,
    width: size,
    height: size,
    interpolation: image.Interpolation.average,
  );
  const targets = {
    'favicon-16x16.png': 16,
    'favicon-32x32.png': 32,
    'apple-touch-icon.png': 180,
    'android-chrome-192x192.png': 192,
    'android-chrome-512x512.png': 512,
    'web-app-manifest-192x192.png': 192,
    'web-app-manifest-512x512.png': 512,
  };
  for (final entry in targets.entries) {
    await File('${web.path}/${entry.key}')
        .writeAsBytes(image.encodePng(resize(entry.value)));
  }
  await File('${web.path}/favicon.ico').writeAsBytes(
    image.IcoEncoder().encodeImages([
      for (final size in [16, 32, 48]) resize(size),
    ]),
  );
  final png = base64Encode(image.encodePng(resize(512)));
  await File('${web.path}/favicon.svg').writeAsString(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'
    '<image width="512" height="512" href="data:image/png;base64,$png"/>'
    '</svg>\n',
  );
}

Future<void> main(List<String> args) async {
  if (args.length != 1 && !(args.length == 3 && args[1] == '--output-root')) {
    stderr.writeln(
      'Usage: fvm dart run scripts/generate_icons.dart <source.png> [--output-root <dir>]',
    );
    exitCode = 64;
    return;
  }
  final root = args.length == 3
      ? Directory(args[2])
      : File.fromUri(Platform.script).parent.parent;
  await generateWebIcons(File(args[0]), root);
  stdout.writeln('Generated browser icons from selected tenant artwork.');
}
