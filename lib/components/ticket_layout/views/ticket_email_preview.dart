import 'dart:convert';
import 'package:flutter/material.dart';
import '../../email_templates/email_preview_html.dart';
import '../../email_templates/db_email_templates.dart';
import 'package:festapp_core/email_templates.dart';
import '../../html/html_embedded_block.dart';
import '../../features/ticket_feature.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:html/parser.dart' as html;
import '../ticket_delivery_strings.dart';

/// Uses the template editor's inert received-message renderer and local QR samples.
class TicketEmailPreview extends StatelessWidget {
  const TicketEmailPreview(
      {super.key, required this.preview, this.sampleCount = 0});
  final Map<String, dynamic> preview;
  final int sampleCount;

  static const _ticketMarker = 'FESTAPP_TICKET_PREVIEW_BLOCK';

  /// Read-only examples from the inherited template, without preparing real
  /// tickets, PDF bytes, capability links or outgoing messages.
  static Map<String, dynamic> sample(
      Map<String, dynamic> context, TicketDeliveryMode mode, int count) {
    final resolved = context['resolved'] as Map? ?? {};
    final template = resolved['template'] as Map? ?? {};
    final scenario = (context['scenario'] as EmailPreviewScenario).withContext(
        EmailPreviewContext(
            occasionTitle: context['title'] as String?, ticketsEnabled: true));
    var body = '${template['html'] ?? ''}';
    final tickets = RegExp(r'\{\{\s*tickets\s*\}\}');
    if (!tickets.hasMatch(body)) body += '{{tickets}}';
    var seen = false;
    body = body.replaceAllMapped(tickets, (_) {
      if (seen) return '';
      seen = true;
      return mode == TicketDeliveryMode.pdfAttachment ? '' : _ticketMarker;
    });
    final wrapper = (resolved['wrapper'] as Map?)?['html'] as String?;
    return {
      'subject': scenario.composeSubject('${template['subject'] ?? ''}'),
      'html': scenario.composeHtml(body, wrapperHtml: wrapper),
      'wrapper': wrapper,
      'attachments': [
        if (mode.includesPdf)
          for (var i = 1; i <= count; i++)
            {
              'filename': 'ticket_UKAZKA-$i.pdf',
              'contentType': 'application/pdf'
            },
      ],
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
        'script,style,iframe,object,embed,form,input,button,video,audio,source,svg,link,meta,base')) {
      node.remove();
    }
    for (final node in document.querySelectorAll('*')) {
      final image =
          node.localName == 'img' ? allowed[node.attributes['src']] : null;
      if (node.localName == 'img' && image == null) {
        node.remove();
        continue;
      }
      final alt = node.attributes['alt'];
      node.attributes.clear();
      if (image != null) {
        node.attributes
            .addAll({'src': image, 'width': '240', 'alt': alt ?? 'QR'});
      }
    }
    return document.body?.innerHtml ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final tickets = HtmlEmbeddedBlock(
        cssClass: 'ticket-email-preview',
        builder: (_) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 1; i <= sampleCount; i++)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: QrImageView(
                        data: 'festapp-preview:INVALID-$i',
                        size: 240,
                        backgroundColor: Colors.white)),
            ]));
    final body =
        '${preview['html'] ?? ''}'.replaceAll(_ticketMarker, tickets.html);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      EmailReceivedMessage(
          key: ValueKey(sampleCount),
          subject: '${preview['subject'] ?? ''}',
          html: body,
          embeddedBlock: tickets,
          allowedRemoteImageSources: EmailAuthoringContext(
                  senderAddress: '', wrapperHtml: preview['wrapper'] as String?)
              .bannerImageSources),
      if ((preview['attachments'] as List? ?? []).isNotEmpty) ...[
        const Divider(height: 24),
        for (final attachment
            in (preview['attachments'] as List? ?? []).whereType<Map>())
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text('${attachment['filename']}')),
      ],
      const SizedBox(height: 8),
      Text(TicketDeliveryStrings.text('sampleHelp')),
    ]);
  }
}
