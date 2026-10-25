import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:fstapp/services/import_file.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_resources.dart';
import 'package:fstapp/components/blueprint/views/blueprint_layout_background.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/images/image_control_client.dart';
import 'package:fstapp/components/images/image_file_format.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final background in [false, true]) {
    for (final cancelled in [false, true]) {
      test(
          'actual ${background ? 'background' : 'graphic'} upload merges latest resources cancellation=$cancelled',
          () async {
        final bytes = base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC');
        final hash = sha256.convert(bytes).toString();
        final otherBytes = [...bytes, 0];
        final otherHash = sha256.convert(otherBytes).toString();
        final otherRef = 'image:$otherHash';
        final asset = <String, dynamic>{
          'assetRef': 'image:$hash',
          'hash': hash,
          'url': 'https://images.example.test/new.png',
          'width': 2,
          'height': 2,
          'mimeType': 'image/png',
          'byteLength': bytes.length
        };
        final response = Completer<http.Response>();
        final requested = Completer<void>();
        final resolver = BlueprintLayoutAssetResolver(client: MockClient((_) {
          requested.complete();
          return response.future;
        }));
        addTearDown(resolver.dispose);
        final controller =
            VenueLayoutController(VenueLayoutDocument.empty(), resources: {
          'protocol': 2,
          'fontFamilies': {},
          'textLayouts': {},
        });
        addTearDown(controller.dispose);
        var live = true;
        Future<ImageUploadResult> upload(Uint8List _) async =>
            ImageUploadResult(asset['url'] as String, asset: asset);
        final pending = background
            ? uploadBlueprintBackground(
                selection: ImportFile.fromData(bytes, name: 'new.png'),
                controller: controller,
                assets: resolver,
                isMounted: () => live,
                occasionId: 1,
                uploadBitmap: upload)
            : uploadBlueprintGraphic(
                selection: ImportFile.fromData(bytes, name: 'new.png'),
                controller: controller,
                assets: resolver,
                isMounted: () => live,
                occasionId: 1,
                uploadBitmap: upload,
                prepareText: (_) => throw StateError('bitmap_only'));
        await requested.future;
        final current = controller.resources;
        expect(
            controller.setResources({
              ...current,
              'assets': {
                ...current['assets'] as Map? ?? {},
                otherRef: {
                  ...asset,
                  'hash': otherHash,
                  'byteLength': otherBytes.length
                }..remove('assetRef')
              }
            }),
            isTrue);
        final latest = controller.resources;
        if (cancelled) live = false;
        final completion =
            cancelled ? expectLater(pending, throwsStateError) : pending;
        response.complete(http.Response.bytes(bytes, 200));
        await completion;
        expect((controller.resources['assets'] as Map).containsKey(otherRef),
            isTrue);
        if (cancelled) {
          expect(controller.resources, latest);
          expect(controller.document.nodes, isEmpty);
          expect(controller.document.background, isNull);
          expect(controller.dirty, isFalse);
        } else {
          expect(
              (controller.resources['images'] as Map)
                  .containsKey('image:$hash'),
              isTrue);
          expect(
              background
                  ? controller.document.background != null
                  : controller.document.nodes.isNotEmpty,
              isTrue);
          controller.undo();
          expect(controller.document.nodes, isEmpty);
          expect(controller.document.background, isNull);
          expect(controller.canUndo, isFalse,
              reason: 'resource contribution adds no undo entry');
        }
      });
    }
  }
  test(
      'background upload preserves verified processed manifest and SVG source MIME',
      () async {
    final hash = List.filled(64, 'a').join();
    final asset = {
      'assetRef': 'image:$hash',
      'hash': hash,
      'url': 'https://img.festapp.net/assets/background.png',
      'width': 2,
      'height': 3,
      'byteLength': 80,
      'mimeType': 'image/png',
      'state': 'ready'
    };
    final svg = Uint8List.fromList(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'));
    expect(() => ImageFileFormat.detect(svg), throwsFormatException);
    final client = ImageControlClient(
        endpoint: 'https://image-api.festapp.net',
        projectId: 'fixture',
        httpClient: MockClient((request) async {
          expect(latin1.decode(request.bodyBytes), contains('image/svg+xml'));
          return http.Response(
              jsonEncode({'url': asset['url'], 'asset': asset}), 200);
        }));
    final result = await client.uploadWithResult(
        bytes: svg,
        filename: 'background.svg',
        accessToken: 'fixture',
        occasionId: 1,
        profile: ImageUploadProfile.blueprintBackground);
    expect(result.asset, asset);
    expect(result.url, asset['url']);
  });
  test('background upload rejects URL-only responses as uncertain, not ready',
      () async {
    final client = ImageControlClient(
        endpoint: 'https://image-api.festapp.net',
        projectId: 'fixture',
        httpClient: MockClient((_) async => http.Response(
            '{"url":"https://img.festapp.net/background.png"}', 200)));
    await expectLater(
        client.uploadWithResult(
            bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
            filename: 'background.png',
            accessToken: 'fixture',
            occasionId: 1,
            profile: ImageUploadProfile.blueprintBackground),
        throwsA(isA<ImageUploadOutcomeUnknown>()));
  });
}
