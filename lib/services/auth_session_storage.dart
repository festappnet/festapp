import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the shared web/Flutter session using the Dart SDK's numeric contract.
class AuthSessionStorage extends SharedPreferencesLocalStorage {
  AuthSessionStorage({required super.persistSessionKey});

  @override
  Future<String?> accessToken() async {
    final stored = await super.accessToken();
    if (stored == null) return null;
    final session = jsonDecode(stored);
    // supabase-js setSession computes exp - Date.now()/1000, producing a
    // fractional expires_in. GoTrue Dart casts this field to int during restore.
    // Preserve tokens, identity and absolute expiry; normalize only duration.
    if (session is Map<String, dynamic>) {
      final duration = session['expires_in'];
      if (duration is double && duration.isFinite) {
        session['expires_in'] = duration.floor();
        return jsonEncode(session);
      }
    }
    return stored;
  }
}
