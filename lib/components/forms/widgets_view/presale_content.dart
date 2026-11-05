import 'package:fstapp/services/locale_date_time.dart';

import '../sale_opening_strings.dart';
import 'sale_opening_notification.dart';

import 'package:material_ui/material_ui.dart';
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

class PresaleContent extends StatelessWidget {
  const PresaleContent({
    super.key,
    required this.targetTime,
    required this.onFinished,
    this.html,
    this.showTimer = true,
    this.canSubscribe = false,
    this.formLink = '',
    this.hasTickets = true,
    this.informal = false,
    this.header,
    this.eventTitle,
    this.preview = false,
  });
  final DateTime targetTime;
  final VoidCallback onFinished;
  final String? html;
  // Defaults preserve the existing countdown-only call sites.
  final bool showTimer;
  final bool canSubscribe;
  final String formLink;
  final bool hasTickets, informal;
  final String? header;
  String get effectiveHeader => header ?? (showTimer ? 'date' : 'none');
  final String? eventTitle;
  final bool preview;

  bool get _hasVisibleContent {
    if (showTimer) return true;
    final hasSubscription =
        canSubscribe &&
        parser
                .parseFragment(html ?? '')
                .querySelector(
                  'div.html-editor-block.form-sale-opening-notification',
                ) !=
            null;
    final content = parser.parseFragment(html ?? '');
    for (final slot in content.querySelectorAll(
      '.html-editor-block.form-countdown, .html-editor-block.form-sale-opening-notification',
    )) {
      slot.remove();
    }
    return hasSubscription ||
        (content.text ?? '').replaceAll(RegExp(r'[\s\u200b]'), '').isNotEmpty ||
        content.querySelector('img,video,iframe,table,hr') != null;
  }

  bool get _subscriptionOnly {
    if (effectiveHeader != 'none' || showTimer || !canSubscribe) return false;
    final content = parser.parseFragment(html ?? '');
    final hasNotification =
        content.querySelector(
          '.html-editor-block.form-sale-opening-notification',
        ) !=
        null;
    for (final slot in content.querySelectorAll(
      '.html-editor-block.form-countdown, .html-editor-block.form-sale-opening-notification',
    )) {
      slot.remove();
    }
    return hasNotification &&
        (content.text ?? '').replaceAll(RegExp(r'[\s\u200b]'), '').isEmpty &&
        content.querySelector('img,video,iframe,table,hr') == null;
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: !preview && _subscriptionOnly
          ? (MediaQuery.sizeOf(context).height - 80)
                .clamp(0.0, double.infinity)
                .toDouble()
          : 0,
    ),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (effectiveHeader == 'event_and_date' &&
              (eventTitle?.trim().isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                eventTitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (!_hasVisibleContent && effectiveHeader == 'none')
            Text(
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
              SaleOpeningStrings.scheduledStart(
                LocaleDateTime.dateTimeCell(
                  targetTime,
                  Localizations.localeOf(context).toString(),
                ),
              ),
            ),
          if (effectiveHeader != 'none')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                LocaleDateTime.dateTimeCell(
                  targetTime,
                  Localizations.localeOf(context).toString(),
                ),
              ),
            ),
          HtmlView(
            key: ValueKey((
              showTimer,
              canSubscribe,
              targetTime,
              formLink,
              hasTickets,
              informal,
              preview,
            )),
            html:
                '<div style="text-align: center;">${_singletonContent(showTimer ? countdownContent(html) : html ?? '')}</div>',
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
                        preview: preview,
                        hasTickets: hasTickets,
                        informal: informal,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
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

HtmlEmbeddedBlock saleOpeningPreviewBlock({
  bool enabled = true,
  bool paused = false,
}) => HtmlEmbeddedBlock(
  cssClass: 'form-sale-opening-notification',
  label: SaleOpeningStrings.title,
  builder: (_) => enabled && !paused
      ? const SaleOpeningNotification(formLink: '', preview: true)
      : Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            SaleOpeningStrings.text(
              paused ? 'previewPaused' : 'previewDisabled',
            ),
          ),
        ),
);

String _singletonContent(String html) {
  final root = parser.parseFragment(html);
  for (final title in root.querySelectorAll('.form-presale-system-title')) {
    title.text = FormStrings.registrationStart;
  }
  for (final type in ['form-countdown', 'form-sale-opening-notification']) {
    for (final duplicate
        in root.querySelectorAll('div.html-editor-block.$type').skip(1)) {
      duplicate.remove();
    }
  }
  return root.outerHtml;
}
