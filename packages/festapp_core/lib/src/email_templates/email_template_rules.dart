enum EmailValueKind { text, url, richInline, richBlock }

enum EmailTargetField { subject, body }

class EmailVariableDefinition {
  final String code;
  final EmailValueKind kind;
  final bool repeatable;
  final int order;
  const EmailVariableDefinition({
    required this.code,
    required this.kind,
    this.repeatable = true,
    this.order = 0,
  });
  bool supports(EmailTargetField field) =>
      field == EmailTargetField.body ||
      kind == EmailValueKind.text ||
      kind == EmailValueKind.url;
}

class EmailTitleMatch {
  final int start, end;
  final String text;
  const EmailTitleMatch(this.start, this.end, this.text);
}

/// Pure authoring rules. Persisted substitutions remain {{code}}.
abstract final class EmailTemplateRules {
  static final tokenPattern = RegExp(r'\{\{([A-Za-z_][A-Za-z_0-9]*)\}\}');
  static EmailValueKind kindFor(String code) {
    if (const {
      'fullOrder',
      'paymentDetails',
      'balanceReasoning',
      'changeOverview',
      'order_overview_button',
      'manage_waitlist_button',
      'offer_button',
    }.contains(code))
      return EmailValueKind.richBlock;
    if (const {'platformLinks', 'appLinks'}.contains(code)) {
      return EmailValueKind.richInline;
    }
    if (const {
      'resetLink',
      'confirmationUrl',
      'order_overview_url',
      'manage_waitlist_url',
      'offer_url',
    }.contains(code))
      return EmailValueKind.url;
    return EmailValueKind.text;
  }

  static EmailVariableDefinition definition(String code, {int order = 0}) {
    final kind = kindFor(code);
    return EmailVariableDefinition(
      code: code,
      kind: kind,
      order: order,
      // Whole content sections appear once. Links/buttons and inline content
      // may deliberately appear in several places, regardless of their kind.
      repeatable: !const {
        'fullOrder',
        'paymentDetails',
        'balanceReasoning',
        'changeOverview',
      }.contains(code),
    );
  }

  static bool canTrigger(
    String text,
    int triggerOffset, {
    bool inLink = false,
    bool inCode = false,
    bool composing = false,
  }) {
    if (triggerOffset < 0 ||
        triggerOffset >= text.length ||
        text[triggerOffset] != '@' ||
        inLink ||
        inCode ||
        composing)
      return false;
    if (!_boundary(text, triggerOffset)) return false;
    final prefix = text.substring(0, triggerOffset).split(RegExp(r'\s')).last;
    if (prefix.contains('://') ||
        prefix.toLowerCase().contains('mailto:') ||
        prefix.toLowerCase().startsWith('www.'))
      return false;
    final suffix = text.substring(triggerOffset + 1).split(RegExp(r'\s')).first;
    // Check the existing right half before publishing a composing menu.
    if (suffix.contains('@') ||
        suffix.contains('.') ||
        suffix.contains('/') ||
        suffix.contains(':') ||
        suffix.contains('+'))
      return false;
    return !_insideToken(text, triggerOffset);
  }

  static bool _boundary(String text, int offset) =>
      offset == 0 ||
      RegExp(r'\s').hasMatch(text[offset - 1]) ||
      '([{'.contains(text[offset - 1]);
  static bool _insideToken(String text, int offset) => tokenPattern
      .allMatches(text)
      .any((m) => m.start <= offset && offset < m.end);
  static bool canInsert(
    String text,
    int offset, {
    bool inLink = false,
    bool inCode = false,
    bool composing = false,
  }) {
    if (offset < 0 ||
        offset > text.length ||
        inLink ||
        inCode ||
        composing ||
        _insideToken(text, offset))
      return false;
    final left = text.substring(0, offset).split(RegExp(r'\s')).last;
    final right = text.substring(offset).split(RegExp(r'\s')).first;
    final word = left + right;
    return !word.contains('@') &&
        !word.contains('://') &&
        !word.toLowerCase().startsWith('mailto:') &&
        !RegExp(
          r'^(?:www\.|[^\s]+\.[a-z]{2,}(?:/|$))',
          caseSensitive: false,
        ).hasMatch(word);
  }

  static Map<String, int> occurrences(String text) {
    final counts = <String, int>{};
    for (final match in tokenPattern.allMatches(text)) {
      counts.update(match[1]!, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  static String normalize(String value) {
    const groups = [
      'áàäâãå',
      'čćç',
      'ď',
      'éěèëê',
      'íìïî',
      'ľĺł',
      'ňń',
      'óòöôõ',
      'řŕ',
      'šś',
      'ť',
      'úůùüû',
      'ýÿ',
      'žźż',
    ];
    const ascii = [
      'a',
      'c',
      'd',
      'e',
      'i',
      'l',
      'n',
      'o',
      'r',
      's',
      't',
      'u',
      'y',
      'z',
    ];
    var result = value.toLowerCase();
    for (var i = 0; i < groups.length; i++) {
      result = result.replaceAll(RegExp('[${groups[i]}]'), ascii[i]);
    }
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<T> rank<T>(
    Iterable<T> values, {
    required EmailVariableDefinition Function(T) definition,
    required String Function(T) label,
    String query = '',
    Map<String, int> usage = const {},
    EmailTargetField field = EmailTargetField.body,
  }) {
    final q = normalize(query);
    int score(T item) {
      final d = definition(item);
      final title = normalize(label(item));
      final code = normalize(d.code);
      if (q.isEmpty) return 0;
      if (title == q || code == q) return 0;
      if (title.startsWith(q) || code.startsWith(q)) return 1;
      return 2;
    }

    final result = values
        .where(
          (v) =>
              definition(v).supports(field) &&
              (q.isEmpty ||
                  normalize(label(v)).contains(q) ||
                  normalize(definition(v).code).contains(q)),
        )
        .toList();
    final positions = {for (var i = 0; i < result.length; i++) result[i]: i};
    result.sort((a, b) {
      int used(T v) =>
          !definition(v).repeatable && (usage[definition(v).code] ?? 0) > 0
          ? 1
          : 0;
      final group = used(a).compareTo(used(b));
      if (group != 0) return group;
      final relevance = score(a).compareTo(score(b));
      if (relevance != 0) return relevance;
      final order = definition(a).order.compareTo(definition(b).order);
      return order != 0 ? order : positions[a]!.compareTo(positions[b]!);
    });
    return result;
  }

  static Iterable<EmailTitleMatch> titleMatches(
    String text,
    String title,
  ) sync* {
    final normalized = normalize(title);
    if (normalized.length < 8 ||
        normalized.split(' ').length < 2 ||
        const {'nova akce', 'nase akce', 'test event'}.contains(normalized))
      return;
    final words = title
        .trim()
        .split(RegExp(r'\s+'))
        .map(RegExp.escape)
        .join(r'\s+');
    final pattern = RegExp(words, caseSensitive: false, unicode: true);
    bool word(String c) => RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(c);
    for (final match in pattern.allMatches(text)) {
      if ((match.start > 0 && word(text[match.start - 1])) ||
          (match.end < text.length && word(text[match.end])))
        continue;
      if (!canInsert(text, match.start) || _insideToken(text, match.start))
        continue;
      final before = text.substring(0, match.start);
      // Caller supplies editable text, never HTML or preview values.
      if (before.lastIndexOf('<') > before.lastIndexOf('>')) continue;
      yield EmailTitleMatch(match.start, match.end, match[0]!);
    }
  }
}
