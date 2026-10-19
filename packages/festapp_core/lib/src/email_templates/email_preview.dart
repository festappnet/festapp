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
String completeEmailContent(String html, List<EmailRequiredLink> links,
        [String? wrapperHtml]) =>
    _completeEmailContent(_wrapEmailContent(html, wrapperHtml), links);

String _wrapEmailContent(String content, String? wrapperHtml) =>
    wrapperHtml == null || wrapperHtml.isEmpty
        ? content
        : wrapperHtml.replaceFirst('{{content}}', content);

bool _missingRequiredLink(String html, EmailRequiredLink link) =>
    link.url.isNotEmpty && !html.contains('href="${escapeEmailHtml(link.url)}"');

String _completeEmailContent(
    String html, List<EmailRequiredLink> links,
    {void Function(int offset, String html, int replacedLength)? onInsertion}) {
  for (final link in links) {
    if (!_missingRequiredLink(html, link)) continue;
    if (html.contains(emailOverviewSlot)) {
      onInsertion?.call(html.indexOf(emailOverviewSlot), link.html, emailOverviewSlot.length);
      html = html.replaceFirst(emailOverviewSlot, link.html);

    }
  }
  return html.replaceAll(emailOverviewSlot, '');
}

/// Read-only presentation of delivery's automatic additions in editor order.
class EmailAuthoringCompletion {
  final Map<String, List<String>> tokenHtml;
  final String leadingHtml, trailingHtml;
  const EmailAuthoringCompletion({required this.tokenHtml,
    required this.leadingHtml, required this.trailingHtml});
  String? forToken(String code, int occurrence) {
    final values = tokenHtml[code];
    return values != null && occurrence < values.length ? values[occurrence] : null;
  }
}

class _PreviewTokenSpan {
  final String code;
  int start, end;
  String html;
  _PreviewTokenSpan(this.code, this.start, this.end, this.html);
}

class _AuthoringCompletionCapture {
  final spans = <_PreviewTokenSpan>[];
  final leading = StringBuffer(), trailing = StringBuffer();
  int bodyStart = 0;
  void insert(int offset, String html, int replacedLength) {
    final owner = spans.where((s) => offset >= s.start && offset < s.end).firstOrNull;
    if (owner != null) {
      final local = offset - owner.start;
      owner.html = owner.html.replaceRange(local, local + replacedLength, html);
    } else {
      (offset < bodyStart ? leading : trailing).write(html);
    }
    final delta = html.length - replacedLength;
    for (final span in spans) {
      if (span == owner) {
        span.end += delta;
      } else if (span.start >= offset) {
        span.start += delta;
        span.end += delta;
      }
    }
    if (offset < bodyStart) bodyStart += delta;
  }
  EmailAuthoringCompletion finish() {
    final values = <String, List<String>>{};
    for (final span in spans) {
      values.putIfAbsent(span.code, () => []).add(span.html.replaceAll(emailOverviewSlot, ''));
    }
    return EmailAuthoringCompletion(tokenHtml: values,
      leadingHtml: leading.toString(), trailingHtml: trailing.toString());
  }
}

class EmailPreviewScenario {
  final String templateCode, scenario, locale, tone;
  final Map<String, String> values;
  final Set<String> richCodes;
  final Map<String, String> contextTemplates;
  final Map<String, String> applicationContextTemplates;
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
    this.applicationContextTemplates = const {},
    this.contextDefaults = const {},
    required this.requiredLinks,
  });
  factory EmailPreviewScenario.fromJson(Map<String, dynamic> json) =>
      EmailPreviewScenario(
        applicationContextTemplates: Map<String, String>.from(
          json['applicationContextTemplates'] as Map? ?? const {},
        ),
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
    applicationContextTemplates: {
      for (final entry in applicationContextTemplates.entries)
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
    if (context.paymentAccount != null) {
      if (result.containsKey('accountNumber')) result['accountNumber'] = context.paymentAccount!.accountNumber;
      if (result.containsKey('iban')) result['iban'] = context.paymentAccount!.iban;
    }
    if (context.deadline != null && result.containsKey('deadline'))
      result['deadline'] = context.deadline!;
    if (context.deadline != null && result.containsKey('offer_expires_at'))
      result['offer_expires_at'] = '${context.deadline} 18:00';
    final templates = {
      ...contextTemplates,
      if (context.ticketsEnabled == false) ...applicationContextTemplates,
    };
    for (final entry in templates.entries) {
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
          bindings[templateCode == 'TICKET_ORDER_PAYMENT_DONE' && scenario == 'deposit'
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
      applicationContextTemplates: applicationContextTemplates,
      contextDefaults: contextDefaults,
    );
  }

  String composeSubject(String subject) => subject.replaceAllMapped(
    EmailTemplateRules.tokenPattern,
    (m) => richCodes.contains(m[1]) ? m[0]! : values[m[1]] ?? m[0]!,
  );

  /// One scan over authored HTML. Substituted fragments are never reprocessed.
  /// Rich content is admitted only in text context, never HTML attributes.
  String composeHtml(String html, {String? wrapperHtml}) =>
      _compose(html, wrapperHtml: wrapperHtml);

  EmailAuthoringCompletion authoringCompletion(String html, {String? wrapperHtml}) {
    final capture = _AuthoringCompletionCapture();
    _compose(html, wrapperHtml: wrapperHtml, capture: capture);
    return capture.finish();
  }

  String _compose(
      String html, {String? wrapperHtml, _AuthoringCompletionCapture? capture}) {
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
            if (capture != null && richCodes.contains(code)) {
              capture.spans.add(_PreviewTokenSpan(code, out.length, out.length + value.length, value));
            }
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
    final wrapped = _wrapEmailContent(content, wrapperHtml);
    if (capture != null && wrapperHtml != null && wrapperHtml.isNotEmpty) {
      final contentOffset = wrapperHtml.indexOf('{{content}}');
      if (contentOffset < 0) {
        capture.spans.clear();
        capture.bodyStart = wrapped.length;
      } else {
        capture.bodyStart = contentOffset;
        for (final span in capture.spans) {
          span.start += contentOffset;
          span.end += contentOffset;
        }
      }
    }
    return _completeEmailContent(wrapped, requiredLinks,
        onInsertion: capture?.insert);
  }
}
