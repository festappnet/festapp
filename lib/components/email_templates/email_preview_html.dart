import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/parser.dart' as parser;

/// Email source styles on a neutral canvas, with no navigation or remote fetch.
/// Removing action attributes also removes tap semantics and keyboard targets.
class EmailPreviewHtml extends StatelessWidget {
  const EmailPreviewHtml(
      {required this.html, this.imageBytesResolver, super.key});
  final String html;
  final Uint8List? Function(String)? imageBytesResolver;
  @override
  Widget build(BuildContext context) {
    final document = parser.parse(html);
    for (final element in document.querySelectorAll('*')) {
      for (final attribute in element.attributes.keys.toList()) {
        if (attribute.toString().startsWith('on') ||
            const {'href', 'action', 'formaction', 'tabindex', 'srcset'}
                .contains(attribute)) {
          element.attributes.remove(attribute);
        }
      }
    }
    for (final element in document
        .querySelectorAll('script,iframe,video,audio,form,object,embed,link')) {
      element.remove();
    }
    return ColoredBox(
        color: Colors.white,
        child: DefaultTextStyle(
          style: const TextStyle(
              color: Color(0xff202020), fontSize: 16, height: 1.5),
          child: ExcludeFocus(
              child: HtmlWidget(
            document.outerHtml,
            textStyle: const TextStyle(
                color: Color(0xff202020), fontSize: 16, height: 1.5),
            onTapUrl: (_) async => true,
            customStylesBuilder: (element) => element.localName == 'a' &&
                    !element.attributes.containsKey('style')
                ? {'color': '#1565c0', 'text-decoration': 'underline'}
                : null,
            customWidgetBuilder: (element) {
              if (element.localName != 'img') return null;
              final source = element.attributes['src'] ?? '';
              final fallback = Semantics(
                  label: element.attributes['alt'] ?? '',
                  child: const SizedBox(
                      height: 48,
                      child: Center(
                          child:
                              Icon(Icons.image_outlined, color: Colors.grey))));
              if (imageBytesResolver == null || source.isEmpty) return fallback;
              final bytes = imageBytesResolver!(source);
              return bytes == null
                  ? fallback
                  : Image.memory(bytes,
                      fit: BoxFit.contain,
                      semanticLabel: element.attributes['alt']);
            },
          )),
        ));
  }
}
