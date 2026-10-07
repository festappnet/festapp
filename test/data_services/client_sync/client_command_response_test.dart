import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';

void main() {
  test('parses the standard mutation envelope once for domain adapters', () {
    final response = ClientCommandResponse.from({
      'status': 'conflict',
      'code': 409,
      'data': {'version': 3},
      'mutation': {
        'commandId': '00000000-0000-4000-8000-000000000001',
        'receiptId': '00000000-0000-4000-8000-000000000001',
        'commitId': null,
        'replayed': false,
        'occurredAt': '2026-10-07T10:00:00Z'
      },
      'sync': {
        'replacements': [
          {'component': 'map_catalog', 'revision': 8, 'payload': {}}
        ],
      },
    });

    expect(response.status, 'conflict');
    expect(response.code, 409);
    expect(response.data['version'], 3);
    expect(response.replacements.single['component'], 'map_catalog');
  });

  test('rejects a partial or unknown envelope', () {
    expect(
      () => ClientCommandResponse.from({
        'status': 'maybe',
        'code': 200,
        'data': {},
        'sync': {'replacements': []},
      }),
      throwsFormatException,
    );
  });
}
