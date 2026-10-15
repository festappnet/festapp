import 'package:test/test.dart';
import 'package:festapp_core/sync.dart';

void main() {
  group('client_command_response', () {
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
          'occurredAt': '2026-10-15T10:00:00Z',
        },
        'sync': {
          'replacements': [
            {'component': 'map_catalog', 'revision': 8, 'payload': {}},
          ],
        },
      });

      expect(response.status, 'conflict');
      expect(response.code, 409);
      expect(response.data['version'], 3);
      expect(response.replacements.single['component'], 'map_catalog');
    });

    test(
      'retains map views numeric conversion and deferred replacement validation',
      () {
        final data = <String, dynamic>{'value': 1};
        final replacement = <String, dynamic>{
          'component': null,
          'revision': 'later',
        };
        final response = ClientCommandResponse.from({
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-15T10:00:00Z',
          },
          'status': 'unchanged',
          'code': 200.9,
          'data': data,
          'sync': {
            'replacements': [replacement],
          },
        });
        data['value'] = 2;
        replacement['payload'] = 'changed';
        expect(response.code, 200);
        expect(response.data['value'], 2);
        expect(response.replacements.single['payload'], 'changed');
      },
    );
    test(
      'keeps null malformed envelope and non-map replacement failures synchronous',
      () {
        expect(() => ClientCommandResponse.from(null), throwsFormatException);
        expect(
          () => ClientCommandResponse.from({
            'mutation': {
              'commandId': '00000000-0000-4000-8000-000000000001',
              'receiptId': '00000000-0000-4000-8000-000000000001',
              'commitId': null,
              'replayed': false,
              'occurredAt': '2026-10-15T10:00:00Z',
            },
            'status': 'applied',
            'code': 200,
            'data': {},
            'sync': {
              'replacements': [null],
            },
          }),
          throwsA(isA<TypeError>()),
        );
      },
    );
    test('rejects a partial or unknown envelope', () {
      expect(
        () => ClientCommandResponse.from({
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-15T10:00:00Z',
          },
          'status': 'maybe',
          'code': 200,
          'data': {},
          'sync': {'replacements': []},
        }),
        throwsFormatException,
      );
    });
  });
}
