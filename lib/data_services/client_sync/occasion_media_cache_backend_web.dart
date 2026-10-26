import 'dart:js_interop';

import 'package:fstapp/data_services/client_sync/occasion_media_cache_backend.dart';
import 'package:web/web.dart' as web;

OccasionMediaCacheBackend createOccasionMediaCacheBackend() =>
    BrowserOccasionMediaCacheBackend();

/// Persists media across PWA restarts. The service worker serves these entries
/// back to normal cross-origin image requests while offline.
class BrowserOccasionMediaCacheBackend implements OccasionMediaCacheBackend {
  static const cacheName = 'festapp-occasion-media-v1';

  Future<web.Cache> _cache() => web.window.caches.open(cacheName).toDart;

  @override
  Future<bool> contains(Uri url) async =>
      await (await _cache()).match(url.toString().toJS).toDart != null;

  @override
  Future<void> download(Uri url) async {
    final response = await web.window.fetch(url.toString().toJS).toDart;
    if (!response.ok) {
      throw StateError('Media download failed with HTTP ${response.status}');
    }
    await (await _cache()).put(url.toString().toJS, response.clone()).toDart;
  }
}
