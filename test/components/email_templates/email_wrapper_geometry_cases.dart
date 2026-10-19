import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/email_templates/email_preview_html.dart';

const _message = '<p style="margin:0">Message content</p>';

// Exact banner producer structure, including its intentionally full-width image.
String _bannerWrapper({required bool inset}) =>
    '<div style="font-family: Arial, sans-serif; font-size: 16px; max-width: 680px; margin: 0 auto;">'
    '<div style="text-align: center;">'
    '<img src="cid:fixture-banner" alt="Banner" style="width: 100%; height: auto; display: block;">'
    '</div>'
    '<div style="margin-top: 10px; margin-bottom: 10px;${inset ? ' padding-left: 24px; padding-right: 24px;' : ''}">'
    '$_message</div></div>';

Future<Rect> _render(WidgetTester tester, String html, double width) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, child: EmailPreviewHtml(html: html)),
  ))));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return tester.getRect(find.text('Message content', findRichText: true));
}

void main() {
  testWidgets('explicit div padding preserves invisible content bounds',
      (tester) async {
    final text =
        await _render(tester, '<div style="padding:24px">$_message</div>', 320);
    expect(text.left, closeTo(24, 0.1));
    expect(text.top, closeTo(24, 0.1));
    expect(text.right, closeTo(296, 0.1));
  });

  testWidgets('table cell padding preserves invisible content bounds',
      (tester) async {
    final text = await _render(
        tester,
        '<table style="width:100%;border-collapse:collapse;border-spacing:0"><tr><td style="padding:24px">$_message</td></tr></table>',
        320);
    expect(text.left, closeTo(24, 0.1));
    expect(text.top, closeTo(24, 0.1));
    expect(text.right, closeTo(296, 0.1));
  });

  for (final width in [320.0, 800.0]) {
    for (final inset in [false, true]) {
      testWidgets(
          '${inset ? 'corrected' : 'original'} banner wrapper at $width respects source bounds',
          (tester) async {
        final text = await _render(tester, _bannerWrapper(inset: inset), width);
        final wrapperWidth = width > 680 ? 680.0 : width;
        final wrapperLeft = (width - wrapperWidth) / 2;
        final padding = inset ? 24.0 : 0.0;
        expect(text.left, closeTo(wrapperLeft + padding, 0.1));
        expect(text.right, closeTo(wrapperLeft + wrapperWidth - padding, 0.1));
        final banner = tester.getRect(find.byIcon(Icons.image_outlined));
        expect(banner.center.dx, closeTo(width / 2, 0.1));
        expect(text.top - (banner.center.dy + 24), closeTo(10, 0.1));
      });
    }
  }
}
