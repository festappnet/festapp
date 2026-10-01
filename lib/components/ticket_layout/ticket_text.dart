import 'dart:math' as math;
import 'models/ticket_layout.dart';

class TicketFontMetrics {
  final Map<String, double> advances;
  final double ascent, descent;
  const TicketFontMetrics(this.advances, this.ascent, this.descent);
  factory TicketFontMetrics.fromJson(Map j) => TicketFontMetrics(
      (j['advances'] as Map)
          .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      (j['ascent'] as num).toDouble(),
      (j['descent'] as num).toDouble());
  double width(String text, double size) => text.runes.fold(
      0.0,
      (n, c) =>
          n + (advances[String.fromCharCode(c)] ?? advances['?'] ?? 0) * size);
}

class TicketTextFit {
  final double size;
  final List<String> lines;
  final List<double> widths;
  final bool overflow;
  final bool replaced;
  const TicketTextFit(
      this.size, this.lines, this.widths, this.overflow, this.replaced);
}

TicketTextFit fitTicketText(String text, TicketElement e, TicketFontMetrics m) {
  final replaced = text.runes
      .any((r) => r != 10 && !m.advances.containsKey(String.fromCharCode(r)));
  text = text.runes
      .map((r) => r == 10 || m.advances.containsKey(String.fromCharCode(r))
          ? String.fromCharCode(r)
          : '?')
      .join();
  List<String> wrap(double size) {
    final lines = <String>[];
    var line = '';
    for (final rune in text.runes) {
      final c = String.fromCharCode(rune);
      if (c == '\n') {
        lines.add(line);
        line = '';
        continue;
      }
      if (m.width(line + c, size) > e.box.width && line.isNotEmpty) {
        final split = line.lastIndexOf(' ');
        if (split > 0) {
          lines.add(line.substring(0, split));
          line = line.substring(split + 1) + c;
        } else {
          lines.add(line);
          line = c;
        }
      } else {
        line += c;
      }
    }
    if (line.isNotEmpty) lines.add(line.trimRight());
    return lines;
  }

  var size = e.fontSize, lines = wrap(e.fontSize);
  bool fits() =>
      lines.length <= e.maxLines &&
      (lines.isEmpty ||
          ((lines.length - 1) * 1.2 + m.ascent - m.descent) * size <=
              e.box.height) &&
      lines.every((l) => m.width(l, size) <= e.box.width + .001);
  while (!fits() && size > e.minFontSize) {
    size = math.max(e.minFontSize, size - .5);
    lines = wrap(size);
  }
  final overflow = !fits();
  if (overflow && e.binding == 'ticketSymbol') {
    throw const FormatException('ticketSymbol');
  }
  if (overflow) {
    lines = lines
        .take(math.max(
            0,
            math.min(
                e.maxLines,
                ((e.box.height / size - m.ascent + m.descent) / 1.2).floor() +
                    1)))
        .toList();
    if (lines.isEmpty || m.width('…', size) > e.box.width) {
      lines = [];
    } else {
      var last = lines.removeLast();
      while (last.isNotEmpty && m.width('$last…', size) > e.box.width) {
        last = String.fromCharCodes(last.runes.take(last.runes.length - 1));
      }
      lines.add('$last…');
    }
  }
  return TicketTextFit(size, lines, lines.map((l) => m.width(l, size)).toList(),
      overflow, replaced);
}
