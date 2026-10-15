import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/map_feature.dart';
import 'package:fstapp/components/map/offline_map_configuration.dart';

void main() {
  test('web never selects the native offline renderer', () {
    final configuration = OfflineMapConfiguration.fromLayer(
      MapLayer(forceOfflineMap: true),
    );

    expect(
      configuration.useOfflineWhileConnectivityLoads(
        isKnownOffline: true,
        hasAuthoritativeConfiguration: false,
        isWeb: true,
      ),
      isFalse,
    );
  });

  test('exposes only the selected renderer contract', () {
    final configuration = OfflineMapConfiguration.fromLayer(
      MapLayer(
        offlineMapRenderer: OfflineMapRenderer.maplibre,
        offlineMapBundleManifestURL: 'https://maps.test/v2/manifest.json',
        offlineMapPackageURL: 'https://maps.test/v1/map.mbtiles',
        offlineMapStyleURL: 'https://maps.test/v1/style.json',
        offlineMapLayerName: 'versatiles-shortbread',
      ),
    );

    expect(
      configuration.selectedContract,
      isA<MapLibreOfflineMapContract>(),
    );
    expect(
      (configuration.selectedContract as MapLibreOfflineMapContract)
          .manifestUrl,
      'https://maps.test/v2/manifest.json',
    );
  });

  test('disconnected explicit invalid configuration surfaces an error', () {
    final configuration = OfflineMapConfiguration.fromLayer(
      MapLayer(
        offlineMapRenderer: OfflineMapRenderer.maplibre,
        hasExplicitOfflineMapRenderer: true,
      ),
    );

    expect(
      configuration.resolveStartup(hasConnection: false),
      isA<InvalidOfflineMapStartup>(),
    );
  });

  test('configured renderer uses offline mode only when required', () {
    OfflineMapConfiguration configuration({bool forceOffline = false}) =>
        OfflineMapConfiguration.fromLayer(
          MapLayer(
            offlineMapRenderer: OfflineMapRenderer.maplibre,
            offlineMapBundleManifestURL: 'https://maps.test/v2/manifest.json',
            forceOfflineMap: forceOffline,
          ),
        );

    expect(
      configuration().resolveStartup(hasConnection: true),
      isA<OnlineMapStartup>(),
    );
    expect(
      configuration().resolveStartup(hasConnection: false),
      isA<ReadyOfflineMapStartup>(),
    );
    expect(
      configuration(forceOffline: true).resolveStartup(hasConnection: true),
      isA<ReadyOfflineMapStartup>(),
    );
  });

  test(
      'forced offline map never exposes the online renderer while probing connectivity',
      () {
    final configuration = OfflineMapConfiguration.fromLayer(
      MapLayer(
        offlineMapRenderer: OfflineMapRenderer.maplibre,
        offlineMapBundleManifestURL: 'https://maps.test/v2/manifest.json',
        forceOfflineMap: true,
      ),
    );

    expect(
      configuration.useOfflineWhileConnectivityLoads(isKnownOffline: false),
      isTrue,
    );
  });

  test(
      'known offline startup never exposes the online renderer while probing connectivity',
      () {
    final configuration = OfflineMapConfiguration.fromLayer(
      MapLayer(
        offlineMapRenderer: OfflineMapRenderer.legacy,
        offlineMapPackageURL: 'https://maps.test/v1/map.mbtiles',
        offlineMapStyleURL: 'https://maps.test/v1/style.json',
        offlineMapLayerName: 'versatiles-shortbread',
      ),
    );

    expect(
      configuration.useOfflineWhileConnectivityLoads(isKnownOffline: true),
      isTrue,
    );
  });

  test('missing authoritative map settings never fall back to public tiles',
      () {
    final configuration = OfflineMapConfiguration.fromLayer(MapLayer());

    expect(
      configuration.useOfflineWhileConnectivityLoads(
        isKnownOffline: false,
        hasAuthoritativeConfiguration: false,
      ),
      isTrue,
    );
  });

  test('initialization is skipped only for an untouched online-only layer', () {
    final untouched = OfflineMapConfiguration.fromLayer(MapLayer());
    final explicit = OfflineMapConfiguration.fromLayer(
      MapLayer(
        offlineMapRenderer: OfflineMapRenderer.maplibre,
        hasExplicitOfflineMapRenderer: true,
      ),
    );

    expect(untouched.shouldInitialize, isFalse);
    expect(explicit.shouldInitialize, isTrue);
  });

  test('online startup retains the selected Legacy contract for instant switch',
      () {
    final configuration = OfflineMapConfiguration.fromLayer(
      MapLayer(
        offlineMapRenderer: OfflineMapRenderer.legacy,
        offlineMapPackageURL: 'https://maps.test/v1/map.mbtiles',
        offlineMapStyleURL: 'https://maps.test/v1/style.json',
        offlineMapLayerName: 'versatiles-shortbread',
      ),
    );

    final startup = configuration.resolveStartup(hasConnection: true);

    expect(startup, isA<OnlineMapStartup>());
    expect(
      (startup as OnlineMapStartup).availableOfflineContract,
      isA<LegacyOfflineMapContract>(),
    );
  });

  test('both renderers follow the same force-offline and connectivity policy',
      () {
    for (final renderer in OfflineMapRenderer.values) {
      OfflineMapConfiguration configuration({required bool forceOffline}) =>
          OfflineMapConfiguration.fromLayer(
            MapLayer(
              offlineMapRenderer: renderer,
              offlineMapBundleManifestURL: 'https://maps.test/v2/manifest.json',
              offlineMapPackageURL: 'https://maps.test/v1/map.mbtiles',
              offlineMapStyleURL: 'https://maps.test/v1/style.json',
              offlineMapLayerName: 'versatiles-shortbread',
              forceOfflineMap: forceOffline,
            ),
          );

      expect(
        configuration(forceOffline: false).resolveStartup(hasConnection: true),
        isA<OnlineMapStartup>(),
        reason: '$renderer stays online when offline mode is not forced',
      );
      expect(
        configuration(forceOffline: false).resolveStartup(hasConnection: false),
        isA<ReadyOfflineMapStartup>(),
        reason: '$renderer activates offline when disconnected',
      );
      expect(
        configuration(forceOffline: true).resolveStartup(hasConnection: true),
        isA<ReadyOfflineMapStartup>(),
        reason: '$renderer honors forceOfflineMap while connected',
      );
    }
  });

  test('Legacy uses the shared manifest when present and keeps old URLs valid',
      () {
    final bundled = OfflineMapConfiguration.fromLayer(
      MapLayer(
        offlineMapRenderer: OfflineMapRenderer.legacy,
        offlineMapBundleManifestURL: 'https://maps.test/v2/manifest.json',
        offlineMapPackageURL: 'https://maps.test/v1/map.mbtiles',
        offlineMapStyleURL: 'https://maps.test/v1/style.json',
        offlineMapLayerName: 'versatiles-shortbread',
      ),
    );
    final legacyOnly = OfflineMapConfiguration.fromLayer(
      MapLayer(
        offlineMapRenderer: OfflineMapRenderer.legacy,
        offlineMapPackageURL: 'https://maps.test/v1/map.mbtiles',
        offlineMapStyleURL: 'https://maps.test/v1/style.json',
        offlineMapLayerName: 'versatiles-shortbread',
      ),
    );

    expect(
      bundled.bundleFor(bundled.selectedContract!),
      isA<MapLibreOfflineMapContract>(),
    );
    expect(legacyOnly.bundleFor(legacyOnly.selectedContract!), isNull);
  });
}
