import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/saved_program_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('saved program command returns the complete authoritative set',
      () async {
    late Map<String, dynamic> parameters;
    final commands = SupabaseSavedProgramCommands.withTransport(
      ClientCommandTransport((name, params) async {
        expect(name, 'set_saved_program_client_sync_v1');
        parameters = params;
        return {
          'status': 'unchanged',
          'code': 200,
          'data': {
            'saved': [4, 9, 21],
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
      643,
    );

    final saved = await commands.update([21, 9, 9], SavedProgramMode.join);

    expect(parameters['p_occasion'], 643);
    expect(parameters['p_event_ids'], [9, 21]);
    expect(parameters['p_mode'], 'join');
    expect(parameters['p_command_id'], isA<String>());
    expect(saved, [4, 9, 21]);
  });

  test('accepts authoritative program and live cache replacements', () async {
    final commands = SupabaseSavedProgramCommands.withTransport(
      ClientCommandTransport((_, __) async {
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'saved': [9, 21],
          },
          'sync': {
            'replacements': [
              {
                'component': 'live_public',
                'revision': 12,
                'payload': {'events': <Object>[]},
              },
              {
                'component': 'private_program',
                'revision': 7,
                'payload': {
                  'signedIn': <int>[],
                  'saved': [9, 21],
                },
              },
            ],
          },
        };
      }, maxAttempts: 1),
      643,
    );

    expect(
      await commands.update([21], SavedProgramMode.join),
      [9, 21],
    );
  });
}
