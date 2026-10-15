import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/form_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('form lifecycle and blueprint saves use dedicated command RPCs',
      () async {
    final calls = <String>[];
    final commands = SupabaseFormCommands.withTransport(
      ClientCommandTransport((name, params) async {
        calls.add(name);
        return {
          'status': 'applied',
          'code': 200,
          'data': {'code': 200, 'formId': 8},
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-07T10:00:00Z'
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.create(
      occasionLink: 'festival',
      link: 'registration',
      title: 'Registration',
    );
    expect(
      await commands.duplicate(
        sourceFormId: 3,
        targetOccasionLink: 'next-festival',
      ),
      8,
    );
    await commands.delete(8);
    await commands.save({'id': 1, 'occasion': 7});
    await commands.saveBlueprint({'id': 2, 'occasion': 7});
    expect(calls, [
      'create_form_client_sync_v1',
      'duplicate_form_to_occasion_client_sync_v1',
      'delete_form_client_sync_v1',
      'update_form_client_sync_v1',
      'update_blueprint_client_sync_v1',
    ]);
  });
}
