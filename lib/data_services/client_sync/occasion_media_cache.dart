import 'package:fstapp/data_services/client_sync/occasion_media_cache_backend.dart';
import 'package:fstapp/data_services/client_sync/occasion_media_cache_backend_io.dart'
    if (dart.library.js_interop) 'package:fstapp/data_services/client_sync/occasion_media_cache_backend_web.dart'
    as platform;

export 'package:fstapp/data_services/client_sync/occasion_media_cache_backend.dart';

/// Best-effort binary sidecar for an atomically activated client-sync catalog.
///
/// JSON activation remains fast and authoritative. Media is filled in with
/// bounded concurrency and retried on later catalog polls; one broken URL does
/// not prevent the remaining occasion images from becoming available offline.
class OccasionMediaCache {
  OccasionMediaCache({
    OccasionMediaCacheBackend? backend,
    this.maxConcurrentDownloads = 3,
  }) : _backend = backend ?? platform.createOccasionMediaCacheBackend();

  final OccasionMediaCacheBackend _backend;
  final int maxConcurrentDownloads;

  Future<void> cacheAll(
    Iterable<Uri> urls, {
    bool refreshExisting = false,
  }) async {
    final queue = urls.toSet().toList(growable: false);
    var next = 0;

    Future<void> worker() async {
      while (next < queue.length) {
        final url = queue[next++];
        try {
          if (refreshExisting || !await _backend.contains(url)) {
            await _backend.download(url);
          }
        } catch (_) {
          // Retry on the next sync poll. Keep filling the rest of the cache.
        }
      }
    }

    final workerCount = queue.length < maxConcurrentDownloads
        ? queue.length
        : maxConcurrentDownloads;
    await Future.wait(List.generate(workerCount, (_) => worker()));
  }
}
