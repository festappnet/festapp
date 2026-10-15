import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/html_document_codec.dart';
import 'package:html/parser.dart' as parser;

String fixture(String name) => File(
      'test/components/html/fixtures/$name.html',
    ).readAsStringSync();

void main() {
  for (final name in [
    'app_content',
    'song_content',
    'email_body',
    'full_document',
    'images',
  ]) {
    test('$name: exact no-op HTML and stable slots', () {
      final source = fixture(name);
      final draft = HtmlDocumentCodec.decode(source);
      expect(draft.encode(), source);
      final ids = draft.textSlots.map((slot) => slot.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      if (draft.textSlots.isNotEmpty) {
        final slot = draft.textSlots.first;
        final old = slot.text;
        draft.replaceText(slot.id, 'Změna & < > " 👩🏽‍💻');
        expect(draft.textSlots.first.id, slot.id);
        draft.replaceText(slot.id, old);
        expect(draft.encode(), source);
      }
    });
  }

  test('empty values and image-only content remain distinct', () {
    for (final value in [null, '', '<p><br></p>']) {
      expect(HtmlDocumentCodec.decode(value).encode(), value ?? '');
    }
    const image = '<img src="https://images.example/p.png">';
    final draft = HtmlDocumentCodec.decode(image);
    expect(draft.textSlots, isEmpty);
    expect(draft.imageSlots, hasLength(1));
    expect(draft.encode(), image);
  });

  test('edit a real body variable inside nested email layout', () {
    final draft = HtmlDocumentCodec.decode(fixture('email_body'));
    final name = draft.textSlots.singleWhere((slot) => slot.text == '{{name}}');
    draft.replaceText(name.id, '{{recipientName}}');
    final parsed = parser.parseFragment(draft.encode());
    expect(parsed.querySelector('strong')!.text, '{{recipientName}}');
    expect(parsed.querySelectorAll('table'), hasLength(2));
    expect(parsed.querySelectorAll('thead td'), hasLength(1));
    expect(parsed.querySelectorAll('th'), hasLength(2));
    expect(parsed.querySelector('td[rowspan]')!.attributes['rowspan'], '2');
    expect(parsed.querySelector('a')!.attributes['href'], '{{resetLink}}');
    expect(parsed.querySelector('a')!.attributes['style'],
        contains('padding:12px'));
    expect(draft.encode(), contains('{{orderNumber}}'));
  });

  test('song whitespace and nested list attributes survive adjacent text edit',
      () {
    final song = HtmlDocumentCodec.decode(fixture('song_content'));
    final text =
        song.textSlots.singleWhere((slot) => slot.text == 'Vedlejší text');
    song.replaceText(text.id, 'Nový text & další');
    expect(
        parser.parseFragment(song.encode()).querySelector('pre')!.text,
        parser
            .parseFragment(fixture('song_content'))
            .querySelector('pre')!
            .text);
    final app = HtmlDocumentCodec.decode(fixture('app_content'));
    app.replaceText(app.textSlots.first.id, 'Nový nadpis');
    final parsed = parser.parseFragment(app.encode());
    expect(parsed.querySelector('ol')!.attributes['start'], '3');
    expect(parsed.querySelector('li')!.attributes['value'], '4');
    expect(parsed.querySelectorAll('li ul li'), hasLength(1));
    expect(parsed.querySelector('.ql-indent-2')!.attributes['data-list'],
        'bullet');
    expect(parsed.querySelector('.ql-align-center')!.attributes['style'],
        'text-align:center');
    expect(parsed.querySelector('span')!.attributes['style'],
        contains('color:#aabbcc'));
  });

  test('text assignment escapes once and preserves Unicode/NBSP', () {
    final draft = HtmlDocumentCodec.decode('<p><strong>Text</strong></p>');
    draft.replaceText(
        draft.textSlots.single.id, 'Čeština 👩🏽‍💻\u00a0& <tag> "');
    final result = draft.encode();
    expect(parser.parseFragment(result).querySelector('strong')!.text,
        'Čeština 👩🏽‍💻\u00a0& <tag> "');
    expect(result, isNot(contains('&amp;amp;')));
  });

  test('full document does not acquire a second HTML/body envelope', () {
    final draft = HtmlDocumentCodec.decode(fixture('full_document'));
    final slot =
        draft.textSlots.singleWhere((slot) => slot.text == 'Ahoj {{name}}');
    draft.replaceText(slot.id, 'Ahoj {{recipientName}}');
    final result = draft.encode();
    expect(RegExp('<html').allMatches(result), hasLength(1));
    expect(RegExp('<body').allMatches(result), hasLength(1));
    expect(parser.parse(result).querySelector('style')!.text,
        contains('padding: 8px'));
  });

  test('image replacement preserves dimensions, styles and other images', () {
    final draft = HtmlDocumentCodec.decode(fixture('images'));
    final images = draft.imageSlots.toList();
    expect(images, hasLength(4));
    expect(images[2].hasUnresolvedSource, isTrue);
    expect(images[3].hasUnresolvedSource, isTrue);
    draft.replaceImageSource(
        images[0].id, 'https://images.example/stored.webp');
    final first = parser.parseFragment(draft.encode()).querySelector('img')!;
    expect(first.attributes['width'], '251');
    expect(first.attributes['height'], '300');
    expect(first.attributes['alt'], 'Žluťoučký & kůň');
    expect(first.attributes['style'], 'max-width:100%;height:auto');
    expect(images[1].source, 'https://images.example/alpha.png');
    expect(() => draft.replaceImageSource(images[0].id, 'javascript:alert(1)'),
        throwsArgumentError);
  });

  test('resolve relative sources only with an explicit source base', () {
    const source = '<p><a href="tickets">Text</a></p><img src="photo.png">';
    expect(HtmlDocumentCodec.decode(source).encode(), source);
    final draft = HtmlDocumentCodec.decode(source,
        sourceBase: Uri.parse('https://images.example/event/'));
    expect(draft.imageSlots.single.source,
        'https://images.example/event/photo.png');
    expect(
        parser
            .parseFragment(draft.encode())
            .querySelector('a')!
            .attributes['href'],
        'https://images.example/event/tickets');
  });

  test('sanitize executable HTML, CSS and template URL prefixes', () {
    final draft = HtmlDocumentCodec.decode(fixture('unsafe_content'));
    final parsed = parser.parseFragment(draft.encode());
    expect(parsed.querySelectorAll('script,iframe,svg'), isEmpty);
    for (final element in parsed.querySelectorAll('*')) {
      expect(
          element.attributes.keys
              .any((name) => name.toString().startsWith('on')),
          isFalse);
    }
    expect(parsed.querySelector('img')!.attributes.containsKey('src'), isFalse);
    expect(
        parsed
            .querySelectorAll('a')
            .every((a) => !a.attributes.containsKey('href')),
        isTrue);
    expect(
        parsed.querySelector('span')!.attributes.containsKey('style'), isFalse);
    expect(parsed.querySelector('custom-safe'), isNull);
    expect(
        parsed.querySelector('b')!.text, 'Zachovaný obsah neznámého elementu');
    expect(HtmlDocumentCodec.decode(draft.encode()).encode(), draft.encode());
  });

  test('unknown field identity fails instead of mutating the wrong text', () {
    final draft = HtmlDocumentCodec.decode('<p>Text</p>');
    expect(() => draft.replaceText('missing', 'Změna'), throwsArgumentError);
    expect(draft.encode(), '<p>Text</p>');
  });
}
