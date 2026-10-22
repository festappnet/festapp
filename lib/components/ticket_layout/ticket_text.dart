import 'dart:ui';
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

// Synthetic emphasis uses the bundled font in both Canvas and PDF, with the
// same outline width and 12-degree shear. Reserve its overhang during fitting.
({double left, double right}) ticketTextInsets(
        TicketElement e, TicketFontMetrics m) =>
    (
      left:
          (e.bold ? .02 : 0) + (e.italic ? -m.descent * .2125565616700221 : 0),
      right: (e.bold ? .02 : 0) + (e.italic ? m.ascent * .2125565616700221 : 0)
    );

TicketTextFit fitTicketText(String text, TicketElement e, TicketFontMetrics m) {
  final inset = ticketTextInsets(e, m);
  double width(String text, double size) =>
      m.width(text, size) +
      (text.isEmpty ? 0 : (inset.left + inset.right) * size);
  final replaced = text.runes
      .any((r) => r != 10 && !m.advances.containsKey(String.fromCharCode(r)));
  text = text.runes
      .map((r) => r == 10 || m.advances.containsKey(String.fromCharCode(r))
          ? String.fromCharCode(r)
          : '?')
      .join();
  List<String> wrap(double size) {
    final lines = <String>[], paragraphs = text.split('\n');
    for (var i = 0; i < paragraphs.length; i++) {
      var line = '';
      for (final match in RegExp(r'[^ ]+| +').allMatches(paragraphs[i])) {
        final token = match.group(0)!;
        if (token.startsWith(' ')) {
          line += token;
          continue;
        }
        if (line.trim().isNotEmpty && width(line + token, size) > e.box.width) {
          lines.add(line.trimRight());
          line = token;
        } else {
          line += token;
        }
      }
      if (line.isNotEmpty || i < paragraphs.length - 1)
        lines.add(line.trimRight());
    }
    return lines;
  }

  var size = e.fontSize, lines = wrap(e.fontSize);
  bool fits() =>
      lines.length <= e.maxLines &&
      (lines.isEmpty ||
          ((lines.length - 1) * 1.2 + m.ascent - m.descent) * size <=
              e.box.height) &&
      lines.every((l) => width(l, size) <= e.box.width + .001);
  // Match the PDF: preserve complete titles even below the preferred minimum.
  final minimum = e.binding == 'occasionTitle'
      ? math.min(e.minFontSize, .1)
      : e.minFontSize;
  while (!fits() && size > minimum) {
    size = math.max(minimum, size - .5);
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
    if (lines.isEmpty || width('…', size) > e.box.width) {
      lines = [];
    } else {
      lines = [
        for (var i = 0; i < lines.length; i++)
          (() {
            var line = lines[i];
            if (i < lines.length - 1 && width(line, size) <= e.box.width)
              return line;
            while (line.isNotEmpty && width('$line…', size) > e.box.width) {
              line =
                  String.fromCharCodes(line.runes.take(line.runes.length - 1));
            }
            return '$line…';
          })()
      ];
    }
  }
  return TicketTextFit(size, lines, lines.map((l) => width(l, size)).toList(),
      overflow, replaced);
}

/// Grow an undersized ticket-code box, keeping it on the ticket and clear of QR.
TicketTemplate ensureTicketCodeFits(
    TicketTemplate doc, TicketFontMetrics metrics) {
  final code = doc.elements.firstWhere((e) => e.binding == 'ticketSymbol');
  const sample = 'XXXX9W9W9W';
  try {
    fitTicketText(sample, code, metrics);
    return doc;
  } on FormatException {
    // The code is required: enlarge its box instead of truncating or hiding it.
  }
  final inset = ticketTextInsets(code, metrics);
  final width = math.max(
      code.box.width,
      metrics.width(sample, code.minFontSize) +
          (inset.left + inset.right) * code.minFontSize +
          .01);
  final height = math.max(code.box.height,
      (metrics.ascent - metrics.descent) * code.minFontSize + .01);
  if (width > doc.area.width || height > doc.area.height) return doc;
  final qr = doc.elements.firstWhere((e) => e.binding == 'qr').box;
  Rect box(Offset p) => Rect.fromLTWH(p.dx.clamp(0, doc.area.width - width),
      p.dy.clamp(0, doc.area.height - height), width, height);
  final candidates = [
    code.box.topLeft,
    Offset(qr.right + 2, code.box.top),
    Offset(qr.left - width - 2, code.box.top),
    Offset(code.box.left, qr.bottom + 2),
    Offset(code.box.left, qr.top - height - 2)
  ].map(box).where((b) => !b.overlaps(qr)).toList()
    ..sort((a, b) => (a.topLeft - code.box.topLeft)
        .distance
        .compareTo((b.topLeft - code.box.topLeft).distance));
  if (candidates.isEmpty) return doc;
  return doc.replace(code.copyWith(box: candidates.first));
}
