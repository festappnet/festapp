import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns true only when retrying the same migrated refresh token cannot
/// recover the session. Network and server failures must remain retryable and
/// must never erase a valid offline identity.
bool isTerminalAuthRefreshError(Object error) {
  if (error is! AuthException) return false;
  return error.code == 'refresh_token_not_found' ||
      error.code == 'refresh_token_already_used';
}
