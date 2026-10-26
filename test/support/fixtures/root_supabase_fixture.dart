import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'resource_scope.dart';

/// Only for contracts of the actual application singleton. A suite owns this
/// client until tearDownAll. Groups sharing a cached service require process
/// isolation; groups using disjoint services can own sequential client scopes.
class RootSupabaseFixture {
  RootSupabaseFixture._();
  final _scope = FixtureScope();
  final requests = <http.Request>[];
  static Future<RootSupabaseFixture> open(
      FutureOr<http.Response> Function(http.Request) respond) async {
    final fixture = RootSupabaseFixture._();
    final transport = MockClient((request) async {
      if (request.url.host != 'fixture.invalid') {
        throw StateError('Unexpected fixture host: ${request.url.host}');
      }
      fixture.requests.add(request);
      return respond(request);
    });
    fixture._scope.onDispose(transport.close);
    try {
      final supabase = await Supabase.initialize(
          url: 'https://fixture.invalid',
          publishableKey: 'synthetic-fixture-key',
          authOptions: FlutterAuthClientOptions(
              autoRefreshToken: false,
              persistSession: false,
              detectSessionInUri: false,
              localStorage: const EmptyLocalStorage(),
              pkceAsyncStorage: _PkceStorage()),
          httpClient: transport);
      fixture._scope.onDispose(supabase.dispose);
      return fixture;
    } catch (_) {
      await fixture.dispose();
      rethrow;
    }
  }

  Future<void> dispose() => _scope.dispose();
}

class _PkceStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}
