import 'package:fstapp/services/locale_date_time.dart';

import '../sale_opening_strings.dart';
import 'sale_opening_notification.dart';

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
  DateTime targetTime,
  VoidCallback onFinished,
) => HtmlEmbeddedBlock(
  cssClass: 'form-countdown',
  label: FormStrings.labelCountdownTimer,
  builder: (_) => CountdownWidget(
    targetTime: targetTime,
    onFinished: onFinished,
    compact: true,
  ),
);

class CountdownContent extends StatelessWidget {
  const CountdownContent({
    super.key,
    required this.targetTime,
    required this.onFinished,
    this.html,
    this.showTimer = true,
    this.canSubscribe = false,
    this.formLink = '',
    this.hasTickets = true,
    this.informal = false,
  });
  final DateTime targetTime;
  final VoidCallback onFinished;
  final String? html;
  // Defaults preserve the existing countdown-only call sites.
  final bool showTimer;
  final bool canSubscribe;
  final String formLink;
  final bool hasTickets, informal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        if (showTimer)
          Text(
            LocaleDateTime.dateTimeCell(
              targetTime,
              Localizations.localeOf(context).toString(),
            ),
          ),
        HtmlView(
          html:
              '<div style="text-align: center;">${showTimer ? countdownContent(html) : html ?? ''}</div>',
          fontSize: 24,
          embeddedBlocks: [
            showTimer
                ? countdownBlock(targetTime, onFinished)
                : HtmlEmbeddedBlock(
                    cssClass: 'form-countdown',
                    builder: (_) => const SizedBox.shrink(),
                  ),
            HtmlEmbeddedBlock(
              cssClass: 'form-sale-opening-notification',
              label: SaleOpeningStrings.title,
              builder: (_) => canSubscribe
                  ? SaleOpeningNotification(
                      formLink: formLink,
                      hasTickets: hasTickets,
                      informal: informal,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    ),
  );
}

const saleOpeningBlockHtml =
    '<div class="html-editor-block form-sale-opening-notification"></div>';
String insertSaleOpeningBlock(String html) {
  final root = parser.parseFragment(html);
  if (root.querySelector('.html-editor-block.form-sale-opening-notification') !=
      null)
    return html;
  final countdown = root.querySelector('.html-editor-block.form-countdown');
  final slot = parser.parseFragment(saleOpeningBlockHtml).nodes.first;
  if (countdown != null) {
    final parent = countdown.parentNode!;
    parent.nodes.insert(parent.nodes.indexOf(countdown) + 1, slot);
  } else {
    root.nodes.add(slot);
  }
  return root.outerHtml;
}

HtmlEmbeddedBlock saleOpeningPreviewBlock() => HtmlEmbeddedBlock(
  cssClass: 'form-sale-opening-notification',
  label: SaleOpeningStrings.title,
  builder: (_) => const SaleOpeningNotification(formLink: '', preview: true),
);
