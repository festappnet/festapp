import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/auth_refresh_recovery.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('only terminal migrated refresh failures clear the local session', () {
    expect(
      isTerminalAuthRefreshError(
        const AuthException('', code: 'refresh_token_not_found'),
      ),
      isTrue,
    );
    expect(
      isTerminalAuthRefreshError(
        const AuthException('', code: 'refresh_token_already_used'),
      ),
      isTrue,
    );
    expect(
      isTerminalAuthRefreshError(
        const AuthException('', code: 'unexpected_failure'),
      ),
      isFalse,
    );
    expect(isTerminalAuthRefreshError(Exception('offline')), isFalse);
  });
}
