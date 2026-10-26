Future<void> runLogoutFlow({
  required Future<void> Function() detachNotifications,
  required Future<void> Function() clearPrivateData,
  required Future<void> Function() signOutLocal,
  required Future<void> Function() resetIdentity,
  required Future<void> Function() clearRefreshToken,
  required void Function() clearRights,
  void Function(String step, Object error)? onCleanupError,
}) async {
  Object? signOutError;
  StackTrace? signOutStackTrace;
  try {
    // The local Supabase session is the canonical authentication state. No
    // optional cleanup is allowed to keep it alive.
    await signOutLocal();
  } catch (error, stackTrace) {
    signOutError = error;
    signOutStackTrace = stackTrace;
  }

  Future<void> bestEffort(
      String step, Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      onCleanupError?.call(step, error);
    }
  }

  await bestEffort('refresh-token', clearRefreshToken);
  await bestEffort('private-data', clearPrivateData);
  await bestEffort('identity', resetIdentity);
  try {
    clearRights();
  } catch (error) {
    onCleanupError?.call('rights', error);
  }
  await bestEffort('notifications', detachNotifications);

  if (signOutError != null) {
    Error.throwWithStackTrace(signOutError, signOutStackTrace!);
  }
}
