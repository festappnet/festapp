import 'dart:async';

typedef ProfileLoadErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// Loads the enriched profile without letting an optional remote dependency
/// hide the identity already returned by the occasion bootstrap.
Future<T?> loadProfileWithFallback<T>({
  required Future<T?> Function() loadFresh,
  required Future<T?> Function() loadCached,
  required T? Function() loadBootstrap,
  Duration freshTimeout = const Duration(seconds: 8),
  ProfileLoadErrorHandler? onFreshError,
  ProfileLoadErrorHandler? onCacheError,
}) async {
  try {
    final fresh = await loadFresh().timeout(freshTimeout);
    if (fresh != null) return fresh;
  } catch (error, stackTrace) {
    onFreshError?.call(error, stackTrace);
  }

  try {
    final cached = await loadCached();
    if (cached != null) return cached;
  } catch (error, stackTrace) {
    onCacheError?.call(error, stackTrace);
  }

  return loadBootstrap();
}
