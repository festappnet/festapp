import 'dart:convert';
import 'dart:async';
import 'package:image/image.dart' as image;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/html_media_service.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/images/image_control_client.dart';

final png =
    Uint8List.fromList(image.encodePng(image.Image(width: 1, height: 1)));
const owner = HtmlMediaOwner.occasion(12);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('file import accepts a real JPEG and preserves its bytes', () async {
    final bytes =
        Uint8List.fromList(image.encodeJpg(image.Image(width: 2, height: 2)));
    final media = HtmlMediaDraft();
    addTearDown(media.dispose);
    final source = await media.addBytes(bytes, owner);
    expect(media.previewBytes(source), bytes);
  });
  test('pixel cap rejects oversized PNG metadata before decoding', () async {
    // Valid oversized IHDR/CRC; reject the header before pixel allocation.
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAE4gAABOICAYAAABdmIfLAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=');
    final media = HtmlMediaDraft();
    addTearDown(media.dispose);
    await expectLater(media.addBytes(bytes, owner), throwsA(isA<StateError>()));
  });
  test('editor preview decodes an existing PNG without uploading it', () async {
    var fetches = 0;
    var uploads = 0;
    final media = HtmlMediaDraft(
        owns: (_, __) async => true,
        fetch: (_, scope) async {
          expect(scope, owner);
          fetches++;
          return png;
        },
        upload: (_, __) async {
          uploads++;
          return 'https://assets.test/uploaded.png';
        });
    addTearDown(media.dispose);
    expect(await media.previewSource('https://assets.test/existing.png', owner),
        png);
    expect(await media.previewSource('https://assets.test/existing.png', owner),
        png);
    expect(fetches, 1);
    expect(uploads, 0);
  });
  test('paste stages and deduplicates images; only parent save uploads',
      () async {
    var uploads = 0;
    final media = HtmlMediaDraft(
        owns: (_, __) async => false,
        fetch: (_, __) async => png,
        upload: (_, scope) async {
          expect(scope, owner);
          uploads++;
          return 'https://assets.test/saved.png';
        });
    addTearDown(media.dispose);
    final first =
        await media.importSource('https://external.test/a.png', owner);
    final second = await media.addBytes(png, owner);
    expect(first, second);
    expect(uploads, 0);
    expect(media.previewBytes(first), png);
    final html = '<p>Text</p><img src="$first" alt="Alt" width="1">';
    final saved = await media.prepareHtml(html, '', owner);
    expect(saved, contains('https://assets.test/saved.png'));
    expect(saved, contains('alt="Alt"'));
    expect(await media.prepareHtml(html, '', owner), saved);
    expect(uploads, 1);
  });
  test('parallel save reuses the same in flight upload', () async {
    final response = Completer<String>();
    var uploads = 0;
    final media = HtmlMediaDraft(upload: (_, __) {
      uploads++;
      return response.future;
    });
    addTearDown(media.dispose);
    final src = await media.addBytes(png, owner);
    final html = '<img src="$src">';
    final a = media.prepareHtml(html, '', owner);
    final b = media.prepareHtml(html, '', owner);
    await Future<void>.delayed(Duration.zero);
    expect(uploads, 1);
    response.complete('https://assets.test/saved.png');
    expect(await a, await b);
  });
  test('unknown upload blocks automatic retry until explicitly acknowledged',
      () async {
    var uploads = 0;
    final media = HtmlMediaDraft(upload: (_, __) async {
      uploads++;
      if (uploads == 1) throw const ImageUploadOutcomeUnknown('response lost');
      return 'https://assets.test/saved.png';
    });
    addTearDown(media.dispose);
    final src = await media.addBytes(png, owner);
    final html = '<img src="$src">';
    await expectLater(media.prepareHtml(html, '', owner),
        throwsA(isA<ImageUploadOutcomeUnknown>()));
    await expectLater(media.prepareHtml(html, '', owner),
        throwsA(isA<ImageUploadOutcomeUnknown>()));
    expect(uploads, 1);
    media.allowExplicitUnknownRetry();
    expect(await media.prepareHtml(html, '', owner), contains('saved.png'));
    expect(uploads, 2);
  });
  test(
      'unit scope verifies ownership; matching URL in another scope is imported',
      () async {
    final scopes = <HtmlMediaOwner>[];
    final media = HtmlMediaDraft(
        owns: (_, scope) async {
          scopes.add(scope);
          return scope.isUnit;
        },
        fetch: (_, __) async => png);
    addTearDown(media.dispose);
    const source = 'https://assets.test/shared.png';
    expect(
        await media.importSource(source, const HtmlMediaOwner.unit(3)), source);
    expect(await media.importSource(source, owner),
        contains('html-draft.invalid'));
    expect(scopes, [const HtmlMediaOwner.unit(3), owner]);
    await expectLater(media.importSource(source, const HtmlMediaOwner.none()),
        throwsStateError);
  });
  test('unchanged unresolved images remain unchanged and do not upload',
      () async {
    final media = HtmlMediaDraft(
        upload: (_, __) async => throw StateError('unexpected upload'));
    addTearDown(media.dispose);
    const html = '<p>Old</p><img alt="Missing"><img src="relative.png">';
    expect(await media.prepareHtml(html, html, owner), html);
  });
  test('unsupported and oversized images fail before upload', () async {
    final media = HtmlMediaDraft();
    addTearDown(media.dispose);
    await expectLater(media.addBytes(Uint8List.fromList([1, 2, 3]), owner),
        throwsFormatException);
    await expectLater(
        media.addBytes(Uint8List(HtmlMediaDraft.maxImageBytes + 1), owner),
        throwsStateError);
  });
  test(
      'parent save flushes active fields, awaits writer and coalesces double click',
      () async {
    final coordinator = HtmlSaveCoordinator();
    addTearDown(coordinator.dispose);
    final completed = Completer<void>();
    var flushes = 0;
    var writes = 0;
    coordinator.registerActive('field', () {
      flushes++;
    });
    Future<void> writer() async {
      writes++;
      await completed.future;
    }

    final a = coordinator.save(writer);
    final b = coordinator.save(writer);
    expect(identical(a, b), true);
    expect(flushes, 1);
    expect(writes, 1);
    completed.complete();
    await a;
    coordinator.unregisterActive('field');
    await coordinator.save(() async {
      writes++;
    });
    expect(flushes, 1);
    expect(writes, 2);
  });
  test('field registry keeps stable identity and can target changed grid rows',
      () async {
    final coordinator = HtmlSaveCoordinator();
    addTearDown(coordinator.dispose);
    String first = '<p>One</p>', second = '<p>Two</p>';
    var writes = 0;
    coordinator.registerValue(const HtmlFieldIdentity('row1', 'description'),
        read: () => first,
        write: (value) {
          first = value;
          writes++;
        },
        owner: owner);
    coordinator.registerValue(const HtmlFieldIdentity('row2', 'description'),
        read: () => second,
        write: (value) {
          second = value;
          writes++;
        },
        owner: owner);
    await coordinator.prepareWhere((id) => id.entity == 'row2');
    expect(writes, 1);
    expect(first, '<p>One</p>');
    expect(second, '<p>Two</p>');
    coordinator.clearBindings();
    await coordinator.prepareWhere((_) => true);
    expect(writes, 1);
  });
  test(
      'successful upload survives an entity writer failure and is reused on retry',
      () async {
    var uploads = 0;
    var writes = 0;
    final coordinator =
        HtmlSaveCoordinator(media: HtmlMediaDraft(upload: (_, __) async {
      uploads++;
      return 'https://assets.test/retry.png';
    }));
    addTearDown(coordinator.dispose);
    final src = await coordinator.media.addBytes(png, owner);
    final html = '<img src="$src">';
    Future<void> writer() async {
      final saved = await coordinator.prepare(html, owner);
      expect(saved, contains('retry.png'));
      writes++;
      if (writes == 1) throw StateError('entity conflict');
    }

    await expectLater(coordinator.save(writer), throwsStateError);
    await coordinator.save(writer);
    expect(uploads, 1);
    expect(writes, 2);
  });
  test('GIF animation and transparent PNG keep original bytes through upload',
      () async {
    final transparent = image.Image(width: 1, height: 1, numChannels: 4)
      ..setPixelRgba(0, 0, 20, 30, 40, 0);
    final animated = image.Image(width: 1, height: 1)
      ..setPixelRgba(0, 0, 255, 0, 0, 255);
    animated.addFrame(
        image.Image(width: 1, height: 1)..setPixelRgba(0, 0, 0, 0, 255, 255));
    for (final bytes in [
      Uint8List.fromList(image.encodePng(transparent)),
      Uint8List.fromList(image.encodeGif(animated))
    ]) {
      final media = HtmlMediaDraft(upload: (uploaded, __) async {
        expect(uploaded, bytes);
        return 'https://assets.test/original';
      });
      addTearDown(media.dispose);
      final src = await media.addBytes(bytes, owner);
      expect(media.previewBytes(src), bytes);
      await media.prepareHtml('<img src="$src">', '', owner);
    }
  });
  test('removing an unknown image does not require retry or another upload',
      () async {
    var uploads = 0;
    final media = HtmlMediaDraft(upload: (_, __) async {
      uploads++;
      throw const ImageUploadOutcomeUnknown('lost response');
    });
    addTearDown(media.dispose);
    final src = await media.addBytes(png, owner);
    final html = '<img src="$src">';
    await expectLater(media.prepareHtml(html, '', owner),
        throwsA(isA<ImageUploadOutcomeUnknown>()));
    expect(media.hasUnknownUploadsIn('<p>Removed</p>'), false);
    expect(
        await media.prepareHtml('<p>Removed</p>', '', owner), '<p>Removed</p>');
    expect(uploads, 1);
  });
}
