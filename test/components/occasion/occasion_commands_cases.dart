import '../../support/fixtures/localization_log_fixture.dart';
import '../../support/fixtures/client_command_response_fixture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_commands.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test(
    'settings save excludes unrelated metadata and read-only projections',
    () {
      final occasion = OccasionModel(
        id: 7,
        isOpen: true, isHidden: false, isPromoted: false,
        aggregateVersion: 4,
        data: {
          'reply_to': 'reply@example.invalid',
          'timezone': 'Europe/Prague',
          'image': 'https://img.festapp.net/images/owned.webp',
          'game': {'start': '2030-01-01T00:00:00Z'},
          'client_sync_v1': true,
          'opaque_owner_data': true,
        },
      );
      final saved = occasion.toSettingsSaveJson();
      expect(saved.containsKey('data'), isFalse);
      expect(saved.containsKey('stats'), isFalse);
      expect(saved.containsKey('sale_forms'), isFalse);
      expect(saved['settings'], {
        'reply_to': 'reply@example.invalid',
        'timezone': 'Europe/Prague',
        'place_name': null,
        'image': 'https://img.festapp.net/images/owned.webp',
      });
      // Provisioning keeps its separate complete configuration.
      expect(occasion.toSaveJson()['data'], occasion.data);
    },
  );

  test(
    'game command sends its original aggregate version and adopts snapshot',
    () async {
      final commands = SupabaseOccasionCommands.withTransport(
        ClientCommandTransport((name, params) async {
          expect(name, 'game_update_settings_client_sync_v1');
          expect(params['p_expected_version'], 6);
          return commandResponseFixture(
            params['p_command_id'] as String,
            data: {
              'version': 7,
              'game': {'start': null, 'end': null},
            },
          );
        }, maxAttempts: 1),
      );
      final result = await commands.updateGameSettings(
        7,
        null,
        null,
        expectedVersion: 6,
      );
      expect(result['version'], 7);
      expect(result['game'], {'start': null, 'end': null});
    },
  );

  test(
    'layout save sends only the narrow change and original revision',
    () async {
      late Map<String, dynamic> sent;
      final commands = SupabaseOccasionCommands.withTransport(
        ClientCommandTransport((name, params) async {
          expect(name, 'save_occasion_client_sync_v1');
          sent = params;
          return {
            ...commandResponseFixture(params['p_command_id']),
            'status': 'applied',
            'code': 200,
            'data': {
              'occasion': {
                'id': 7,
                'is_open': false,
                'is_hidden': false,
                'is_promoted': false,
                'aggregate_version': 8,
              },
            },
            'sync': {'replacements': <Object>[]},
          };
        }),
      );
      final change = {
        'expected': null,
        'next': {'schemaVersion': 3},
        'appearance': {'ticket_type': 'wide'},
      };
      final saved = await commands.saveTicketLayout(
        7,
        7,
        change,
        commandId: '00000000-0000-4000-8000-000000000001',
      );
      expect(sent['p_config'], {'id': 7, 'ticket_layout_change': change});
      expect(sent['p_expected_version'], 7);
      expect(saved.aggregateVersion, 8);
      expect(sent['p_command_id'], '00000000-0000-4000-8000-000000000001');
    },
  );

  test('occasion save carries its loaded aggregate version', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          ...commandResponseFixture(params['p_command_id']),
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
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    final saved = await commands.save(
      OccasionModel(
        id: 7,
        title: 'Fest',
        isOpen: true,
        isHidden: false,
        isPromoted: false,
        aggregateVersion: 4,
      ),
    );

    expect(functionName, 'save_occasion_client_sync_v1');
    expect(parameters['p_expected_version'], 4);
    expect(saved.aggregateVersion, 5);
  });

  test('occasion command carries an explicit layout envelope without persisting it', () async {
    final layout =
        jsonDecode(
              File('test/fixtures/ticket_layout/layouts.json')
                  .readAsStringSync(),
            )['valid'][0]
            as Map<String, dynamic>;
    final ticket = TicketFeature.fromJson({
      'code': 'ticket',
      'is_enabled': true,
      'layout': layout,
    });
    ticket.layout!['templates']['named']['elements'][0]['style']['color'] =
        '17365D';
    Map<String, dynamic>? config;
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        config =
            jsonDecode(jsonEncode(params['p_config'])) as Map<String, dynamic>;
        return {
          ...commandResponseFixture(params['p_command_id']),
          'status': 'applied',
          'code': 200,
          'data': {
            'occasion': {
              'id': 7,
              'is_open': true,
              'is_hidden': false,
              'is_promoted': false,
              'features': config!['features'],
              'aggregate_version': 2,
            },
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    final saved = await commands.save(
      OccasionModel(
        id: 7,
        isOpen: true,
        isHidden: false,
        isPromoted: false,
        features: [ticket],
      ),
    );
    expect(config!['ticket_layout_change'], ticket.layoutChange);
    expect(
      (config!['features'] as List).first.containsKey('ticket_layout_change'),
      isFalse,
    );
    expect(
      saved.features.whereType<TicketFeature>().single.layoutChange,
      isNull,
    );
  });

  test('occasion lifecycle commands use dedicated receipted RPCs', () async {
    final calls = <String>[];
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        calls.add(name);
        return {
          ...commandResponseFixture(params['p_command_id']),
          'status': 'applied',
          'code': 200,
          'data': name.startsWith('duplicate')
              ? {'occasionId': 12}
              : <String, dynamic>{},
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

  test('occasion copy sends the selected target unit', () async {
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        expect(name, 'duplicate_occasion_client_sync_v1');
        expect(params['p_occasion'], 7);
        expect(params['p_target_unit'], 23);
        expect(params['p_locale'], 'cs');
        return {
          ...commandResponseFixture(params['p_command_id']),
          'status': 'applied',
          'code': 200,
          'data': {'occasionId': 12},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    expect(await commands.duplicate(7, targetUnitId: 23, locale: 'cs'), 12);
  });

  test('occasion create uses the unit-scoped canonical command', () async {
    late String functionName;
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          ...commandResponseFixture(params['p_command_id']),
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
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    final created = await commands.create(
      OccasionModel(
        title: 'Fest',
        isOpen: true,
        isHidden: false,
        isPromoted: false,
      ),
    );
    expect(functionName, 'create_occasion_client_sync_v1');
    expect(created.id, 12);
  });

  test('service delete uses the canonical profile/config command', () async {
    late String functionName;
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          ...commandResponseFixture(params['p_command_id']),
          'status': 'applied',
          'code': 200,
          'data': {'message': 'deleted'},
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
          ...commandResponseFixture(params['p_command_id']),
          'status': 'applied',
          'code': 200,
          'data': <String, dynamic>{},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.createService(7, 'food', 'lunch', 'Lunch', null);
    await commands.updateService(7, 'food', 'lunch', 'Dinner', null);
    await commands.updateGameSettings(7, null, null, expectedVersion: 0);
    expect(calls, [
      'create_service_item_client_sync_v1',
      'update_service_item_client_sync_v1',
      'game_update_settings_client_sync_v1',
    ]);
  });
}
