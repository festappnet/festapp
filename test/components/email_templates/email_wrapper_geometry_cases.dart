import 'package:festapp_core/email_templates.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fstapp/components/email_templates/email_preview_html.dart';

const _message = '<p style="margin:0">Message content</p>';

// Historical banner structure with its full-width image.
String _bannerWrapper({required bool inset}) =>
    '<div style="font-family: Arial, sans-serif; font-size: 16px; max-width: 680px; margin: 0 auto;">'
    '<div style="text-align: center;">'
    '<img src="cid:fixture-banner" alt="Banner" style="width: 100%; height: auto; display: block;">'
    '</div>'
    '<div style="margin-top: 10px; margin-bottom: 10px;${inset ? ' padding-left: 24px; padding-right: 24px;' : ''}">'
    '$_message</div></div>';

Future<Rect> _render(
  WidgetTester tester,
  String html,
  double width, {
  Uint8List? Function(String)? imageBytesResolver,
  Map<String, Object>? paymentQrSample,
}) async {
  await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
          body: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      child: EmailPreviewHtml(
        html: html,
        imageBytesResolver: imageBytesResolver,
        paymentQrSample: paymentQrSample,
      ),
    ),
  ))));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return tester.getRect(find.text('Message content', findRichText: true));
}

void main() {
  testWidgets('synthetic payment QR keeps rounded corners in a narrow preview',
      (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7QAAAABJRU5ErkJggg==',
    );
    await _render(
      tester,
      '<img src="$emailPreviewPaymentQrSource" alt="QR platba" '
      'style="border-radius:8px">$_message',
      180,
      imageBytesResolver: (source) =>
          source == emailPreviewPaymentQrSource ? png : null,
    );
    final rendered = find.byType(Image);
    expect(rendered, findsOneWidget);
    expect(tester.widget<Image>(rendered).image, MemoryImage(png));
    final clip = find.ancestor(of: rendered, matching: find.byType(ClipRRect));
    expect(tester.widget<ClipRRect>(clip).borderRadius, BorderRadius.circular(8));
    expect(tester.getRect(find.byType(FittedBox)).width, lessThanOrEqualTo(180));
    expect(find.byIcon(Icons.image_outlined), findsNothing);
  });

  testWidgets('missing artwork still shows a nonpayable sample QR and captions',
      (tester) async {
    await _render(
      tester,
      '<img src="$emailPreviewPaymentQrSource" alt="QR platba">$_message',
      180,
      paymentQrSample: {
        'title': 'Podzimní ples',
        'accountNumber': '13200132/2010',
        'iban': 'CZ22 2010 0000 0000 1320 0132',
        'currency': 'CZK',
        'locale': 'cs',
        'amount': 900,
        'reference': '20261030',
      },
    );
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Podzimní ples'), findsOneWidget);
    expect(find.text('13200132/2010'), findsOneWidget);
    expect(find.textContaining('900'), findsOneWidget);
    expect(find.textContaining('VS 20261030'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
  });

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
    testWidgets('responsive banner has equal insets at $width', (tester) async {
      final text = await _render(
        tester,
        '<div style="max-width: 680px; margin: 0 auto;">'
        '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" '
        'style="width: 100%; table-layout: fixed;"><tr>'
        '<td align="center" style="padding: 0 24px;"><img src="cid:fixture-banner" alt="Banner" '
        'width="632" style="display: block; width: 100%; max-width: 632px; height: auto; margin: 0 auto;">'
        '</td></tr></table>'
        '<div style="margin-top: 10px; margin-bottom: 10px; padding: 0 24px;">$_message</div></div>',
        width,
      );
      final banner = tester.getRect(find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Banner',
      ));
      expect(banner.center.dx, closeTo(width / 2, 0.1));
      expect(banner.left, closeTo(text.left, 0.1));
      expect(banner.right, closeTo(text.right, 0.1));
    });
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
