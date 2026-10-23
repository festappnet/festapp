import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/blueprint_seat_order_preview.dart';
import 'package:fstapp/components/eshop/seat_order_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import '../../support/fixtures/blueprint_order_preview_fixture.dart';
import '../../support/fixtures/local_app_storage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final failure in ['network', 'http', 'relay', 'authorization'])
    test(
        'production Supabase binding resumes original confirmed Edge HTTP payload ($failure)',
        () async {
      final storage = await LocalAppStorageFixture.open();
      addTearDown(storage.dispose);
      var lose = true;
      final writes = <Map<String, dynamic>>[], reads = <String>[];
      final httpClient = MockClient((request) async {
        expect(request.url.host, 'fixture.invalid');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/preview_blueprint_seat_order')) {
          reads.add(request.url.path);
          expect(body['p_organization'], 3);
          expect(body['p_unit'], 4);
          expect(body['p_blueprint'], 5);
          return http.Response(
              jsonEncode(body['p_input'] == null
                  ? seatOrderRequirementsJson()
                  : seatOrderQuoteJson()),
              200,
              request: request,
              headers: {'content-type': 'application/json'});
        }
        expect(request.url.path, '/functions/v1/send-ticket-order');
        writes.add(body);
        if (lose) {
          if (failure == 'network')
            throw http.ClientException('Synthetic lost HTTP acknowledgement');
          return http.Response('{}', failure == 'authorization' ? 401 : 503,
              request: request,
              headers: {
                'content-type': 'application/json',
                if (failure == 'relay') 'x-relay-error': 'true'
              });
        }
        return http.Response(
            jsonEncode(seatOrderReceiptFixture(body['commandId'] as String)),
            200,
            request: request,
            headers: {'content-type': 'application/json'});
      });
      final client = SupabaseClient(
          'https://fixture.invalid', 'synthetic-fixture-key',
          httpClient: httpClient);
      addTearDown(client.dispose);
      addTearDown(httpClient.close);
      final commands = SupabaseSeatOrderCommands(client),
          request = seatOrderRequestFixture();
      final requirements = await commands.requirements(request);
      final input = {
        'email': 'http-order@example.invalid',
        'form_key': requirements.formKey
      };
      final preview = await commands.preview(requirements, input);
      input['email'] = 'later@example.invalid';
      await expectLater(
          commands.create(preview),
          throwsA(failure == 'authorization'
              ? isA<PostgrestException>()
                  .having((e) => e.code, 'SQL authorization code', '42501')
              : isA<http.ClientException>()));
      final attempts = failure == 'authorization' ? 1 : 2;
      expect(writes, hasLength(attempts));
      lose = false;
      expect(
          (await SupabaseSeatOrderCommands(client).recover(request))!.orderId,
          101);
      expect(reads, hasLength(2));
      expect(writes, hasLength(attempts + 1));
      expect(writes.every((row) => jsonEncode(row) == jsonEncode(writes.first)),
          isTrue);
      final replacement = writes.last['replacement'] as Map,
          confirmation = replacement['confirmation'] as Map;
      expect(replacement['inputData'],
          containsPair('email', 'http-order@example.invalid'));
      expect(replacement['spotIds'], [71]);
      expect(confirmation['targetSpotIds'], [71]);
      expect(confirmation['blueprints'], [
        {'id': 5, 'revision': 3}
      ]);
      expect(confirmation['actorId'], requirements.actorId);
      expect(confirmation['confirmationHash'], preview.confirmationHash);
      expect(confirmation['editor'], true);
    });
  test(
      'lost Edge acknowledgement resumes immutable approved bytes and UUID after recreation',
      () async {
    final storage = await LocalAppStorageFixture.open();
    addTearDown(storage.dispose);
    final calls = <Map<String, dynamic>>[];
    var lose = true;
    Future<Object?> rpc(String name, Map<String, dynamic> params) async {
      calls.add(jsonDecode(jsonEncode(params)) as Map<String, dynamic>);
      if (lose) throw TimeoutException('Actual SQL receipt reply lost');
      return SupabaseSeatOrderCommands.decodeEdgeResponse(
          seatOrderReceiptFixture(params['p_command_id'] as String),
          params['p_command_id'] as String);
    }

    SupabaseSeatOrderCommands port() => SupabaseSeatOrderCommands.withTransport(
        ClientCommandTransport(rpc,
            maxAttempts: 1, principalBinding: 'endpoint:actor'),
        readRpc: (name, params) async => params['p_input'] == null
            ? seatOrderRequirementsJson()
            : seatOrderQuoteJson());
    final first = port(),
        request = seatOrderRequestFixture(),
        requirements = await first.requirements(request);
    final input = {
      'email': 'approved@example.invalid',
      'form_key': requirements.formKey
    };
    final preview = await first.preview(requirements, input);
    input['email'] = 'new@example.invalid';
    await expectLater(first.create(preview), throwsA(isA<TimeoutException>()));
    expect(calls.single['p_input'],
        containsPair('email', 'approved@example.invalid'));
    lose = false;
    final outcome = await port().recover(BlueprintSeatOrderRequest(
        occasionId: 9,
        organizationId: 3,
        unitId: 4,
        blueprintId: 5,
        spotIds: [72]));
    expect(outcome!.orderId, 101);
    expect(calls, hasLength(2));
    expect(calls.last, calls.first);
    expect(await port().recover(request), isNull);
  });
  test(
      'known committed payment preparation retains original journal and validates receipt identity',
      () async {
    final storage = await LocalAppStorageFixture.open();
    addTearDown(storage.dispose);
    var pending = true;
    final ids = <String>[];
    final port = SupabaseSeatOrderCommands.withTransport(
        ClientCommandTransport((name, params) async {
          final id = params['p_command_id'] as String;
          ids.add(id);
          final receipt = seatOrderReceiptFixture(id);
          return SupabaseSeatOrderCommands.decodeEdgeResponse(
              pending ? {'code': 503, 'committed': receipt} : receipt, id);
        }, maxAttempts: 1, principalBinding: 'endpoint:actor'),
        readRpc: (name, params) async => params['p_input'] == null
            ? seatOrderRequirementsJson()
            : seatOrderQuoteJson());
    final request = seatOrderRequestFixture(),
        requirements = await port.requirements(request);
    final preview = await port.preview(requirements,
        {'email': 'pending@example.invalid', 'form_key': requirements.formKey});
    await expectLater(
        port.create(preview),
        throwsA(isA<SeatOrderPreparationPending>()
            .having((e) => e.orderId, 'committed order', 101)));
    final forged =
        seatOrderReceiptFixture('00000000-0000-4000-8000-000000000099');
    expect(
        () => SupabaseSeatOrderCommands.decodeEdgeResponse(
            {'code': 503, 'committed': forged}, ids.single),
        throwsFormatException);
    pending = false;
    expect((await port.recover(request))!.orderId, 101);
    expect(ids.toSet(), hasLength(1));
  });
  test(
      'actor switches suppress both successful previews and failed response details',
      () async {
    var principal = 'endpoint:actor';
    final completion = Completer<Object?>();
    final port = SupabaseSeatOrderCommands.withTransport(
        ClientCommandTransport((_, __) async => null,
            principalProvider: () => principal),
        readRpc: (_, __) => completion.future);
    final read = port.requirements(seatOrderRequestFixture());
    principal = 'endpoint:other';
    completion.completeError(StateError('Previous actor private failure'));
    await expectLater(
        read,
        throwsA(isA<StateError>()
            .having((e) => e.message, 'reason', 'COMMAND_PRINCIPAL_CHANGED')));
  });
  test(
      'legacy uncertain replacements require exact original input and never claim another UUID',
      () async {
    final storage = await LocalAppStorageFixture.open();
    addTearDown(storage.dispose);
    const payload = {
      'spotIds': [71],
      'inputData': {'email': 'old@example.invalid'}
    };
    expect(
        await ClientCommandIdentity.pendingLegacyOrderReplacement(payload,
            principalBinding: 'endpoint:actor'),
        isNull);
    final id = await ClientCommandIdentity.claimIntent(
        'ticket_order_replace', payload,
        principalBinding: 'endpoint:actor');
    expect(
        await ClientCommandIdentity.pendingLegacyOrderReplacement(payload,
            principalBinding: 'endpoint:actor'),
        id);
    await expectLater(
        ClientCommandIdentity.pendingLegacyOrderReplacement({
          'spotIds': [71],
          'inputData': {'email': 'different@example.invalid'}
        }, principalBinding: 'endpoint:actor'),
        throwsStateError);
    expect(
        await ClientCommandIdentity.pendingLegacyOrderReplacement(payload,
            principalBinding: 'endpoint:other'),
        isNull);
    expect(
        await ClientCommandIdentity.pendingLegacyOrderReplacement(payload,
            principalBinding: 'endpoint:actor'),
        id);
  });
}
