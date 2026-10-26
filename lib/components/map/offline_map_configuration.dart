import 'package:fstapp/components/features/map_feature.dart';

/// The only supported offline map source: an integrity-checked bundle manifest.
final class MapLibreOfflineMapContract {
  final String manifestUrl;

  const MapLibreOfflineMapContract({required this.manifestUrl});
}

sealed class OfflineMapStartupDecision {
  const OfflineMapStartupDecision();
}

final class OnlineMapStartup extends OfflineMapStartupDecision {
  final MapLibreOfflineMapContract? availableOfflineContract;

  const OnlineMapStartup({required this.availableOfflineContract});
}

final class ReadyOfflineMapStartup extends OfflineMapStartupDecision {
  final MapLibreOfflineMapContract contract;

  const ReadyOfflineMapStartup({required this.contract});
}

final class InvalidOfflineMapStartup extends OfflineMapStartupDecision {
  const InvalidOfflineMapStartup();
}

/// Canonical policy between occasion configuration and offline map startup.
final class OfflineMapConfiguration {
  final bool forceOffline;
  final MapLibreOfflineMapContract? selectedContract;

  const OfflineMapConfiguration._({
    required this.forceOffline,
    required this.selectedContract,
  });

  factory OfflineMapConfiguration.fromLayer(MapLayer layer) {
    final manifestUrl = _nonEmpty(layer.offlineMapBundleManifestURL);
    return OfflineMapConfiguration._(
      forceOffline: layer.forceOfflineMap,
      selectedContract: manifestUrl == null
          ? null
          : MapLibreOfflineMapContract(manifestUrl: manifestUrl),
    );
  }

  bool get shouldInitialize => selectedContract != null || forceOffline;

  /// Whether the first frame must avoid the online renderer while the
  /// asynchronous connectivity check is still pending.
  bool useOfflineWhileConnectivityLoads({
    required bool isKnownOffline,
    bool hasAuthoritativeConfiguration = true,
    bool isWeb = false,
  }) =>
      !isWeb &&
      (forceOffline || isKnownOffline || !hasAuthoritativeConfiguration);

  OfflineMapStartupDecision resolveStartup({required bool hasConnection}) {
    final contract = selectedContract;
    if (contract == null) {
      return forceOffline
          ? const InvalidOfflineMapStartup()
          : const OnlineMapStartup(availableOfflineContract: null);
    }
    return forceOffline || !hasConnection
        ? ReadyOfflineMapStartup(contract: contract)
        : OnlineMapStartup(availableOfflineContract: contract);
  }
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
