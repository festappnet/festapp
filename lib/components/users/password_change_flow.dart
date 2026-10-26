enum PasswordChangeResult {
  changedAndSignedIn,
  changedSignInRequired,
  invalidToken,
  failed,
}

Future<PasswordChangeResult> completePasswordChange({
  required String? token,
  required String password,
  required Future<dynamic> Function(String token, String password) change,
  required Future<void> Function(String email, String password) signIn,
}) async {
  final normalizedToken = token?.trim();
  if (normalizedToken == null || normalizedToken.isEmpty) {
    return PasswordChangeResult.invalidToken;
  }

  try {
    final response = await change(normalizedToken, password);
    if (response is! Map) return PasswordChangeResult.failed;

    final code = response['code'];
    if (code == 403 || code == 404) {
      return PasswordChangeResult.invalidToken;
    }
    final email = response['email'];
    if (code != 200 || email is! String || email.trim().isEmpty) {
      return PasswordChangeResult.failed;
    }

    try {
      await signIn(email, password);
      return PasswordChangeResult.changedAndSignedIn;
    } catch (_) {
      return PasswordChangeResult.changedSignInRequired;
    }
  } catch (_) {
    return PasswordChangeResult.failed;
  }
}
