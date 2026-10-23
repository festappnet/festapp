import 'dart:async';
import 'package:festapp_core/eshop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/supabase_product_schedule_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test(
      'new and existing target use one receipt RPC, preserving null vs false and retry identity',
      () async {
    final calls = <Map<String, dynamic>>[];
    var lose = true;
    final commands = SupabaseProductScheduleCommands.withTransport(
        ClientCommandTransport((name, parameters) async {
      expect(name, 'manage_product_schedule');
      calls.add(parameters);
      if (lose) {
        lose = false;
        throw TimeoutException('lost response');
      }
      return {
        'code': 200,
        'status': 'applied',
        'mutation': {
          'commandId': parameters['p_command_id'],
          'receiptId': parameters['p_command_id'],
          'commitId': null,
          'replayed': false,
          'occurredAt': '2026-10-23T10:00:00Z'
        },
        'data': <String, dynamic>{},
        'sync': {'replacements': <Object>[]},
      };
    }),
        productScope: () =>
            {'p_occasion': 7, 'p_organization': 3, 'p_unit': 2});
    final time = DateTime.utc(2027);
    await commands.saveTarget(
        ProductPriceWave(time: time), 9, 125.50, false, null, null);
    expect(calls.length, 2);
    expect(calls[0], calls[1]);
    expect(calls[0]['p_payload'], {
      'product_id': 9,
      'change_time': time.toIso8601String(),
      'price': '125.5',
      'is_hidden': false,
      'expected_price_revision': null,
      'expected_visibility_revision': null
    });
    await commands.saveTarget(
        ProductPriceWave(id: 12, revision: 4, time: time), 9, null, null, 2, 3);
    expect(calls.last['p_action'], 'save_target');
    expect(calls.last['p_payload'], {
      'product_id': 9,
      'wave_id': 12,
      'expected_wave_revision': 4,
      'price': null,
      'is_hidden': null,
      'expected_price_revision': 2,
      'expected_visibility_revision': 3
    });
  });
}
