import 'dart:async';
import '../../support/fixtures/client_command_response_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/order_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('repair timeout reuses identity and immutable preconditions', () async {
    final ids = <String>[];
    final commands = SupabaseOrderCommands.withTransport(
        ClientCommandTransport((name, args) async {
      expect(name, 'repair_order_email_client_sync_v1');
      expect(args['p_expected_payment_version'], 3);
      expect(args['p_expected_state'], 'ordered');
      expect(args['p_source_message'], 'source');
      ids.add(args['p_command_id']);
      if (ids.length == 1) throw TimeoutException('response lost after commit');
      return commandResponseFixture(args['p_command_id']);
    }));
    await commands.repairEmail(
        orderId: 5,
        expectedEmail: 'old@example.invalid',
        expectedState: 'ordered',
        expectedPaymentVersion: 3,
        expectedPaymentFingerprint: 'facts',
        email: 'fixed@example.invalid',
        sourceMessageId: 'source',
        resend: true);
    expect(ids.length, 2);
    expect(ids.toSet().length, 1);
  });

  test('explicit repair command identity is preserved', () async {
    const id = '00000000-0000-4000-8000-000000000007';
    final commands = SupabaseOrderCommands.withTransport(
        ClientCommandTransport((name, args) async {
      expect(args['p_command_id'], id);
      return commandResponseFixture(id);
    }));
    await commands.repairEmail(
        orderId: 5,
        expectedEmail: 'old@example.invalid',
        expectedState: 'ordered',
        expectedPaymentVersion: 1,
        expectedPaymentFingerprint: 'facts',
        email: 'saved@example.invalid',
        resend: false,
        commandId: id);
  });

  test('order delete uses its dedicated command RPC', () async {
    late String functionName;
    late Map<String, dynamic> sent;
    final commands = SupabaseOrderCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        sent = params;
        return {
          'mutation': commandResponseFixture(
              params['p_command_id'] as String)['mutation'],
          'status': 'applied',
          'code': 200,
          'data': {'orderId': 5},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.delete(5);
    expect(functionName, 'delete_order_client_sync_v1');
    expect(sent['p_order'], 5);
    expect(sent.containsKey('order_symbol'), isFalse);
  });

  test('order cancellation uses its dedicated command RPC', () async {
    late String functionName;
    late Map<String, dynamic> sent;
    final commands = SupabaseOrderCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        sent = params;
        return {
          'mutation': commandResponseFixture(
              params['p_command_id'] as String)['mutation'],
          'status': 'applied',
          'code': 200,
          'data': {'orderId': 5},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.cancel(5);
    expect(functionName, 'storno_order_client_sync_v1');
    expect(sent['p_order'], 5);
    expect(sent.containsKey('order_symbol'), isFalse);
  });
}
