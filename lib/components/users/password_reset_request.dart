enum PasswordResetRequestResult { sent, missingEmail, failed }

Future<PasswordResetRequestResult> requestPasswordReset({
  required String? email,
  required Future<void> Function(String email) send,
}) async {
  final normalizedEmail = email?.trim();
  if (normalizedEmail == null || normalizedEmail.isEmpty) {
    return PasswordResetRequestResult.missingEmail;
  }

  try {
    await send(normalizedEmail);
    return PasswordResetRequestResult.sent;
  } catch (_) {
    return PasswordResetRequestResult.failed;
  }
}
