import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:fstapp/components/groups/group_commands.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test(
      'editing during create retains new fields and reconciles IDs for the next save',
      () async {
    final release = Completer<void>();
    final calls = <Map<String, dynamic>>[];
    final commands = SupabaseGroupCommands.withTransport(
        ClientCommandTransport((name, parameters) async {
      calls.add(parameters);
      if (calls.length == 1) await release.future;
      final group = parameters['p_group'] as Map;
      return {
        'status': 'applied',
        'code': 200,
        'mutation': {
          'commandId': parameters['p_command_id'],
          'receiptId': parameters['p_command_id'],
          'commitId': '00000000-0000-4000-8000-000000000001',
          'replayed': false,
          'occurredAt': '2026-10-07T10:00:00Z'
        },
        'sync': {'replacements': []},
        'data': {
          'version': calls.length,
          'group': {
            'id': 42,
            'title': group['title'],
            'place': 43,
            'participants': [],
            'placeData': {
              'id': 43,
              'title': (group['privatePlace'] as Map)['title'],
              'type': 'group',
              'is_hidden': true,
              'aggregate_version': calls.length
            }
          }
        }
      };
    }));
    final place =
        PlaceModel(title: 'Original place', type: 'group', isHidden: true);
    final model = UserGroupInfoModel(
        id: null, title: 'Original', place: place, participants: {});
    final first = DbGroups.saveWithCommands(commands, 7, model);
    model.title = 'New edit';
    place.title = 'New place edit';
    release.complete();
    await first;
    expect(model.id, 42);
    expect(model.aggregateVersion, 1);
    expect(model.title, 'New edit');
    expect(model.place!.title, 'New place edit');
    expect(model.place!.id, 43);
    expect(model.place!.aggregateVersion, 1);
    await DbGroups.saveWithCommands(commands, 7, model);
    expect((calls.last['p_group'] as Map)['id'], 42);
    expect(((calls.last['p_group'] as Map)['privatePlace'] as Map)['id'], 43);
    expect(calls.last['p_expected_version'], 1);
    expect(model.aggregateVersion, 2);
  });
  test(
      'lost create response plus changed form replays creation before the new save',
      () async {
    final calls = <Map<String, dynamic>>[];
    final commits = <String, Map<String, dynamic>>{};
    var creations = 0;
    final commands = SupabaseGroupCommands.withTransport(
        ClientCommandTransport((name, p) async {
      calls.add(p);
      final id = p['p_command_id'] as String;
      if (commits.containsKey(id)) return commits[id]!;
      final dto = p['p_group'] as Map;
      if (dto['id'] == null) creations++;
      final r = groupResponse(p, version: commits.length + 1);
      commits[id] = r;
      if (calls.length == 1)
        throw TimeoutException('response lost after commit');
      return r;
    }, maxAttempts: 1));
    final model =
        UserGroupInfoModel(id: null, title: 'Before', participants: {});
    await expectLater(DbGroups.saveWithCommands(commands, 7, model),
        throwsA(isA<TimeoutException>()));
    model.title = 'Changed intent';
    await DbGroups.saveWithCommands(commands, 7, model);
    expect(creations, 1);
    expect(calls[1]['p_command_id'], calls[0]['p_command_id']);
    expect(calls[2]['p_command_id'], isNot(calls[0]['p_command_id']));
    expect((calls[2]['p_group'] as Map)['id'], 42);
    expect((calls[2]['p_group'] as Map)['title'], 'Changed intent');
    expect(calls[2]['p_expected_version'], 1);
    expect(model.id, 42);
    expect(model.aggregateVersion, 2);
    expect(model.title, 'Changed intent');
  });
  test('pending creation cannot replay after actor change', () async {
    var actor = 'first';
    var attempts = 0;
    final commands = SupabaseGroupCommands.withTransport(
        ClientCommandTransport((name, p) async {
          attempts++;
          throw TimeoutException('unknown commit');
        }, maxAttempts: 1),
        actorId: () => actor);
    final model =
        UserGroupInfoModel(id: null, title: 'Before', participants: {});
    await expectLater(
        commands.save(7, model), throwsA(isA<TimeoutException>()));
    actor = 'second';
    await expectLater(commands.save(7, model), throwsA(isA<StateError>()));
    expect(attempts, 1);
  });
  test('two new rows with identical data are distinct creation intents',
      () async {
    final ids = <String>[];
    final commands = SupabaseGroupCommands.withTransport(
        ClientCommandTransport((name, p) async {
      ids.add(p['p_command_id'] as String);
      throw TimeoutException('unknown commit');
    }, maxAttempts: 1));
    for (var i = 0; i < 2; i++) {
      await expectLater(
          commands.save(
              7, UserGroupInfoModel(id: null, title: 'Same', participants: {})),
          throwsA(isA<TimeoutException>()));
    }
    expect(ids.toSet().length, 2);
  });
  test(
      'authorization failure after an ambiguous commit keeps the original creation identity',
      () async {
    final ids = <String>[];
    final commands = SupabaseGroupCommands.withTransport(
        ClientCommandTransport((name, p) async {
      ids.add(p['p_command_id'] as String);
      if (ids.length == 1) throw TimeoutException('unknown commit');
      if (ids.length == 2)
        throw const PostgrestException(
            message: 'permission revoked', code: '42501');
      return groupResponse(p, version: 1);
    }, maxAttempts: 1));
    final model =
        UserGroupInfoModel(id: null, title: 'Retained', participants: {});
    await expectLater(
        commands.save(7, model), throwsA(isA<TimeoutException>()));
    await expectLater(
        commands.save(7, model), throwsA(isA<PostgrestException>()));
    final result = await commands.save(7, model);
    expect(result.group!.id, 42);
    expect(ids.toSet().length, 1);
  });
}

Map<String, dynamic> groupResponse(Map<String, dynamic> parameters,
    {required int version}) {
  final dto = parameters['p_group'] as Map;
  return {
    'status': 'applied',
    'code': 200,
    'mutation': {
      'commandId': parameters['p_command_id'],
      'receiptId': parameters['p_command_id'],
      'commitId': '00000000-0000-4000-8000-000000000001',
      'replayed': false,
      'occurredAt': '2026-10-07T10:00:00Z'
    },
    'sync': {'replacements': []},
    'data': {
      'version': version,
      'group': {'id': 42, 'title': dto['title'], 'participants': []}
    }
  };
}
