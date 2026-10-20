import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/waitlist_commands.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fixtures/client_command_response_fixture.dart';

void main() {
  SupabaseClient clientWith(
    Future<Object> Function(Map<String, dynamic>, Uri) respond,
  ) {
    final client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final response = await respond(body, request.url);
        return http.Response(jsonEncode(response), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    addTearDown(client.dispose);
    return client;
  }

  for (final acceptance in [false, true]) {
    test(
        'confirmed ${acceptance ? 'acceptance' : 'command'} uses its sent identity',
        () async {
      final sent = <Map<String, dynamic>>[];
      final commands = WaitlistCommands(clientWith((body, uri) async {
        expect(
            uri.path,
            acceptance
                ? '/functions/v1/send-ticket-order'
                : '/functions/v1/waitlist-commands');
        expect(body.containsKey('p_command_id'), isFalse);
        sent.add(body);
        return commandResponseFixture(body['commandId'], data: {'code': 200});
      }));
      Future<Map<String, dynamic>> invoke() => acceptance
          ? commands.accept(
              offerId: 'offer',
              token: 'capability',
              ticketIds: [1],
              orderDetails: {'name': 'Alex'})
          : commands.command('register', {'formId': 1});
      expect(await invoke(), {'code': 200});
      expect(await invoke(), {'code': 200});
      expect(sent[0]['commandId'], isNot(sent[1]['commandId']));
      expect(sent[0]['clientId'], sent[1]['clientId']);
      if (acceptance) {
        expect(sent[0]['waitlistAcceptance']['token'], 'capability');
      }
    });
  }

  for (final code in [408, 429, 503]) {
    test('transient $code retains identity across reordered equivalent payload',
        () async {
      final sent = <Map<String, dynamic>>[];
      final commands = WaitlistCommands(clientWith((body, _) async {
        sent.add(body);
        return commandResponseFixture(body['commandId'],
            status: sent.length == 1 ? 'rejected' : 'applied',
            code: sent.length == 1 ? code : 200,
            data: {'errorCode': 'TRY_AGAIN'});
      }));
      await expectLater(commands.command('register', {'a': 1, 'b': 2}),
          throwsA(isA<WaitlistCommandException>()));
      await commands.command('register', {'b': 2, 'a': 1});
      expect(sent[0]['commandId'], sent[1]['commandId']);
    });
  }

  test('malformed and mismatched replies preserve pending identity', () async {
    final ids = <String>[];
    final commands = WaitlistCommands(clientWith((body, _) async {
      ids.add(body['commandId']);
      if (ids.length == 1) return {'code': 200};
      return commandResponseFixture(ids.length == 2
          ? '00000000-0000-4000-8000-000000000009'
          : body['commandId']);
    }));
    for (var i = 0; i < 2; i++) {
      await expectLater(commands.command('register', {'formId': 1}),
          throwsA(isA<FormatException>()));
    }
    await commands.command('register', {'formId': 1});
    expect(ids.toSet(), hasLength(1));
  });

  test('transport retry freezes nested capability payload and sent identity',
      () async {
    final payload = <String, dynamic>{
      'token': 'original',
      'tickets': [1]
    };
    final sent = <Map<String, dynamic>>[];
    final commands = WaitlistCommands(clientWith((body, _) async {
      sent.add(body);
      if (sent.length == 1) {
        payload['token'] = 'edited';
        (payload['tickets'] as List).add(2);
        throw TimeoutException('ambiguous response');
      }
      return commandResponseFixture(body['commandId']);
    }));
    await commands.command('decline', payload);
    expect(sent, hasLength(2));
    expect(sent[1], sent[0]);
    expect(sent[1]['payload'], {
      'token': 'original',
      'tickets': [1]
    });
  });
}
