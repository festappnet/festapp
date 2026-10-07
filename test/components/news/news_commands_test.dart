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
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-07T10:00:00Z'
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

  for (final serverMessage in ['Original', 'Changed elsewhere']) {
    test(
        'unversioned edit binds a version only to matching snapshot: $serverMessage',
        () async {
      final versions = <Object?>[];
      final ids = <Object?>[];
      final commands = SupabaseNewsCommands.withTransport(
          ClientCommandTransport((_, parameters) async {
        versions.add(parameters['p_expected_version']);
        ids.add(parameters['p_command_id']);
        return {
          'status': versions.length == 1 ? 'conflict' : 'applied',
          'code': versions.length == 1 ? 409 : 200,
          'data': {
            'version': versions.length == 1 ? 5 : 6,
            'news': {
              'id': 8,
              'message': versions.length == 1 ? serverMessage : 'Edited',
              'created_at': '2026-08-03T10:00:00Z'
            }
          },
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-07T10:00:00Z'
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1));
      final result = await commands.update(
          7,
          NewsModel(
              id: 8,
              createdAt: DateTime.utc(2026),
              message: 'Edited',
              createdBy: null,
              views: 0),
          originalMessage: 'Original');
      final matches = serverMessage == 'Original';
      expect(versions, matches ? [0, 5] : [0]);
      expect(result.status,
          matches ? NewsCommandStatus.applied : NewsCommandStatus.conflict);
      expect(ids.toSet().length, versions.length);
    });
  }
  test('snapshot version binding stops after another concurrent change',
      () async {
    var attempts = 0;
    final commands = SupabaseNewsCommands.withTransport(
        ClientCommandTransport((_, parameters) async {
      attempts++;
      return {
        'status': 'conflict',
        'code': 409,
        'data': {
          'version': attempts + 5,
          'news': {
            'id': 8,
            'message': 'Original',
            'created_at': '2026-08-03T10:00:00Z'
          }
        },
        'mutation': {
          'commandId': '00000000-0000-4000-8000-000000000001',
          'receiptId': '00000000-0000-4000-8000-000000000001',
          'commitId': null,
          'replayed': false,
          'occurredAt': '2026-10-07T10:00:00Z'
        },
        'sync': {'replacements': <Object>[]}
      };
    }, maxAttempts: 1));
    final result = await commands.update(
        7,
        NewsModel(
            id: 8,
            createdAt: DateTime.utc(2026),
            message: 'Edited',
            createdBy: null,
            views: 0),
        originalMessage: 'Original');
    expect(attempts, 2);
    expect(result.status, NewsCommandStatus.conflict);
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
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-07T10:00:00Z'
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
