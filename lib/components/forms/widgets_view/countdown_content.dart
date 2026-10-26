import 'package:flutter/widgets.dart';
import 'package:html/parser.dart' as parser;
import '../../html/html_embedded_block.dart';
import '../../html/html_view.dart';
import '../form_strings.dart';
import 'countdown_widget.dart';

const countdownBlockHtml =
    '<div class="html-editor-block form-countdown"></div>';

String countdownContent(String? title) {
  final content = title == null
      ? '<p>${FormStrings.registrationStart}</p>'
      : title.trim().isEmpty
          ? '<p><br></p>'
          : title;
  if (parser
          .parseFragment(content)
          .querySelector('div.html-editor-block.form-countdown') !=
      null) {
    return content;
  }
  return '$content$countdownBlockHtml<p><br></p>';
}

HtmlEmbeddedBlock countdownBlock(
        DateTime targetTime, VoidCallback onFinished) =>
    HtmlEmbeddedBlock(
      cssClass: 'form-countdown',
      builder: (_) => CountdownWidget(
          targetTime: targetTime, onFinished: onFinished, compact: true),
    );

class CountdownContent extends StatelessWidget {
  const CountdownContent(
      {super.key,
      required this.targetTime,
      required this.onFinished,
      this.html});
  final DateTime targetTime;
  final VoidCallback onFinished;
  final String? html;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: HtmlView(
          html:
              '<div style="text-align: center;">${countdownContent(html)}</div>',
          fontSize: 24,
          embeddedBlock: countdownBlock(targetTime, onFinished),
        ),
      );
}
