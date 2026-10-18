import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/parser.dart' as parser;

/// Inert email content adapted to the current app theme, without remote fetch.
/// Removing action attributes also removes tap semantics and keyboard targets.
class EmailPreviewHtml extends StatelessWidget {
  const EmailPreviewHtml(
      {required this.html, this.imageBytesResolver, super.key});
  final String html;
  final Uint8List? Function(String)? imageBytesResolver;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String css(Color color) =>
        '#${color.toARGB32().toRadixString(16).substring(2)}';
    final document = parser.parse(html);
    for (final element in document.querySelectorAll('*')) {
      final styles = (element.attributes['style'] ?? '').split(';');
      final isButton = element.localName == 'a' &&
          styles.any((s) => s.trimLeft().startsWith('background'));
      final themed = <String>[];
      for (final declaration in styles) {
        final colon = declaration.indexOf(':');
        if (colon < 0) continue;
        final property = declaration.substring(0, colon).trim().toLowerCase();
        final value = declaration.substring(colon + 1).trim();
        if (property == 'color') {
          themed.add(
              'color: ${css(isButton ? colors.onPrimary : colors.onSurface)}');
        } else if (property == 'background' || property == 'background-color') {
          themed.add(
              'background-color: ${css(isButton ? colors.primary : colors.surfaceContainerLow)}');
        } else if (property == 'border-color') {
          themed.add('border-color: ${css(colors.outlineVariant)}');
        } else if (property.startsWith('border') && value.contains('solid')) {
          themed.add(
              '$property: ${value.replaceAll(RegExp(r'#[0-9a-fA-F]{3,8}|rgb[a]?\([^)]*\)'), css(colors.outlineVariant))}');
        } else {
          themed.add(declaration);
        }
      }
      if (isButton) {
        themed.add('color: ${css(colors.onPrimary)}');
      }
      element.attributes['style'] = themed.join(';');
      element.attributes.remove('bgcolor');
      element.attributes.remove('color');
      for (final attribute in element.attributes.keys.toList()) {
        if (attribute.toString().startsWith('on') ||
            const {'href', 'action', 'formaction', 'tabindex', 'srcset'}
                .contains(attribute)) {
          element.attributes.remove(attribute);
        }
      }
    }
    for (final element in document.querySelectorAll(
        'script,style,iframe,video,audio,form,object,embed,link')) {
      element.remove();
    }
    return ColoredBox(
        color: colors.surface,
        child: DefaultTextStyle(
          style: TextStyle(color: colors.onSurface, fontSize: 16, height: 1.5),
          child: ExcludeFocus(
              child: HtmlWidget(
            document.outerHtml,
            textStyle:
                TextStyle(color: colors.onSurface, fontSize: 16, height: 1.5),
            onTapUrl: (_) async => true,
            customStylesBuilder: (element) => element.localName == 'a' &&
                    (element.attributes['style'] ?? '').isEmpty
                ? {'color': css(colors.primary), 'text-decoration': 'underline'}
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
