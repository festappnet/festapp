import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/fonts/ticket_font_catalog.dart';
import 'package:fstapp/components/ticket_layout/ticket_preview_assets.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';
import 'package:fstapp/components/fonts/font_resource_loading.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fixtures/blueprint_native_font_fixture.dart';

import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

class _FailOnceBundle extends CachingAssetBundle {
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (++loads == 1) throw StateError('temporary_asset_failure');
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('font catalog retry recovers after a failed asset request', () async {
    const path = '${TicketPreviewAssets.root}font-catalog.json';
    var loads = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    rootBundle.evict(path);
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = const StringCodec().decodeMessage(message);
      if (key == path && ++loads == 1) return null;
      return ByteData.sublistView(File(key!).readAsBytesSync());
    });
    addTearDown(() {
      messenger.setMockMessageHandler('flutter/assets', null);
      rootBundle.evict(path);
    });

    await Future.wait([
      expectLater(TicketFontCatalog.loadFamilies(), throwsA(anything)),
      expectLater(TicketFontCatalog.load(), throwsA(anything)),
    ]);
    expect(loads, 1, reason: 'concurrent callers share the pending request');
    final families = await TicketFontCatalog.loadFamilies();
    expect(families, isNotEmpty);
    expect(loads, 2);
    await TicketFontCatalog.loadFamilies();
    expect(loads, 2, reason: 'successful catalogs stay cached');
  });

  test(
    'font preview manifest retry recovers after a failed asset request',
    () async {
      final bundle = _FailOnceBundle();
      final assets = TicketPreviewAssets(bundle: bundle);
      final pending = assets.manifest;
      expect(assets.manifest, same(pending));
      await expectLater(pending, throwsStateError);
      final manifest = await assets.manifest;
      expect(manifest['fonts'], isNotEmpty);
      expect(bundle.loads, 2);
      expect(await assets.manifest, same(manifest));
      expect(assets.manifest, same(assets.manifest));
      expect(bundle.loads, 2);
    },
  );

  testWidgets(
    'bundled public fonts use the existing shared cache without backend requests',
    (tester) async {
      var requests = 0;
      final service = TicketLayoutService(
        transport: (_) async {
          requests++;
          throw StateError('Default font previews must not need the backend');
        },
      );
      await tester.runAsync(() async {
        final face = TicketFontCatalog.defaultLayoutFontId;
        final font = await service.font(1, face);
        expect(font.id, face);
        expect(font.loaderName, 'TicketFont_${face.split(':').last}');
        expect(await service.font(1, face), same(font));
      });
      expect(requests, 0);
    },
  );

  testWidgets(
    'unbundled Roboto recovers automatically through authorized font reads',
    (tester) async {
      var requests = 0;
      final service = TicketLayoutService(
        transport: (request) async {
          if (++requests <= 2) throw const FunctionsHttpException(status: 503);
          return blueprintNativeFontReplyFixture(request);
        },
      );
      await tester.runAsync(() async {
        final families = await TicketFontCatalog.loadFamilies();
        final roboto = families.singleWhere((f) => f['family'] == 'Roboto');
        final face = (roboto['faces'] as Map)['400:normal'] as String;
        expect(
          (await TicketPreviewAssets.shared.manifest)['fonts'],
          isNot(contains(face)),
        );
        final font = await service.font(1, face);
        expect(font.id, face);
        expect(font.loaderName, 'TicketFont_${face.split(':').last}');
        expect(requests, 3);
        await service.font(1, face);
        expect(
          requests,
          4,
          reason: 'unbundled faces require another authorized read',
        );
      });
    },
  );

  testWidgets(
    'automatic font recovery is bounded and does not retry denied access',
    (tester) async {
      var denied = 0;
      await expectLater(
        readFontResource<Object>(() async {
          denied++;
          throw const FunctionsHttpException(status: 403);
        }),
        throwsA(isA<FunctionsHttpException>()),
      );
      expect(denied, 1);
      var failed = 0;
      final pending = expectLater(
        readFontResource<Object>(() async {
          failed++;
          throw const FunctionsHttpException(status: 503);
        }),
        throwsA(isA<FunctionsHttpException>()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 5));
      await pending;
      expect(failed, 4);
    },
  );

  for (final revoked in [false, true]) {
    testWidgets(
      'font context changes require a fresh authorized read (revoked: $revoked)',
      (tester) async {
        final old = RightsService.occasionLinkModelNotifier.value;
        addTearDown(() => RightsService.occasionLinkModelNotifier.value = old);
        var requests = 0;
        final service = TicketLayoutService(
          transport: (request) async {
            if (++requests == 1) {
              RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
                capabilities: {'font-test-scope': true},
              );
            } else if (revoked) {
              throw const FunctionsHttpException(status: 403);
            }
            return blueprintNativeFontReplyFixture(request);
          },
        );
        await tester.runAsync(() async {
          final families = await TicketFontCatalog.loadFamilies();
          final roboto = families.singleWhere((f) => f['family'] == 'Roboto');
          final face = (roboto['faces'] as Map)['400:normal'] as String;
          if (revoked) {
            await expectLater(
              service.font(1, face),
              throwsA(isA<FunctionsHttpException>()),
            );
          } else {
            expect((await service.font(1, face)).id, face);
          }
        });
        expect(requests, 2);
      },
    );
  }
}
