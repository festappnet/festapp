import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/event_feedback/event_feedback_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('anonymous feedback command carries stable client identity', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseEventFeedbackCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'feedback': {
              'id': 1,
              'event': 8,
              'rating': 'happy',
              'note': null,
            },
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    await commands.submit(
      occasionId: 3,
      eventId: 8,
      rating: 'happy',
      note: null,
      anonymousClientId: '10000000-0000-0000-0000-000000000001',
    );

    expect(functionName, 'submit_event_feedback_client_sync_v1');
    expect(parameters['p_occasion'], 3);
    expect(parameters['p_client_id'], '10000000-0000-0000-0000-000000000001');
    expect(parameters['p_command_id'], isNotNull);
  });

  test('admin delete targets one feedback row through the sync command',
      () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseEventFeedbackCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'deleted': true},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    await commands.deleteForEdit(occasionId: 7, feedbackId: 41);

    expect(functionName, 'delete_event_feedback_for_edit_client_sync_v1');
    expect(parameters['p_occasion'], 7);
    expect(parameters['p_feedback'], 41);
    expect(parameters['p_command_id'], isNotNull);
  });
}
