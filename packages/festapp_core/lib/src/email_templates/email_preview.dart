import 'email_template_rules.dart';

class EmailRequiredLink {
  final String url, html;
  const EmailRequiredLink({required this.url, required this.html});
  factory EmailRequiredLink.fromJson(Map<String, dynamic> json) =>
      EmailRequiredLink(
        url: json['url'] as String,
        html: json['html'] as String,
      );
}

const emailOverviewSlot = '<!-- customer-order-overview-link -->';
String escapeEmailHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Mirrors the production pure finalizer; shared fixtures assert parity.
String completeEmailContent(String html, List<EmailRequiredLink> links) {
  for (final link in links) {
    if (link.url.isEmpty ||
        html.contains('href="${escapeEmailHtml(link.url)}"'))
      continue;
    if (html.contains(emailOverviewSlot)) {
      html = html.replaceFirst(emailOverviewSlot, link.html);
    } else if (RegExp(r'</body>', caseSensitive: false).hasMatch(html)) {
      html = html.replaceFirst(
        RegExp(r'</body>', caseSensitive: false),
        '${link.html}</body>',
      );
    } else {
      html += link.html;
    }
  }
  return html.replaceAll(emailOverviewSlot, '');
}

class EmailPreviewScenario {
  final String templateCode, scenario, locale, tone;
  final Map<String, String> values;
  final Set<String> richCodes;
  final List<EmailRequiredLink> requiredLinks;
  const EmailPreviewScenario({
    required this.templateCode,
    required this.scenario,
    required this.locale,
    required this.tone,
    required this.values,
    required this.richCodes,
    required this.requiredLinks,
  });
  factory EmailPreviewScenario.fromJson(Map<String, dynamic> json) =>
      EmailPreviewScenario(
        templateCode: json['templateCode'] as String,
        scenario: json['scenario'] as String,
        locale: json['locale'] as String,
        tone: json['tone'] as String,
        values: Map<String, String>.from(json['values'] as Map),
        richCodes: Set<String>.from(json['richCodes'] as List),
        requiredLinks: (json['requiredLinks'] as List)
            .map(
              (v) => EmailRequiredLink.fromJson(
                Map<String, dynamic>.from(v as Map),
              ),
            )
            .toList(),
      );

  /// The domain catalog owns availability, including legacy unknown tokens.
  EmailPreviewScenario restrictTo(Set<String> codes) => EmailPreviewScenario(
    templateCode: templateCode,
    scenario: scenario,
    locale: locale,
    tone: tone,
    values: {
      for (final entry in values.entries)
        if (codes.contains(entry.key)) entry.key: entry.value,
    },
    richCodes: richCodes.intersection(codes),
    requiredLinks: requiredLinks,
  );

  String composeSubject(String subject) => subject.replaceAllMapped(
    EmailTemplateRules.tokenPattern,
    (m) => richCodes.contains(m[1]) ? m[0]! : values[m[1]] ?? m[0]!,
  );

  /// One scan over authored HTML. Substituted fragments are never reprocessed.
  /// Rich content is admitted only in text context, never HTML attributes.
  String composeHtml(String html) {
    final out = StringBuffer();
    var offset = 0;
    var inTag = false;
    var quote = '';
    var rawElement = '';
    while (offset < html.length) {
      if (!inTag && html.startsWith('<!--', offset)) {
        final end = html.indexOf('-->', offset + 4);
        final until = end < 0 ? html.length : end + 3;
        out.write(html.substring(offset, until));
        offset = until;
        continue;
      }
      if (html[offset] == '<' && !inTag) {
        final tail = html.substring(offset);
        final open = RegExp(
          r'^<(script|style)\b',
          caseSensitive: false,
        ).firstMatch(tail);
        final close = RegExp(
          r'^</(script|style)\b',
          caseSensitive: false,
        ).firstMatch(tail);
        if (open != null) rawElement = open[1]!.toLowerCase();
        if (close != null && close[1]!.toLowerCase() == rawElement)
          rawElement = '';
        inTag = true;
      }
      if (html.startsWith('{{', offset) && rawElement.isEmpty) {
        final match = EmailTemplateRules.tokenPattern.matchAsPrefix(
          html,
          offset,
        );
        if (match != null) {
          final code = match[1]!;
          final value = values[code];
          if (value != null &&
              (!inTag || (quote.isNotEmpty && !richCodes.contains(code)))) {
            final escaped = escapeEmailHtml(value);
            out.write(
              richCodes.contains(code)
                  ? value
                  : quote == "'"
                  ? escaped.replaceAll("'", '&#39;')
                  : escaped,
            );
          } else {
            out.write(match[0]);
          }
          offset = match.end;
          continue;
        }
      }
      final char = html[offset++];
      out.write(char);
      if (inTag) {
        if (quote.isNotEmpty) {
          if (char == quote) quote = '';
        } else if (char == '"' || char == "'") {
          quote = char;
        } else if (char == '>') {
          inTag = false;
        }
      }
    }
    return completeEmailContent(out.toString(), requiredLinks);
  }
}
