import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/news/news_commands.dart';
import 'package:fstapp/components/news/news_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('news update carries the optimistic aggregate version', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseNewsCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 4,
            'news': {
              'id': 8,
              'message': 'Updated',
              'created_at': '2026-08-03T10:00:00Z',
              'views': 0,
            },
          },
          'sync': {'replacements': <Object>[]},
        };
      },
      maxAttempts: 1,
    ));

    final result = await commands.update(
      7,
      NewsModel(
        id: 8,
        createdAt: DateTime.utc(2026, 8, 3, 10),
        message: 'Updated',
        createdBy: null,
        views: 0,
        aggregateVersion: 3,
      ),
    );

    expect(functionName, 'save_news_client_sync_v1');
    expect(parameters['p_expected_version'], 3);
    expect(result.version, 4);
  });

  test('news plus notification stays one typed publication command', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseNewsCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 1,
            'news': {
              'id': 9,
              'message': 'News',
              'created_at': '2026-08-03T10:00:00Z',
              'views': 0,
            },
            'notificationQueued': true,
          },
          'sync': {'replacements': <Object>[]},
        };
      },
      maxAttempts: 1,
    ));

    await commands.publish(
      occasionId: 7,
      addToNews: true,
      newsMessage: 'News',
      sendNotification: true,
      notificationHeading: 'Heading',
      notificationContent: 'Plain text',
      recipients: ['role:participant'],
    );

    expect(functionName, 'publish_news_client_sync_v1');
    expect(parameters['p_add_to_news'], isTrue);
    expect(parameters['p_send_notification'], isTrue);
    expect(parameters['p_recipients'], ['role:participant']);
  });
}
