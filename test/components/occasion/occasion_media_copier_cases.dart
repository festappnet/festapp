import '../../support/fixtures/local_app_storage_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_commands.dart';
import 'package:fstapp/components/occasion/occasion_duplication.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

import '../../support/fixtures/client_command_response_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'confirmed copy and Worker completion share the exact durable intent',
    () async {
      const command = '00000000-0000-4000-8000-000000000021';
      final calls = <String>[];
      final commands = SupabaseOccasionCommands.withTransport(
        ClientCommandTransport((name, params) async {
          expect(name, 'start_occasion_lifecycle');
          expect(params['p_action'], 'copy');
          expect(params['p_target_unit'], 23);
          expect(params['p_locale'], 'cs');
          expect(params['p_command_id'], command);
          calls.add('sql');
          return commandResponseFixture(command, data: {'occasionId': 42});
        }),
      );
      final duplicator = OccasionDuplicator(
        commands: commands,
        completeMedia: (intent) async {
          expect(intent, command);
          calls.add('worker');
        },
      );
      final result = await duplicator.duplicate(
        7,
        targetUnitId: 23,
        locale: 'cs',
        commandId: command,
      );
      expect(result, (occasionId: 42, mediaCopied: true));
      expect(calls, ['sql', 'worker']);
    },
  );
  test(
    'a lost media response retains the created ID and retries the same job',
    () async {
      const command = '00000000-0000-4000-8000-000000000022';
      final accepted = <String>{};
      var attempts = 0;
      final commands = SupabaseOccasionCommands.withTransport(
        ClientCommandTransport((name, params) async {
          accepted.add(params['p_command_id']);
          return commandResponseFixture(command, data: {'occasionId': 42});
        }),
      );
      final duplicator = OccasionDuplicator(
        commands: commands,
        completeMedia: (intent) async {
          expect(intent, command);
          if (attempts++ == 0) throw StateError('lost acknowledgement');
        },
      );
      expect(await duplicator.duplicate(7, commandId: command), (
        occasionId: 42,
        mediaCopied: false,
      ));
      expect(await duplicator.duplicate(7, commandId: command), (
        occasionId: 42,
        mediaCopied: true,
      ));
      expect(accepted, {command});
    },
  );
  test('an unconfirmed SQL copy never starts external media work', () async {
    var mediaCalls = 0;
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport(
        (name, params) async => {
          'code': 200,
          'data': {'occasionId': 42},
        },
      ),
    );
    final duplicator = OccasionDuplicator(
      commands: commands,
      completeMedia: (_) async {
        mediaCalls++;
      },
    );
    await expectLater(duplicator.duplicate(7), throwsA(isA<FormatException>()));
    expect(mediaCalls, 0);
  });
  test('normal copy recovery survives a coordinator restart and clears only after media completion', () async {
    final storage = await LocalAppStorageFixture.open();
    addTearDown(storage.dispose);
    final accepted = <String>[];
    var attempts = 0;
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        final id = params['p_command_id'] as String;
        accepted.add(id);
        return commandResponseFixture(id, data: {'occasionId': 42});
      }),
    );
    OccasionDuplicator coordinator() => OccasionDuplicator(
      commands: commands,
      principalBinding: () => 'fixture:actor',
      completeMedia: (_) async {
        if (attempts++ == 0) throw StateError('lost response');
      },
    );
    expect(
      (await coordinator().duplicate(7, targetUnitId: 23)).mediaCopied,
      false,
    );
    expect(
      (await coordinator().duplicate(7, targetUnitId: 23)).mediaCopied,
      true,
    );
    expect(accepted[0], accepted[1]);
    await coordinator().duplicate(7, targetUnitId: 23);
    expect(accepted[2], isNot(accepted[1]));
  });
  test('identity change while opening a durable media intent refuses SQL and Worker dispatch', () async {
    final storage = await LocalAppStorageFixture.open();
    addTearDown(storage.dispose);
    var identityReads = 0, sqlCalls = 0, mediaCalls = 0;
    final commands = SupabaseOccasionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        sqlCalls++;
        return commandResponseFixture(
          params['p_command_id'],
          data: {'occasionId': 42},
        );
      }),
    );
    final coordinator = OccasionDuplicator(
      commands: commands,
      principalBinding: () =>
          identityReads++ == 0 ? 'fixture:actor-A' : 'fixture:actor-B',
      completeMedia: (_) async {
        mediaCalls++;
      },
    );
    await expectLater(
      coordinator.duplicate(7, targetUnitId: 23),
      throwsA(isA<StateError>()),
    );
    expect(sqlCalls, 0);
    expect(mediaCalls, 0);
  });
}
