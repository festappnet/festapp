import 'dart:typed_data';
import '../html/html_embedded_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/parser.dart' as parser;
import 'email_templates_strings.dart';
import '../images/image_url_helper.dart';
import '../images/recovering_image.dart';

/// Typography of the canonical email wrapper, independent of the app font.
const emailContentTextStyle =
    TextStyle(inherit: false, fontFamily: 'sans-serif', fontSize: 16);

/// Email fragments own their edge margins. The default factory trims these for
/// app text; doing so joins independently rendered email components together.
class _EmailWidgetFactory extends WidgetFactory {
  @override
  Widget buildBodyWidget(BuildContext context, Widget child) => child;
}

/// Inert email content adapted to the current app theme, with only explicitly approved wrapper images.
/// Removing action attributes also removes tap semantics and keyboard targets.
class EmailPreviewHtml extends StatelessWidget {
  const EmailPreviewHtml(
      {required this.html,
      this.imageBytesResolver,
      this.embeddedBlock,
      this.allowedRemoteImageSources = const {},
      super.key});
  final String html;
  final HtmlEmbeddedBlock? embeddedBlock;
  final Set<String> allowedRemoteImageSources;
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
          style: emailContentTextStyle.copyWith(color: colors.onSurface),
          child: ExcludeFocus(
              child: HtmlWidget(
            document.outerHtml,
            factoryBuilder: _EmailWidgetFactory.new,
            textStyle: emailContentTextStyle.copyWith(color: colors.onSurface),
            onTapUrl: (_) async => true,
            customStylesBuilder: (element) => element.localName == 'a' &&
                    (element.attributes['style'] ?? '').isEmpty
                ? {'color': css(colors.primary), 'text-decoration': 'underline'}
                : null,
            customWidgetBuilder: (element) {
              final block = embeddedBlock;
              if (block != null &&
                  element.classes.contains('html-editor-block') &&
                  element.classes.contains(block.cssClass))
                return block.builder(context);
              // The HTML renderer drops empty blocks before its sizing pass.
              // Production email renderers deliberately use these as spacers.
              if (element.localName == 'div' &&
                  element.children.isEmpty &&
                  element.text.trim().isEmpty) {
                final match = RegExp(
                        r'(?:^|;)\s*height\s*:\s*([0-9]+(?:\.[0-9]+)?)px(?:\s*;|\s*$)')
                    .firstMatch(element.attributes['style'] ?? '');
                if (match != null)
                  return SizedBox(height: double.parse(match.group(1)!));
              }
              if (element.localName != 'img') return null;
              final source = element.attributes['src'] ?? '';
              final fallback = Semantics(
                  label: element.attributes['alt'] ?? '',
                  child: const SizedBox(
                      height: 48,
                      child: Center(
                          child:
                              Icon(Icons.image_outlined, color: Colors.grey))));
              final bytes = imageBytesResolver?.call(source);
              if (bytes != null) {
                return Image.memory(bytes,
                    fit: BoxFit.contain,
                    semanticLabel: element.attributes['alt']);
              }
              if (source.isNotEmpty &&
                  allowedRemoteImageSources.contains(source)) {
                return Semantics(
                  label: element.attributes['alt'] ?? '',
                  image: true,
                  child: RecoveringImage(
                    image: NetworkImage(ImageUrlHelper.transformImageUrl(source,
                        width: ImageUrlHelper.mediumWidth)),
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                );
              }
              return fallback;
            },
          )),
        ));
  }
}

/// A received-message surface with phone-width content, shared with the editor's
/// inert HTML renderer. The sender comes from authoritative delivery metadata;
/// the recipient is a synthetic preview identity.
class EmailReceivedMessage extends StatelessWidget {
  const EmailReceivedMessage({
    required this.subject,
    required this.html,
    this.imageBytesResolver,
    this.embeddedBlock,
    this.senderAddress,
    this.recipientLabel,
    this.allowedRemoteImageSources = const {},
    super.key,
  });
  final String subject;
  final String? senderAddress;
  final String? recipientLabel;
  final String html;
  final HtmlEmbeddedBlock? embeddedBlock;
  final Set<String> allowedRemoteImageSources;
  final Uint8List? Function(String)? imageBytesResolver;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          EmailTemplatesStrings.previewReceivedMessage,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(subject, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text(
                    '${EmailTemplatesStrings.previewFrom}: ${senderAddress ?? EmailTemplatesStrings.previewSenderUnavailable}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${EmailTemplatesStrings.previewTo}: ${recipientLabel ?? 'Jana Nováková <jana.novakova@example.com>'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            EmailPreviewHtml(
              html: html,
              embeddedBlock: embeddedBlock,
              imageBytesResolver: imageBytesResolver,
              allowedRemoteImageSources: allowedRemoteImageSources,
            ),
          ],
        ),
      ),
    );
  }
}
