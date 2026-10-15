import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'resource_scope.dart';

/// A local client and strict transport. No singleton, persisted session,
/// production URL, timer or previous test's operation log belongs to this scope.
class SupabaseClientFixture {
  SupabaseClientFixture(
      FutureOr<http.Response> Function(http.Request) respond) {
    final transport = MockClient((request) async {
      if (request.url.host != 'fixture.invalid') {
        throw StateError('Unexpected fixture host: ${request.url.host}');
      }
      requests.add(request);
      return respond(request);
    });
    _scope.onDispose(transport.close);
    client = SupabaseClient('https://fixture.invalid', 'synthetic-fixture-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: transport);
    _scope.onDispose(client.dispose);
  }
  final _scope = FixtureScope();
  final requests = <http.Request>[];
  late final SupabaseClient client;
  Future<void> dispose() => _scope.dispose();
}
