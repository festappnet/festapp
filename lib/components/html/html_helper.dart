import 'package:html/parser.dart' as html_parser;

class HtmlHelper {
  static String stripHtml(String htmlText) {
    return htmlText.replaceAll(
        RegExp(r'<(?!img\b)[^>]*>', caseSensitive: false), '');
  }

  /// Converts an HTML fragment to a single-line, plain-text snippet suitable
  /// for list subtitles: decodes entities, drops every tag (tolerating
  /// truncated or malformed markup such as a dangling "<" left by a naive
  /// substring), and collapses runs of whitespace to single spaces.
  static String htmlToPlainText(String htmlText) {
    final document = html_parser.parse(htmlText);
    final text = document.body?.text ?? '';
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Plain-text snippet for list subtitles: strips markup (via
  /// [htmlToPlainText]) and, when the text is longer than [maxLen], truncates
  /// at a word boundary and appends an ellipsis. Text at or under the limit is
  /// returned unchanged, so short snippets never get a dangling "…".
  static String htmlToSnippet(String? htmlText, {int maxLen = 160}) {
    if (htmlText == null || htmlText.isEmpty) return '';
    final text = htmlToPlainText(htmlText);
    if (text.length <= maxLen) return text;
    var cut = text.substring(0, maxLen);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace > maxLen ~/ 2) cut = cut.substring(0, lastSpace);
    return '${cut.trimRight()}…';
  }

  static bool isHtmlEmptyOrNull(String? htmlText) {
    if (htmlText == null) {
      return true;
    }

    return htmlText
        .replaceAll(RegExp(r'<(?!img\b)[^>]*>', caseSensitive: false), '')
        .trim()
        .isEmpty;
  }

  /// Returns true if the HTML content is “long” (text length exceeds threshold)
  /// or contains at least one <img> tag, indicating it should be shown in a popup.
  static bool isHtmlLong(String? htmlText, {int lengthThreshold = 500}) {
    if (htmlText == null) {
      return false;
    }
    // Quick check for any <img> tags
    if (RegExp(r'<img\b[^>]*>', caseSensitive: false).hasMatch(htmlText)) {
      return true;
    }

    // Strip tags and count plain text length
    final document = html_parser.parse(htmlText);
    final plainText = document.body?.text.trim() ?? '';
    return plainText.length > lengthThreshold;
  }
}
