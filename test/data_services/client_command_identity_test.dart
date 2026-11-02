import 'package:fstapp/components/eshop/order_commands.dart';

import '../support/fixtures/client_command_response_fixture.dart';

import 'dart:convert';

import 'package:fstapp/components/forms/supabase_form_commands.dart';

import 'dart:async';

import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sembast/sembast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('contact recovery after reload reuses the committed request and clears its durable intent', () async {
    final directory = await Directory.systemTemp.createTemp(
      'festapp-contact-recovery-',
    );
    final provider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Documents(directory.path);
    addTearDown(() async {
      await StorageHelper.closeDatabase('default.db');
      PathProviderPlatform.instance = provider;
      await directory.delete(recursive: true);
    });
    String? committedId;
    Map<String, dynamic>? original;
    var attempts = 0;
    Future<Object?> rpc(String name, Map<String, dynamic> args) async {
      expect(name, 'repair_order_email_client_sync_v1');
      attempts++;
      committedId ??= args['p_command_id'] as String;
      original ??= Map.from(args);
      expect(args, original);
      if (attempts == 1)
        throw TimeoutException('Response lost after the commit');
      return {
        ...commandResponseFixture(committedId!),
        'data': {'sendingRequested': false},
      };
    }

    final commands = SupabaseOrderCommands.withTransport(
      ClientCommandTransport(
        rpc,
        maxAttempts: 1,
        principalBinding: 'http://local:actor',
      ),
    );
    await expectLater(
      commands.repairEmail(
        orderId: 5,
        expectedEmail: 'old@example.invalid',
        expectedState: 'paid',
        expectedPaymentVersion: 1,
        expectedPaymentFingerprint: 'original-payment-facts',
        email: 'new@example.invalid',
        resend: false,
      ),
      throwsA(isA<TimeoutException>()),
    );
    await StorageHelper.closeDatabase('default.db');
    final reopened = SupabaseOrderCommands.withTransport(
      ClientCommandTransport(
        rpc,
        maxAttempts: 1,
        principalBinding: 'http://local:actor',
      ),
    );
    final pending = await reopened.pendingContact(5);
    expect(pending, isNotNull);
    expect(pending!.commandId, committedId);
    final recovered = await reopened.recoverContact(pending);
    expect(recovered['code'], 200);
    expect(await reopened.pendingContact(5), isNull);
    expect(attempts, 2);
  });
  test(
    'durable concurrent claims bind one actor and survive reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'festapp-reference-intent-',
      );
      final provider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Documents(directory.path);
      addTearDown(() async {
        await StorageHelper.closeDatabase('default.db');
        PathProviderPlatform.instance = provider;
        await directory.delete(recursive: true);
      });
      final clients = await Future.wait(
        List.generate(12, (_) => ClientCommandIdentity.clientId()),
      );
      expect(clients.toSet(), hasLength(1));
      const payload = {
        'form': 'reference-fixture',
        'email': 'private@example.invalid',
        'ticket': [
          {'b': 2, 'a': 1},
        ],
      };
      final claims = await Future.wait(
        List.generate(
          12,
          (_) => ClientCommandIdentity.claimIntent(
            'ticket_order',
            payload,
            principalBinding: 'endpoint:user-one',
          ),
        ),
      );
      expect(claims.toSet(), hasLength(1));
      await StorageHelper.closeDatabase('default.db');
      expect(await ClientCommandIdentity.clientId(), clients.first);
      final reordered = {
        'ticket': [
          {'a': 1, 'b': 2},
        ],
        'email': 'private@example.invalid',
        'form': 'reference-fixture',
      };
      expect(
        await ClientCommandIdentity.claimIntent(
          'ticket_order',
          reordered,
          principalBinding: 'endpoint:user-one',
        ),
        claims.first,
      );
      await expectLater(
        ClientCommandIdentity.claimIntent(
          'ticket_order',
          payload,
          principalBinding: 'endpoint:user-two',
        ),
        throwsStateError,
      );
      final db = await StorageHelper.openDatabase();
      expect(
        jsonEncode(
          (await StoreRef.main().find(db)).map((r) => r.value).toList(),
        ),
        isNot(contains('private@example.invalid')),
      );
      expect(
        await ClientCommandIdentity.completeIntent(
          'ticket_order',
          reordered,
          commandId: 'delayed-old-command',
          principalBinding: 'endpoint:user-one',
        ),
        isFalse,
      );
      expect(
        await ClientCommandIdentity.completeIntent(
          'ticket_order',
          reordered,
          commandId: claims.first,
          principalBinding: 'endpoint:user-two',
        ),
        isFalse,
      );
      expect(
        await ClientCommandIdentity.completeIntent(
          'ticket_order',
          reordered,
          commandId: claims.first,
          principalBinding: 'endpoint:user-one',
        ),
        isTrue,
      );
      final newer = await ClientCommandIdentity.claimIntent(
        'ticket_order',
        payload,
        principalBinding: 'endpoint:user-two',
      );
      expect(newer, isNot(claims.first));
      expect(
        await ClientCommandIdentity.completeIntent(
          'ticket_order',
          payload,
          commandId: claims.first,
          principalBinding: 'endpoint:user-one',
        ),
        isFalse,
      );
      expect(
        await ClientCommandIdentity.claimIntent(
          'ticket_order',
          payload,
          principalBinding: 'endpoint:user-two',
        ),
        newer,
      );
      final submitted = <String>[];
      final transport = ClientCommandTransport(
        (name, parameters) async {
          submitted.add(parameters['p_command_id'] as String);
          if (submitted.length == 1) throw TimeoutException('lost response');
          return commandResponseFixture(
            parameters['p_command_id'] as String,
            status: 'expired',
            code: 410,
          );
        },
        maxAttempts: 1,
        principalBinding: 'endpoint:user-one',
      );
      final original = {
        'p_expected_version': 7,
        'p_form': {
          'expected_product_versions': {'9': 4},
        },
        'p_config': {'id': 42},
      };
      await expectLater(
        transport.invoke('save_fixture', original),
        throwsA(isA<TimeoutException>()),
      );
      await StorageHelper.closeDatabase('default.db');
      expect(
        (await transport.invoke('save_fixture', original) as Map)['code'],
        410,
      );
      // A tombstone preserves the original identity. It cannot force a new execution.
      expect(submitted.toSet(), hasLength(1));
      await transport.invoke('save_fixture', original);
      expect(submitted.toSet(), hasLength(1));
      await expectLater(
        transport.invoke('save_fixture', {
          ...original,
          'p_expected_version': 8,
        }),
        throwsStateError,
      );
      expect(submitted, hasLength(3));
      final pending = await transport.pendingIntent('save_fixture', original);
      expect(pending, isNotNull);
      expect(
        (jsonDecode(pending!.requestJson) as Map)['p_expected_version'],
        7,
      );
      await transport.resume(pending);
      expect(submitted.toSet(), hasLength(1));

      final reopened = await StorageHelper.openDatabase();
      expect(
        (await StoreRef.main().find(reopened)).any(
          (r) =>
              r.value is Map &&
              (r.value as Map)['/parameters/p_expected_version'] == 7 &&
              (r.value as Map)['/parameters/p_form/expected_product_versions']
                  is Map &&
              ((r.value as Map)['/parameters/p_form/expected_product_versions']
                      as Map)['9'] ==
                  4,
        ),
        isTrue,
      );
    },
  );
  group('durable transport identity guards', () {
    late Directory directory;
    late PathProviderPlatform provider;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'festapp-command-guard-',
      );
      provider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Documents(directory.path);
    });
    tearDown(() async {
      await StorageHelper.closeDatabase('default.db');
      PathProviderPlatform.instance = provider;
      await directory.delete(recursive: true);
    });

    test(
      'confirmed old form save never silently applies newer edits',
      () async {
        final calls = <String>[];
        final ids = <String>[];
        final transport = ClientCommandTransport(
          (name, parameters) async {
            calls.add(name);
            ids.add(parameters['p_command_id'] as String);
            if (calls.length == 1)
              throw TimeoutException('acknowledgement lost');
            expect(name, 'recover_form_save_client_sync_v1');
            return commandResponseFixture(ids.last, data: {'form_id': 42});
          },
          principalBinding: 'backend:form-editor',
          maxAttempts: 1,
        );
        final commands = SupabaseFormCommands.withTransport(transport);
        final original = <String, dynamic>{
          'id': 42,
          'occasion': 7,
          'title': 'Original',
          'expected_aggregate_version': 3,
          'expected_product_versions': <String, dynamic>{},
          'expected_product_type_versions': <String, dynamic>{},
        };
        await expectLater(
          commands.save(original),
          throwsA(isA<TimeoutException>()),
        );
        await expectLater(
          commands.save({...original, 'title': 'Changed'}),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'FORM_PREVIOUS_SAVE_CONFIRMED',
            ),
          ),
        );
        expect(calls, [
          'update_form_client_sync_v1',
          'recover_form_save_client_sync_v1',
        ]);
        expect(ids.toSet(), hasLength(1));
        expect(
          await transport.pendingIntent('update_form_client_sync_v1', {
            'p_form': original,
          }),
          isNull,
        );
      },
    );

    test(
      'form save recovers a rolled-back command before changed edits',
      () async {
        final calls = <String>[];
        final ids = <String>[];
        var failed = false;
        final transport = ClientCommandTransport(
          (name, parameters) async {
            calls.add(name);
            ids.add(parameters['p_command_id'] as String);
            if (!failed) {
              failed = true;
              throw TimeoutException('save response lost');
            }
            if (name == 'recover_form_save_client_sync_v1') {
              expect((parameters['p_form'] as Map)['title'], 'Original');
              return commandResponseFixture(
                ids.last,
                status: 'rejected',
                code: 409,
                data: {'message': 'FORM_SAVE_NOT_APPLIED'},
              );
            }
            expect((parameters['p_form'] as Map)['title'], 'Changed');
            return commandResponseFixture(ids.last, data: {'form_id': 42});
          },
          principalBinding: 'backend:form-editor',
          maxAttempts: 1,
        );
        final commands = SupabaseFormCommands.withTransport(transport);
        final original = <String, dynamic>{
          'id': 42,
          'occasion': 7,
          'title': 'Original',
          'expected_aggregate_version': 3,
          'expected_product_versions': <String, dynamic>{},
          'expected_product_type_versions': <String, dynamic>{},
        };
        await expectLater(
          commands.save(original),
          throwsA(isA<TimeoutException>()),
        );
        final result = await commands.save({...original, 'title': 'Changed'});
        expect(result['form_id'], 42);
        expect(calls, [
          'update_form_client_sync_v1',
          'recover_form_save_client_sync_v1',
          'update_form_client_sync_v1',
        ]);
        expect(ids[1], ids[0]);
        expect(ids[2], isNot(ids[0]));
        expect(
          await transport.pendingIntent('update_form_client_sync_v1', {
            'p_form': original,
          }),
          isNull,
        );
      },
    );

    test(
      'a mismatched response retains the original ID until confirmed replay',
      () async {
        final ids = <String>[];
        var wrong = true;
        final transport = ClientCommandTransport(
          (name, parameters) async {
            ids.add(parameters['p_command_id'] as String);
            return commandResponseFixture(
              wrong ? ClientCommandIdentity.newCommandId() : ids.last,
            );
          },
          principalBinding: 'backend:actor',
          maxAttempts: 1,
        );
        final request = {
          'p_occasion': 7,
          'p_group': {'id': 9},
          'p_expected_version': 3,
        };
        await expectLater(
          transport.invoke('save_fixture', request),
          throwsFormatException,
        );
        expect(
          await transport.pendingIntent('save_fixture', request),
          isNotNull,
        );
        wrong = false;
        await transport.invoke('save_fixture', request);
        expect(ids.toSet(), hasLength(1));
        expect(await transport.pendingIntent('save_fixture', request), isNull);
      },
    );

    test(
      'an account change during dispatch preserves the prior actor intent',
      () async {
        var principal = 'backend:actor-a';
        final entered = Completer<void>();
        final release = Completer<void>();
        final ids = <String>[];
        final transport = ClientCommandTransport(
          (name, parameters) async {
            ids.add(parameters['p_command_id'] as String);
            if (!entered.isCompleted) entered.complete();
            await release.future;
            return commandResponseFixture(ids.last);
          },
          principalProvider: () => principal,
          maxAttempts: 1,
        );
        final request = {
          'p_occasion': 7,
          'p_group': {'id': 9},
        };
        final flight = transport.invoke('save_fixture', request);
        final rejected = expectLater(flight, throwsStateError);
        await entered.future;
        principal = 'backend:actor-b';
        release.complete();
        await rejected;
        expect(await transport.pendingIntent('save_fixture', request), isNull);
        principal = 'backend:actor-a';
        final original = await transport.pendingIntent('save_fixture', request);
        expect(original, isNotNull);
        await transport.resume(original!);
        expect(ids.toSet(), hasLength(1));
        expect(await transport.pendingIntent('save_fixture', request), isNull);
      },
    );

    test(
      'malformed terminal replies retain identity on dispatch and resume',
      () async {
        final ids = <String>[];
        var malformed = true;
        final transport = ClientCommandTransport(
          (name, parameters) async {
            ids.add(parameters['p_command_id'] as String);
            final response = commandResponseFixture(ids.last);
            if (malformed) (response['mutation'] as Map).remove('receiptId');
            return response;
          },
          principalBinding: 'backend:actor',
          maxAttempts: 1,
        );
        final request = {
          'p_occasion': 7,
          'p_group': {'id': 9},
        };
        await expectLater(
          transport.invoke('save_fixture', request),
          throwsFormatException,
        );
        final original = await transport.pendingIntent('save_fixture', request);
        expect(original, isNotNull);
        await expectLater(transport.resume(original!), throwsFormatException);
        expect(
          (await transport.pendingIntent('save_fixture', request))!.commandId,
          original.commandId,
        );
        malformed = false;
        await transport.resume(original);
        expect(ids.toSet(), hasLength(1));
        expect(await transport.pendingIntent('save_fixture', request), isNull);
      },
    );

    for (final status in ['unchanged', 'rejected', 'conflict']) {
      test('confirmed $status retires the exact durable intent', () async {
        final transport = ClientCommandTransport(
          (name, parameters) async => commandResponseFixture(
            parameters['p_command_id'] as String,
            status: status,
            code: status == 'unchanged' ? 200 : 409,
          ),
          principalBinding: 'backend:actor',
        );
        final request = {
          'p_occasion': 7,
          'p_group': {'id': 9},
        };
        await transport.invoke('save_fixture', request);
        expect(await transport.pendingIntent('save_fixture', request), isNull);
      });
    }

    test(
      'persisted historical keys recover without rewriting payment intents',
      () async {
        const operation = 'legacy.fixture';
        const principal = 'backend:actor';
        const scope = '7:9';
        const commandId = '00000000-0000-4000-8000-000000000007';
        // Literal keys emitted by the previous installed implementation.
        const pendingKey =
            'client_command_pending:legacy.fixture:'
            '43258cff783fe7036d8a43033f830adfc60ec037382473548ac742b888292777';
        const activeKey =
            'client_command_active:legacy.fixture:'
            'fea3b015556e64db79dea3295bf815c022c718c1c6e60c5033c6a9090f1aad06';
        const unrelatedPayment =
            'client_command_pending:ticket_order:historical-fixture';
        final db = await StorageHelper.openDatabase();
        final store = StoreRef.main();
        final records = <String, Object?>{
          pendingKey: commandId,
          '$pendingKey:principal': principal,
          '$pendingKey:scope': activeKey,
          '$pendingKey:request': '{"a":1,"b":2}',
          activeKey: {
            'commandId': commandId,
            'principal': principal,
            'pendingKey': pendingKey,
          },
          unrelatedPayment: 'unresolved-payment-command',
        };
        await db.transaction((transaction) async {
          for (final entry in records.entries) {
            await store.record(entry.key).put(transaction, entry.value);
          }
        });
        await StorageHelper.closeDatabase('default.db');
        expect(
          (await ClientCommandIdentity.pendingIntent(
            operation,
            principalBinding: principal,
            scopeBinding: scope,
          ))!.commandId,
          commandId,
        );
        expect(
          await ClientCommandIdentity.claimIntent(
            operation,
            {'b': 2, 'a': 1},
            principalBinding: principal,
            scopeBinding: scope,
            requestJson: '{"b":2,"a":1}',
          ),
          commandId,
        );
        expect(
          await ClientCommandIdentity.completeIntent(
            operation,
            {'a': 1, 'b': 2},
            commandId: commandId,
            principalBinding: principal,
          ),
          isTrue,
        );
        final reopened = await StorageHelper.openDatabase();
        expect(await store.record(activeKey).get(reopened), isNull);
        expect(
          await store.record(unrelatedPayment).get(reopened),
          'unresolved-payment-command',
        );
      },
    );

    test('two groups retain independent pending scopes', () async {
      final transport = ClientCommandTransport(
        (name, parameters) async {
          throw TimeoutException('unknown result');
        },
        principalBinding: 'backend:actor',
        maxAttempts: 1,
      );
      final one = {
        'p_occasion': 7,
        'p_group': {'id': 1},
        'p_expected_version': 3,
      };
      final two = {
        'p_occasion': 7,
        'p_group': {'id': 2},
        'p_expected_version': 3,
      };
      await expectLater(
        transport.invoke('save_fixture', one),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        transport.invoke('save_fixture', two),
        throwsA(isA<TimeoutException>()),
      );
      final first = await transport.pendingIntent('save_fixture', one);
      final second = await transport.pendingIntent('save_fixture', two);
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.commandId, isNot(second!.commandId));
      await expectLater(
        transport.invoke('save_fixture', {...one, 'p_expected_version': 4}),
        throwsStateError,
      );
    });
  });
}

class _Documents extends PathProviderPlatform {
  _Documents(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}
