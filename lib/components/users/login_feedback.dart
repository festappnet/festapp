Future<void> finishSuccessfulSignIn({
  required Future<void> Function() navigate,
  Future<void> Function()? recoverNavigation,
  required Future<void> Function() showFeedback,
}) async {
  try {
    await navigate();
  } catch (_) {
    if (recoverNavigation == null) rethrow;
    await recoverNavigation();
  }
  await showFeedback();
}

Future<bool> ensureAuthenticatedSession({
  required bool Function() isLoggedIn,
  required Future<bool> Function() restoreSession,
}) async =>
    isLoggedIn() || await restoreSession();
