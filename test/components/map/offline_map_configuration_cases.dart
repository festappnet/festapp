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

  test('only a manifest configures the offline map', () {
    final configuration = OfflineMapConfiguration.fromLayer(MapLayer.fromJson({
      'offlineMapRenderer': 'legacy',
      'offlineMapPackageURL': 'https://maps.test/old.mbtiles',
      'offlineMapStyleURL': 'https://maps.test/old.json',
      'offlineMapLayerName': 'openmaptiles',
    }));
    expect(configuration.selectedContract, isNull);
    expect(configuration.shouldInitialize, isFalse);
  });

  test('forced offline without a manifest fails for either connectivity state',
      () {
    final configuration = OfflineMapConfiguration.fromLayer(
      MapLayer(forceOfflineMap: true),
    );
    for (final connected in [true, false]) {
      expect(configuration.resolveStartup(hasConnection: connected),
          isA<InvalidOfflineMapStartup>());
    }
  });

  test('configured renderer uses offline mode only when required', () {
    OfflineMapConfiguration configuration({bool forceOffline = false}) =>
        OfflineMapConfiguration.fromLayer(MapLayer(
          offlineMapBundleManifestURL: 'https://maps.test/v2/manifest.json',
          forceOfflineMap: forceOffline,
        ));
    expect(configuration().resolveStartup(hasConnection: true),
        isA<OnlineMapStartup>());
    expect(configuration().resolveStartup(hasConnection: false),
        isA<ReadyOfflineMapStartup>());
    expect(
        configuration(forceOffline: true).resolveStartup(hasConnection: true),
        isA<ReadyOfflineMapStartup>());
  });

  test(
      'forced offline map never exposes the online renderer while probing connectivity',
      () {
    final configuration = OfflineMapConfiguration.fromLayer(
      MapLayer(
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
      MapLayer(),
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

  test('initializes configured or forced bundles only', () {
    expect(OfflineMapConfiguration.fromLayer(MapLayer()).shouldInitialize,
        isFalse);
    expect(
        OfflineMapConfiguration.fromLayer(MapLayer(forceOfflineMap: true))
            .shouldInitialize,
        isTrue);
    expect(
        OfflineMapConfiguration.fromLayer(MapLayer(
          offlineMapBundleManifestURL: 'https://maps.test/v2/manifest.json',
        )).shouldInitialize,
        isTrue);
    expect(
        OfflineMapConfiguration.fromLayer(MapLayer(
          offlineMapBundleManifestURL: '  ',
        )).shouldInitialize,
        isFalse);
  });

  test('online startup retains its manifest for an offline switch', () {
    final configuration = OfflineMapConfiguration.fromLayer(MapLayer(
      offlineMapBundleManifestURL: ' https://maps.test/v2/manifest.json ',
    ));
    final startup =
        configuration.resolveStartup(hasConnection: true) as OnlineMapStartup;
    expect(startup.availableOfflineContract?.manifestUrl,
        'https://maps.test/v2/manifest.json');
  });
}
