import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_email_preview.dart';
import 'package:fstapp/components/occasion/setup/setup_email_document.dart';

void main() {
  testWidgets(
      'email preview preserves server HTML including wrapper styles and images',
      (tester) async {
    const source =
        '<html><head><style>p {color:red}</style></head><body style="background:white"><p style="font-family:serif">Exact body</p><img src="data:image/png;base64," alt="Logo"></body></html>';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OccasionSetupEmailPreview(draft: const {
      'title': 'Test'
    }, loadPreview: (_) async => {'html': source, 'subject': 'Subject'}))));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(
        tester.widget<SetupEmailDocument>(find.byType(SetupEmailDocument)).html,
        source);
    expect(tester.widget<HtmlWidget>(find.byType(HtmlWidget)).html, source);
  });
}
