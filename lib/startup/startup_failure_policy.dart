bool shouldEnterOfflineAfterSessionInitializationFailure({
  required bool wasAlreadyOffline,
  required bool supabaseInitialized,
}) {
  return wasAlreadyOffline || !supabaseInitialized;
}

Duration occasionLoadTimeout({required bool hasCachedSettings}) =>
    Duration(seconds: hasCachedSettings ? 5 : 15);
