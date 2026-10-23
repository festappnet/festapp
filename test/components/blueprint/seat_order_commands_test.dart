import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/blueprint_seat_order_preview.dart';
import 'package:fstapp/components/eshop/seat_order_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import '../../support/fixtures/blueprint_order_preview_fixture.dart';
import '../../support/fixtures/local_app_storage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
