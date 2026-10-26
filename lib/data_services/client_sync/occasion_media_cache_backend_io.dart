import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:fstapp/data_services/client_sync/occasion_media_cache_backend.dart';

OccasionMediaCacheBackend createOccasionMediaCacheBackend() =>
    DefaultOccasionMediaCacheBackend();

class DefaultOccasionMediaCacheBackend implements OccasionMediaCacheBackend {
  DefaultOccasionMediaCacheBackend({BaseCacheManager? cacheManager})
      : _cacheManager = cacheManager ?? DefaultCacheManager();

  final BaseCacheManager _cacheManager;

  @override
  Future<bool> contains(Uri url) async =>
      await _cacheManager.getFileFromCache(url.toString()) != null;

  @override
  Future<void> download(Uri url) async {
    await _cacheManager.downloadFile(url.toString());
  }
}
