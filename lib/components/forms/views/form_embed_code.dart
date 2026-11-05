import 'dart:convert';

/// Only call with the independently saved slug, never an editor draft.
String formEmbedCode({
  required String tenantUrl,
  required String savedLink,
  required String title,
  required String fallbackLabel,
  bool automatic = true,
  bool inheritStyle = true,
}) {
  if (savedLink.isEmpty) throw ArgumentError.value(savedLink, 'savedLink');
  final base = tenantUrl.replaceFirst(RegExp(r'/+$'), '');
  final publicUrl = '$base/form/${Uri.encodeComponent(savedLink)}';
  const escape = HtmlEscape(HtmlEscapeMode.attribute);
  final src = escape.convert('$publicUrl?embed=1');
  final marker =
      ' data-festapp-embed data-festapp-style="${inheritStyle ? 'inherit' : 'default'}"${automatic ? '' : ' data-festapp-height="fixed"'}';
  final frame =
      '<iframe$marker src="$src" title="${escape.convert(title)}" '
      'allow="clipboard-write" width="100%" height="800" style="border:0" loading="lazy"></iframe>';
  final fallback =
      '<a href="${escape.convert(publicUrl)}" target="_blank" '
      'rel="noopener noreferrer">${const HtmlEscape().convert(fallbackLabel)}</a>';
  // Pin the helper feature so an old four-hour browser cache cannot ignore
  // the explicit per-iframe appearance choice.
  final script =
      '\n<script src="${escape.convert('$base/embed.js?v=appearance-1')}" defer></script>';
  return '<div data-festapp-embed-host>\n$frame\n$fallback\n</div>$script';
}
