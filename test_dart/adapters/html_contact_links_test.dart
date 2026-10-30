import 'package:test/test.dart';
import 'dart:convert';
import 'dart:io';
import 'package:fstapp/components/html/html_document_codec.dart';
import 'package:html/parser.dart' as parser;

List<String> links(String html) => parser
    .parseFragment(html)
    .querySelectorAll('a')
    .map((a) => a.attributes['href']!)
    .toList();

void main() {
  final cases = jsonDecode(File('shared/html/app-content-cases.json').readAsStringSync()) as List;
  for (final entry in cases) {
    test('canonical app HTML: ${entry['name']}', () {
      final result = normalizeHtmlContentStyles(entry['html'] as String, HtmlContentProfile.appContent);
      final root = parser.parseFragment(result);
      expect(root.querySelector(entry['selector'] as String)?.text, entry['text']);
      if (entry['aligned'] != null) {
        expect(root.querySelector(entry['aligned'] as String)!.attributes['style'], contains('text-align:center'));
      }
      if (entry['table'] != null) expect(root.querySelector(entry['table'] as String)?.text, 'Cell');
      expect(result, isNot(matches(RegExp(r'Arial|color:|face=|bgcolor=', caseSensitive: false))));
      expect(normalizeHtmlContentStyles(result, HtmlContentProfile.appContent), result);
    });
  }
  test('app HTML drops font and color overrides on legacy and pasted content', () {
    const source =
        '<style>p { font-family: Arial; color: red }</style>'
        '<h2><span style="FONT-FAMILY:Arial,sans-serif!important;color:red">Title</span></h2>'
        '<p style="font:italic 18px Arial;background:red;text-align:center">'
        '<font face="Arial" color="red"><strong>Text</strong></font></p>'
        '<ul><li style="font-family:Arial;background-color:blue;font-weight:bold">Item</li></ul>';
    final result = normalizeHtmlContentStyles(
      source,
      HtmlContentProfile.appContent,
    );
    final root = parser.parseFragment(result);
    expect(root.querySelector('style'), isNull);
    expect(result.toLowerCase(), isNot(contains('arial')));
    expect(result, isNot(contains('color:')));
    expect(result, isNot(contains('background:')));
    expect(
      root.querySelector('p')!.attributes['style'],
      contains('text-align:center'),
    );
    expect(root.querySelector('li strong')!.text, 'Item');
    expect(root.querySelector('strong')!.text, 'Text');
    expect(
      normalizeHtmlContentStyles(result, HtmlContentProfile.appContent),
      result,
    );
    for (final profile in [
      HtmlContentProfile.emailContent,
      HtmlContentProfile.songContent,
    ]) {
      expect(normalizeHtmlContentStyles(source, profile), source);
    }
  });
  group('html_contact_links', () {
    for (final entry in {
      '731140198': '731140198',
      '731 140 198': '731140198',
      '731-140-198': '731140198',
      '731.140.198': '731140198',
      '731\u00a0140\u00a0198': '731140198',
      '+420731140198': '+420731140198',
      '+420 731 140 198': '+420731140198',
      '00420 731 140 198': '+420731140198',
      '+44 20 7946 0958': '+442079460958',
    }.entries) {
      test('links ${entry.key} in existing and edited app content', () {
        final html = '<p>or call ${entry.key}.</p>';
        for (final result in [
          linkifyHtmlText(html),
          applyHtmlContentProfile(html, HtmlContentProfile.appContent)
        ]) {
          expect(links(result), ['tel:${entry.value}']);
          expect(parser.parseFragment(result).text, 'or call ${entry.key}.');
        }
      });
    }

    test('recognizes emails and URLs with correct schemes and punctuation', () {
      final result =
          linkifyHtmlText('<p>info+test@example.org, WWW.example.org; '
              'https://example.org/?contact=info@example.org.</p>');
      expect(links(result), [
        'mailto:info+test@example.org',
        'https://WWW.example.org',
        'https://example.org/?contact=info@example.org'
      ]);
    });

    test('preserves manual links, code, attributes, styling and templates', () {
      const original = '<p style="color:red" data-phone="731140198">'
          '<a href="https://custom.example">731140198</a> '
          '<code>731140198</code><pre>info@example.org</pre>'
          '{{contact}} 731140198</p>';
      expect(linkifyHtmlText(original), original);
      final result = linkifyHtmlText('<p style="color:red">731140198</p>');
      expect(result, contains('style="color:red"'));
      expect(linkifyHtmlText(result), result);
      for (final profile in [
        HtmlContentProfile.songContent,
        HtmlContentProfile.emailContent
      ]) {
        expect(applyHtmlContentProfile(original, profile), original);
      }
    });

    test('avoids partial numbers and dates', () {
      const html = '<p>2026-10-01 12345 1234567890 id731140198 '
          '731140198abc +1234567890123456</p>';
      expect(linkifyHtmlText(html), html);
    });
  });
}
