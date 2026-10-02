import 'dart:math' as math;
import 'dart:typed_data';

/// Representative artwork colors, ordered by coverage and perceptual diversity.
/// Transparent pixels and tiny isolated details do not compete with the artwork.
List<String> ticketImagePalette(Uint8List rgba, {int limit = 5}) {
  final bins = <int, List<int>>{};
  var count = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 192) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
    final bin = bins.putIfAbsent(key, () => [0, 0, 0, 0]);
    bin[0]++;
    bin[1] += r;
    bin[2] += g;
    bin[3] += b;
    count++;
  }
  final candidates = bins.values
      .where((b) => b[0] >= math.max(1, count * .005))
      .map((b) => _PaletteColor(b[0], (b[1] / b[0]).round(),
          (b[2] / b[0]).round(), (b[3] / b[0]).round()))
      .toList()
    ..sort((a, b) {
      final coverage = b.count.compareTo(a.count);
      return coverage != 0 ? coverage : a.hex.compareTo(b.hex);
    });
  final selected = <_PaletteColor>[];
  while (candidates.isNotEmpty && selected.length < limit) {
    _PaletteColor? best;
    var bestScore = -1.0;
    for (final candidate in candidates) {
      final distance = selected.isEmpty
          ? 1.0
          : selected.map((s) => candidate.distance(s)).reduce(math.min);
      // Do not fill the palette with near-identical neutral shades.
      if (distance < .10) continue;
      final chroma = math.sqrt(candidate.lab[1] * candidate.lab[1] +
          candidate.lab[2] * candidate.lab[2]);
      final score = selected.isEmpty
          ? candidate.count.toDouble()
          : math.sqrt(candidate.count / count) * distance * (1 + chroma * 2);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    if (best == null) break;
    selected.add(best);
    candidates.remove(best);
  }
  return selected.map((c) => c.hex).toList();
}

class _PaletteColor {
  final int count, r, g, b;
  _PaletteColor(this.count, this.r, this.g, this.b);
  String get hex => ((r << 16) | (g << 8) | b)
      .toRadixString(16)
      .padLeft(6, '0')
      .toUpperCase();
  // OKLab makes equal distances approximate equal perceived color changes.
  late final List<double> lab = _lab();
  List<double> _lab() {
    double linear(int v) {
      final c = v / 255;
      return c <= .04045
          ? c / 12.92
          : math.pow((c + .055) / 1.055, 2.4).toDouble();
    }

    final red = linear(r), green = linear(g), blue = linear(b);
    final l = math.pow(
        .4122214708 * red + .5363325363 * green + .0514459929 * blue, 1 / 3);
    final m = math.pow(
        .2119034982 * red + .6806995451 * green + .1073969566 * blue, 1 / 3);
    final s = math.pow(
        .0883024619 * red + .2817188376 * green + .6299787005 * blue, 1 / 3);
    return [
      (.2104542553 * l + .793617785 * m - .0040720468 * s).toDouble(),
      (1.9779984951 * l - 2.428592205 * m + .4505937099 * s).toDouble(),
      (.0259040371 * l + .7827717662 * m - .808675766 * s).toDouble()
    ];
  }

  double distance(_PaletteColor other) => math.sqrt(
      List.generate(3, (i) => math.pow(lab[i] - other.lab[i], 2).toDouble())
          .reduce((a, b) => a + b));
}
