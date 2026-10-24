import 'dart:convert';

/// Only call with the independently saved slug, never an editor draft.
String formEmbedCode(
    {required String tenantUrl,
    required String savedLink,
    required String title,
    required String fallbackLabel,
    bool automatic = true,
    bool inheritStyle = true}) {
  if (savedLink.isEmpty) throw ArgumentError.value(savedLink, 'savedLink');
  final base = tenantUrl.replaceFirst(RegExp(r'/+$'), '');
  final publicUrl = '$base/form/${Uri.encodeComponent(savedLink)}';
  const escape = HtmlEscape(HtmlEscapeMode.attribute);
  final src = escape.convert('$publicUrl?embed=1');
  final marker = (automatic || inheritStyle ? ' data-festapp-embed' : '') +
      (!automatic && inheritStyle ? ' data-festapp-height="fixed"' : '') +
      (inheritStyle ? ' data-festapp-style="inherit"' : '');
  final frame =
      '<div data-festapp-embed-host><iframe$marker src="$src" title="${escape.convert(title)}" '
      'width="100%" height="800" style="border:0" loading="lazy"></iframe></div>';
  final fallback = '<a href="${escape.convert(publicUrl)}" target="_blank" '
      'rel="noopener noreferrer">${const HtmlEscape().convert(fallbackLabel)}</a>';
  final script = automatic || inheritStyle
      ? '\n<script src="${escape.convert('$base/embed.js')}" defer></script>'
      : '';
  return '$frame\n$fallback$script';
}
