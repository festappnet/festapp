import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'package:fstapp/components/ticket_layout/ticket_text.dart';

void main() {
  final metrics = TicketFontMetrics({
    for (final c in 'Slavnostnívečer PřílišDlouhéSlovoBezMezer…?'.runes)
      String.fromCharCode(c): .5
  }, .8, -.2);
  TicketElement element(
          {String binding = 'occasionTitle',
          double width = 90,
          double height = 180,
          double minimum = 6,
          int lines = 4}) =>
      TicketElement(
          id: 'title',
          binding: binding,
          box: Rect.fromLTWH(0, 0, width, height),
          fontSize: 32,
          minFontSize: minimum,
          maxLines: lines);
  test('long words stay complete while titles and names shrink', () {
    for (final binding in ['occasionTitle', 'orderName']) {
      final fit =
          fitTicketText('Slavnostní večer', element(binding: binding), metrics);
      expect(fit.size, lessThan(32));
      expect(fit.lines, ['Slavnostní', 'večer']);
      expect(fit.overflow, isFalse);
    }
  });
  test('full title fits below its preferred minimum without ellipsis', () {
    const text = 'PřílišDlouhéSlovoBezMezer';
    final fit = fitTicketText(
        text, element(width: 50, height: 20, minimum: 18, lines: 1), metrics);
    expect(fit.lines, [text]);
    expect(fit.size, lessThan(18));
    expect(fit.overflow, isFalse);
  });
  test('explicit newlines remain line boundaries', () {
    final fit = fitTicketText('Slavnostní\nvečer', element(), metrics);
    expect(fit.lines, ['Slavnostní', 'večer']);
    expect(fit.overflow, isFalse);
  });
}
