abstract interface class OccasionMediaCacheBackend {
  Future<bool> contains(Uri url);

  Future<void> download(Uri url);
}
