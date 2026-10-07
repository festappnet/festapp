import 'dart:convert';
import 'dart:io';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_commands.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('occasion save carries its loaded aggregate version', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 5,
            'occasion': {
              'id': 7,
              'title': 'Fest',
              'is_open': true,
              'is_hidden': false,
              'is_promoted': false,
              'aggregate_version': 5,
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
      }, maxAttempts: 1),
    );

    final saved = await commands.save(OccasionModel(
      id: 7,
      title: 'Fest',
      isOpen: true,
      isHidden: false,
      isPromoted: false,
      aggregateVersion: 4,
    ));

    expect(functionName, 'save_occasion_client_sync_v1');
    expect(parameters['p_expected_version'], 4);
    expect(saved.aggregateVersion, 5);
  });

  test(
      'occasion command carries an explicit layout envelope without persisting it',
      () async {
    final layout = jsonDecode(File('test/fixtures/ticket_layout/layouts.json')
        .readAsStringSync())['valid'][0] as Map<String, dynamic>;
    final ticket = TicketFeature.fromJson(
        {'code': 'ticket', 'is_enabled': true, 'layout': layout});
    ticket.layout!['templates']['named']['elements'][0]['style']['color'] =
        '17365D';
    Map<String, dynamic>? config;
    final commands = SupabaseOccasionCommands.withTransport(
        ClientCommandTransport((name, params) async {
      config =
          jsonDecode(jsonEncode(params['p_config'])) as Map<String, dynamic>;
      return {
        'status': 'applied',
        'code': 200,
        'data': {
          'occasion': {
            'id': 7,
            'is_open': true,
            'is_hidden': false,
            'is_promoted': false,
            'features': config!['features'],
            'aggregate_version': 2
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
    final saved = await commands.save(OccasionModel(
        id: 7,
        isOpen: true,
        isHidden: false,
        isPromoted: false,
        features: [ticket]));
    expect(config!['ticket_layout_change'], ticket.layoutChange);
    expect(
        (config!['features'] as List).first.containsKey('ticket_layout_change'),
        isFalse);
    expect(
        saved.features.whereType<TicketFeature>().single.layoutChange, isNull);
  });

  test('occasion lifecycle commands use dedicated receipted RPCs', () async {
    final calls = <String>[];
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        calls.add(name);
        return {
          'status': 'applied',
          'code': 200,
          'data': name.startsWith('duplicate')
              ? {'occasionId': 12}
              : <String, dynamic>{},
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

    expect(await commands.duplicate(7), 12);
    await commands.delete(12);
    expect(calls, [
      'duplicate_occasion_client_sync_v1',
      'delete_occasion_client_sync_v1',
    ]);
  });

  test('occasion create uses the unit-scoped canonical command', () async {
    late String functionName;
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'occasion': {
              'id': 12,
              'title': 'Fest',
              'is_open': true,
              'is_hidden': false,
              'is_promoted': false,
              'aggregate_version': 1,
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
      }, maxAttempts: 1),
    );
    final created = await commands.create(OccasionModel(
      title: 'Fest',
      isOpen: true,
      isHidden: false,
      isPromoted: false,
    ));
    expect(functionName, 'create_occasion_client_sync_v1');
    expect(created.id, 12);
  });

  test('service delete uses the canonical profile/config command', () async {
    late String functionName;
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'message': 'deleted'},
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
    final result = await commands.deleteService(7, 'food', 'lunch', true);
    expect(functionName, 'delete_service_item_client_sync_v1');
    expect(result['code'], 200);
  });

  test('service and game config use typed canonical commands', () async {
    final calls = <String>[];
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        calls.add(name);
        return {
          'status': 'applied',
          'code': 200,
          'data': <String, dynamic>{},
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
    await commands.createService(7, 'food', 'lunch', 'Lunch', null);
    await commands.updateService(7, 'food', 'lunch', 'Dinner', null);
    await commands.updateGameSettings(7, null, null);
    expect(calls, [
      'create_service_item_client_sync_v1',
      'update_service_item_client_sync_v1',
      'game_update_settings_client_sync_v1',
    ]);
  });
}
