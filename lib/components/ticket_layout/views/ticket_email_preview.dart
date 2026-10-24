import 'dart:convert';
import 'package:flutter/material.dart';
import '../../html/html_view.dart';
import '../../html/html_embedded_block.dart';
import '../../features/ticket_feature.dart';
import '../../email_templates/email_template_model.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:html/parser.dart' as html;
import '../ticket_delivery_strings.dart';

/// Only validated sample PNGs may cross the preview's resource boundary.
/// Template images, CSS and links remain inert, including template data URLs.
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
    final values = {
      for (final sub in EmailTemplateModel
          .substitutionDefinitions['TICKET_ORDER_PAYMENT_DONE']!)
        sub.code: sub.defaultValue,
      'occasionTitle': const HtmlEscape().convert('${context['title'] ?? ''}'),
      'orderSymbol': 'UKAZKA-001',
      'tickets': mode == TicketDeliveryMode.pdfAttachment ? '' : _ticketMarker,
    };
    String substitute(String source, {bool subject = false}) =>
        source.replaceAllMapped(
            RegExp(r'\{\{\s*(\w+)\s*\}\}'),
            (match) => subject && match[1] == 'occasionTitle'
                ? '${context['title'] ?? ''}'
                : values[match[1]] ?? match[0]!);
    var body = '${template['html'] ?? ''}';
    final tickets = RegExp(r'\{\{\s*tickets\s*\}\}');
    if (!tickets.hasMatch(body)) body += '{{tickets}}';
    var seen = false;
    body = body.replaceAllMapped(tickets, (_) {
      if (seen) return '';
      seen = true;
      return values['tickets']!;
    });
    body = substitute(body);
    final wrapper = (resolved['wrapper'] as Map?)?['html'] as String?;
    return {
      'subject': substitute('${template['subject'] ?? ''}', subject: true),
      'html': wrapper == null ? body : wrapper.replaceAll('{{content}}', body),
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
      // Retain typography and layout, while keeping CSS resource loads inert.
      final style = node.attributes['style']
          ?.split(';')
          .where((entry) => RegExp(
                  r'^(?:color|background-color|font-size|font-weight|font-style|font-family|text-align|text-decoration|line-height|padding(?:-(?:top|right|bottom|left))?|margin(?:-(?:top|right|bottom|left))?|width|max-width|height|border(?:-radius|-color|-width|-style)?)\s*:\s*[#(),.%\w\s-]+$',
                  caseSensitive: false)
              .hasMatch(entry.trim()))
          .join(';');
      node.attributes.clear();
      if (style != null && style.isNotEmpty) node.attributes['style'] = style;
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
    final body = safeHtml(
            '${preview['html'] ?? ''}', preview['inlineImages'] as List? ?? [])
        .replaceAll(_ticketMarker, tickets.html);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${preview['subject'] ?? ''}',
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      IgnorePointer(
          child: HtmlView(
              key: ValueKey(sampleCount), html: body, embeddedBlock: tickets)),
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
