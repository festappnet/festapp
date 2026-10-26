import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/occasion_media_cache.dart';

void main() {
  test('downloads missing media, skips cached URLs, and survives one failure',
      () async {
    final cached = Uri.parse('https://img.festapp.net/cached.webp');
    final broken = Uri.parse('https://img.festapp.net/broken.webp');
    final fresh = Uri.parse('https://img.festapp.net/fresh.webp');
    final backend = _FakeBackend(cached: {cached}, broken: {broken});
    final cache = OccasionMediaCache(backend: backend);

    await cache.cacheAll([cached, broken, fresh, fresh]);

    expect(backend.downloaded, containsAll([broken, fresh]));
    expect(backend.downloaded, isNot(contains(cached)));
    expect(backend.downloaded.where((url) => url == fresh), hasLength(1));
  });

  test('refreshes an existing URL when a new catalog generation activates',
      () async {
    final existing = Uri.parse('https://img.festapp.net/description.webp');
    final backend = _FakeBackend(cached: {existing}, broken: const {});
    final cache = OccasionMediaCache(backend: backend);

    await cache.cacheAll([existing], refreshExisting: true);

    expect(backend.downloaded, [existing]);
  });
}

class _FakeBackend implements OccasionMediaCacheBackend {
  _FakeBackend({required this.cached, required this.broken});

  final Set<Uri> cached;
  final Set<Uri> broken;
  final List<Uri> downloaded = [];

  @override
  Future<bool> contains(Uri url) async => cached.contains(url);

  @override
  Future<void> download(Uri url) async {
    downloaded.add(url);
    if (broken.contains(url)) throw StateError('unavailable');
  }
}
