import 'email_template_rules.dart';
import 'email_preview_context.dart';

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
  final Map<String, String> contextTemplates;
  final Map<String, String> contextDefaults;
  final List<EmailRequiredLink> requiredLinks;
  const EmailPreviewScenario({
    required this.templateCode,
    required this.scenario,
    required this.locale,
    required this.tone,
    required this.values,
    required this.richCodes,
    this.contextTemplates = const {},
    this.contextDefaults = const {},
    required this.requiredLinks,
  });
  factory EmailPreviewScenario.fromJson(Map<String, dynamic> json) =>
      EmailPreviewScenario(
        contextDefaults: Map<String, String>.from(
          json['contextDefaults'] as Map? ?? const {},
        ),
        contextTemplates: Map<String, String>.from(
          json['contextTemplates'] as Map? ?? const {},
        ),
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
    contextDefaults: contextDefaults,
    contextTemplates: {
      for (final entry in contextTemplates.entries)
        if (codes.contains(entry.key)) entry.key: entry.value,
    },
    requiredLinks: requiredLinks,
  );

  EmailPreviewScenario withContext(EmailPreviewContext context) {
    final bindings = {
      ...contextDefaults,
      ...context.bindings(zero: scenario == 'zero'),
    };
    final result = Map<String, String>.from(values);
    for (final code in ['occasionTitle', 'occasion_title']) {
      if (result.containsKey(code) && context.occasionTitle?.isNotEmpty == true)
        result[code] = context.occasionTitle!;
    }
    if (context.deadline != null && result.containsKey('deadline'))
      result['deadline'] = context.deadline!;
    if (context.deadline != null && result.containsKey('offer_expires_at'))
      result['offer_expires_at'] = '${context.deadline} 18:00';
    for (final entry in contextTemplates.entries) {
      if (!result.containsKey(entry.key)) continue;
      result[entry.key] = entry.value.replaceAllMapped(
        EmailTemplateRules.tokenPattern,
        (m) => bindings.containsKey(m[1])
            ? escapeEmailHtml(bindings[m[1]]!)
            : m[0]!,
      );
    }
    if (context.products.isNotEmpty && result.containsKey('amount'))
      result['amount'] =
          bindings[scenario == 'deposit'
              ? 'preview_deposit'
              : 'preview_total']!;

    return EmailPreviewScenario(
      templateCode: templateCode,
      scenario: scenario,
      locale: locale,
      tone: tone,
      values: result,
      richCodes: richCodes,
      requiredLinks: requiredLinks,
      contextTemplates: contextTemplates,
      contextDefaults: contextDefaults,
    );
  }

  String composeSubject(String subject) => subject.replaceAllMapped(
    EmailTemplateRules.tokenPattern,
    (m) => richCodes.contains(m[1]) ? m[0]! : values[m[1]] ?? m[0]!,
  );

  /// One scan over authored HTML. Substituted fragments are never reprocessed.
  /// Rich content is admitted only in text context, never HTML attributes.
  String composeHtml(String html, {String? wrapperHtml}) {
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
    final content = out.toString();
    // Delivery substitutes the draft, wraps it once, then completes links.
    // Wrapper placeholders must never reprocess substituted customer text.
    final wrapped = wrapperHtml == null
        ? content
        : wrapperHtml.replaceFirst('{{content}}', content);
    return completeEmailContent(wrapped, requiredLinks);
  }
}
