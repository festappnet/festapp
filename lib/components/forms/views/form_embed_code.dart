import 'dart:convert';

/// Envelope validation only. Provider and current approval stay with SQL/runtime.
Map<String, dynamic>? parseFormConsentExport(String raw, String serviceOrigin) {
  if (raw.isEmpty || raw.length > 16384) return null;
  try {
    final v = jsonDecode(raw);
    if (v is! Map<String, dynamic> ||
        v['schemaVersion'] != 1 ||
        v['serviceOrigin'] != serviceOrigin) {
      return null;
    }
    final b = v['binding'];
    final c = v['providerConfig'];
    final site = v['websiteOrigin'];
    if (site is! String ||
        Uri.parse(site).scheme != 'https' ||
        Uri.parse(site).origin != site ||
        b is! Map ||
        b['id'] is! String ||
        !RegExp(r'^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$')
            .hasMatch(b['id']) ||
        b['version'] is! int ||
        b['version'] <= 0 ||
        b['version'] > 9007199254740991 ||
        c is! Map ||
        ![
          'complianz',
          'cookiebot',
          'cookieconsent',
          'wix',
        ].contains(c['provider']) ||
        c['origin'] != site ||
        c['organization'] is! int ||
        c['organization'] <= 0 ||
        c['organization'] > 9007199254740991 ||
        c['unit'] is! int ||
        c['unit'] <= 0 ||
        c['unit'] > 9007199254740991 ||
        c['consentRevision'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(c['consentRevision'])) {
      return null;
    }
    return v;
  } catch (_) {
    return null;
  }
}

/// Only call with the independently saved slug, never an editor draft.
String formEmbedCode({
  required String tenantUrl,
  required String savedLink,
  required String title,
  required String fallbackLabel,
  bool automatic = true,
  bool hostDataLayer = true,
  String? consentExport,
}) {
  if (savedLink.isEmpty) throw ArgumentError.value(savedLink, 'savedLink');
  final base = tenantUrl.replaceFirst(RegExp(r'/+$'), '');
  final imported = consentExport == null
      ? null
      : parseFormConsentExport(consentExport, base);
  if (consentExport != null && imported == null) {
    throw ArgumentError.value('invalid export', 'consentExport');
  }
  final publicUrl = '$base/form/${Uri.encodeComponent(savedLink)}';
  const escape = HtmlEscape(HtmlEscapeMode.attribute);
  final src = escape.convert('$publicUrl?embed=1');
  final marker =
      ' data-festapp-embed${automatic ? '' : ' data-festapp-height="fixed"'}'
      '${hostDataLayer ? ' data-festapp-datalayer' : ''}';
  final frame =
      '<iframe$marker src="$src" title="${escape.convert(title)}" '
      'allow="clipboard-write" height="800" '
      'style="display:block;width:100%;max-width:100%;border:0;color-scheme:light dark" loading="lazy"></iframe>';
  final fallback =
      '<a href="${escape.convert(publicUrl)}" target="_blank" '
      '${imported == null ? 'rel="noopener noreferrer"' : 'data-festapp-consent-link'}>${const HtmlEscape().convert(fallbackLabel)}</a>';
  final importAttribute = imported == null
      ? ''
      : ' data-festapp-consent="${escape.convert(jsonEncode(imported))}"'
            '${imported['providerConfig']['provider'] == 'cookiebot' ? ' data-cookieconsent="ignore"' : ''}'
            '${imported['providerConfig']['provider'] == 'complianz' ? ' data-category="functional"' : ''}';
  final script =
      '\n<script src="${escape.convert('$base/embed.js')}"$importAttribute defer></script>';
  return '<div data-festapp-embed-host>\n$frame\n$fallback\n</div>$script';
}
