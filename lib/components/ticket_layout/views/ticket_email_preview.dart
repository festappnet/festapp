import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../email_templates/email_preview_html.dart';
import '../../email_templates/db_email_templates.dart';

import 'package:festapp_core/email_templates.dart';

import '../../html/html_embedded_block.dart';
import '../../features/ticket_feature.dart';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:html/parser.dart' as html;
import 'package:easy_localization/easy_localization.dart';

import '../ticket_delivery_strings.dart';

/// Uses the template editor's inert received-message renderer and local QR samples.
class TicketEmailPreview extends StatelessWidget {
  const TicketEmailPreview({
    super.key,
    required this.preview,
    this.sampleCount = 0,
    this.senderAddress,
    this.imageBytesResolver,
    this.includesPdf = false,
  });
  final Map<String, dynamic> preview;
  final int sampleCount;
  final bool includesPdf;
  final String? senderAddress;
  final Uint8List? Function(String)? imageBytesResolver;

  static Widget inlineSample({required int count, bool includesPdf = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (includesPdf)
            const Text('Stejné vstupenky najdete také v PDF příloze.'),
          for (var i = 1; i <= count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count > 1 ? 'Vstupenka $i z $count' : 'Vaše vstupenka',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Toto je vaše vstupenka. U vstupu ukažte tento QR kód.',
                  ),
                  const SizedBox(height: 16),
                  QrImageView(
                    data: 'festapp-preview:INVALID-$i',
                    size: 256,
                    padding: const EdgeInsets.all(32),
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text('Kód vstupenky: festapp-preview:INVALID-$i'),
                ],
              ),
            ),
        ],
      );

  static Widget walletSample({required int count, String? language}) => Builder(
    builder: (context) {
      final requested = language ?? context.locale.languageCode;
      final lang =
          const {'cs', 'sk', 'en', 'de', 'pl', 'uk'}.contains(requested)
          ? requested
          : 'en';
      return FutureBuilder<Map<String, String>>(
        future: TicketDeliveryStrings.walletCopy(lang),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          String text(String key) => snapshot.data![key]!;
          return Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.only(top: 24),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xffe2e8f0))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text('Title'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  text('Help'),
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 20),
                for (var i = 1; i <= count; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text('Ticket')
                              .replaceAll('{n}', '$i')
                              .replaceAll('{count}', '$count'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: Image.asset(
                              'assets/brand/google-wallet/$lang.png',
                              height: 48,
                              fit: BoxFit.contain,
                              semanticLabel: text('Button'),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Center(
                            child: Text(
                              text('Fallback'),
                              style: const TextStyle(
                                fontSize: 12,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );

  static String ticketBody(
    String body,
    TicketDeliveryMode? mode, {
    bool walletEnabled = false,
  }) {
    final tokens = RegExp(r'\{\{\s*tickets\s*\}\}');
    if (!tokens.hasMatch(body) &&
        mode != null &&
        (mode != TicketDeliveryMode.pdfAttachment || walletEnabled)) {
      body += '{{tickets}}';
    }
    var seen = false;
    return body.replaceAllMapped(tokens, (_) {
      if (seen) return '';
      seen = true;
      return mode == null ||
              (mode == TicketDeliveryMode.pdfAttachment && !walletEnabled)
          ? ''
          : _ticketMarker;
    });
  }

  static List<Map<String, String>> sampleAttachments(
    TicketDeliveryMode? mode,
    int count,
  ) => [
    if (mode?.includesPdf == true)
      for (var i = 1; i <= count; i++)
        {'filename': 'ticket_UKAZKA-$i.pdf', 'contentType': 'application/pdf'},
  ];

  static const _ticketMarker = 'FESTAPP_TICKET_PREVIEW_BLOCK';

  /// Read-only examples from the inherited template, without preparing real
  /// tickets, PDF bytes, capability links or outgoing messages.
  static Map<String, dynamic> sample(
    Map<String, dynamic> context,
    TicketDeliveryMode mode,
    int count,
  ) {
    final resolved = context['resolved'] as Map? ?? {};
    final template = resolved['template'] as Map? ?? {};
    final scenario = (context['scenario'] as EmailPreviewScenario).withContext(
      EmailPreviewContext(
        occasionTitle: context['title'] as String?,
        ticketsEnabled: true,
      ),
    );
    final walletEnabled =
        context['walletEnabled'] != false && context['walletReady'] == true;
    final body = ticketBody(
      '${template['html'] ?? ''}',
      mode,
      walletEnabled: walletEnabled,
    );
    final wrapper = (resolved['wrapper'] as Map?)?['html'] as String?;
    return {
      'subject': scenario.composeSubject('${template['subject'] ?? ''}'),
      'html': scenario.composeHtml(body, wrapperHtml: wrapper),
      'wrapper': wrapper,
      'walletEnabled': walletEnabled,
      'walletTicketCount': count,
      'walletLanguage': context['lang'] ?? scenario.locale,
      'includesPdf': mode.includesPdf,
      'attachments': sampleAttachments(mode, count),
    };
  }

  static String safeHtml(String source, List<dynamic> images) {
    final allowed = <String, String>{};
    for (final image in images.whereType<Map>()) {
      final cid = image['contentId'];
      final content = image['content'];
      if (cid is! String || content is! String || content.length > 1000000)
        continue;
      try {
        final bytes = base64Decode(content);
        if (bytes.length >= 8 &&
            bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') {
          allowed['cid:$cid'] = 'data:image/png;base64,$content';
        }
      } on FormatException {
        continue;
      }
    }
    final document = html.parse(source);
    for (final node in document.querySelectorAll(
      'script,style,iframe,object,embed,form,input,button,video,audio,source,svg,link,meta,base',
    )) {
      node.remove();
    }
    for (final node in document.querySelectorAll('*')) {
      final image = node.localName == 'img'
          ? allowed[node.attributes['src']]
          : null;
      if (node.localName == 'img' && image == null) {
        node.remove();
        continue;
      }
      final alt = node.attributes['alt'];
      node.attributes.clear();
      if (image != null) {
        node.attributes.addAll({
          'src': image,
          'width': '240',
          'alt': alt ?? 'QR',
        });
      }
    }
    return document.body?.innerHtml ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final tickets = HtmlEmbeddedBlock(
      cssClass: 'ticket-email-preview',
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sampleCount > 0)
            inlineSample(
              count: sampleCount,
              includesPdf: includesPdf || preview['includesPdf'] == true,
            ),
          if (preview['walletEnabled'] == true)
            walletSample(
              count: preview['walletTicketCount'] as int? ?? 1,
              language: preview['walletLanguage'] as String?,
            ),
        ],
      ),
    );
    final body = '${preview['html'] ?? ''}'.replaceAll(
      _ticketMarker,
      tickets.html,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmailReceivedMessage(
          key: ValueKey(sampleCount),
          subject: '${preview['subject'] ?? ''}',
          senderAddress: senderAddress,
          imageBytesResolver: imageBytesResolver,
          html: body,
          embeddedBlock: tickets,
          allowedRemoteImageSources: EmailAuthoringContext(
            senderAddress: '',
            wrapperHtml: preview['wrapper'] as String?,
          ).bannerImageSources,
        ),
        if ((preview['attachments'] as List? ?? []).isNotEmpty) ...[
          const Divider(height: 24),
          for (final attachment
              in (preview['attachments'] as List? ?? []).whereType<Map>())
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text('${attachment['filename']}'),
            ),
        ],
        const SizedBox(height: 8),
        Text(TicketDeliveryStrings.text('sampleHelp')),
      ],
    );
  }
}
