import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/parser.dart' as html;
import '../ticket_delivery_strings.dart';

/// Only server-provided sample PNGs may cross the preview's resource boundary.
/// Template images, CSS and links remain inert, including template data URLs.
class TicketEmailPreview extends StatelessWidget {
  const TicketEmailPreview({super.key, required this.preview});
  final Map<String, dynamic> preview;

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
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${preview['subject'] ?? ''}',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8)),
            child: HtmlWidget(
                safeHtml('${preview['html'] ?? ''}',
                    preview['inlineImages'] as List? ?? []),
                onTapUrl: (_) => true)),
        for (final attachment
            in (preview['attachments'] as List? ?? []).whereType<Map>())
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file),
              title: Text('${attachment['filename']}')),
        if ((preview['inlineImages'] as List? ?? []).isNotEmpty)
          Text(TicketDeliveryStrings.text('sampleHelp')),
      ]);
}
