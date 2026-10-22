import 'dart:math' as math;

String ticketThemeColor(String hex, String primary, String secondary) {
  List<double> channels(String value) => [0, 2, 4]
      .map((i) => int.parse(value.substring(i, i + 2), radix: 16).toDouble())
      .toList();
  double luminance(List<double> rgb) {
    final linear = rgb.map((v) {
      final c = v / 255;
      return c <= .04045
          ? c / 12.92
          : math.pow((c + .055) / 1.055, 2.4).toDouble();
    }).toList();
    return linear[0] * .2126 + linear[1] * .7152 + linear[2] * .0722;
  }

  final source = channels(hex), desired = luminance(source);
  if (source.reduce(math.max) - source.reduce(math.min) < 8 &&
      (desired > .94 || desired < .002)) return hex.toUpperCase();
  final warm = source[0] > source[1] * 1.03 && source[0] > source[2] * 1.12;
  final target = channels(warm ? secondary : primary),
      end = luminance(target) < desired ? 255.0 : 0.0;
  var low = 0.0, high = 1.0;
  for (var i = 0; i < 24; i++) {
    final blend = (low + high) / 2,
        rgb = target.map((c) => c + (end - c) * blend).toList();
    if ((luminance(rgb) < desired) == (end == 255)) {
      low = blend;
    } else {
      high = blend;
    }
  }
  return target
      .map((c) => (c + (end - c) * (low + high) / 2)
          .round()
          .toRadixString(16)
          .padLeft(2, '0'))
      .join()
      .toUpperCase();
}
