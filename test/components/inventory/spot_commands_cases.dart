import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/inventory/spot_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('spot assignments use their dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseSpotCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'changedCount': 1},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.updateAssignments([
      {'old_spot_id': 1, 'new_spot_id': 2, 'resource_id': 3},
    ]);
    expect(functionName, 'update_spot_assignments_client_sync_v1');
  });
}
