import 'dart:convert';
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
  test('durable concurrent claims bind one actor and survive reopening',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('festapp-reference-intent-');
    final provider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Documents(directory.path);
    addTearDown(() async {
      await StorageHelper.closeDatabase('default.db');
      PathProviderPlatform.instance = provider;
      await directory.delete(recursive: true);
    });
    final clients = await Future.wait(
        List.generate(12, (_) => ClientCommandIdentity.clientId()));
    expect(clients.toSet(), hasLength(1));
    const payload = {
      'form': 'reference-fixture',
      'email': 'private@example.invalid',
      'ticket': [
        {'b': 2, 'a': 1}
      ]
    };
    final claims = await Future.wait(List.generate(
        12,
        (_) => ClientCommandIdentity.claimIntent('ticket_order', payload,
            principalBinding: 'endpoint:user-one')));
    expect(claims.toSet(), hasLength(1));
    await StorageHelper.closeDatabase('default.db');
    expect(await ClientCommandIdentity.clientId(), clients.first);
    final reordered = {
      'ticket': [
        {'a': 1, 'b': 2}
      ],
      'email': 'private@example.invalid',
      'form': 'reference-fixture'
    };
    expect(
        await ClientCommandIdentity.claimIntent('ticket_order', reordered,
            principalBinding: 'endpoint:user-one'),
        claims.first);
    await expectLater(
        ClientCommandIdentity.claimIntent('ticket_order', payload,
            principalBinding: 'endpoint:user-two'),
        throwsStateError);
    final db = await StorageHelper.openDatabase();
    expect(
        jsonEncode(
            (await StoreRef.main().find(db)).map((r) => r.value).toList()),
        isNot(contains('private@example.invalid')));
    expect(
        await ClientCommandIdentity.completeIntent('ticket_order', reordered,
            commandId: 'delayed-old-command',
            principalBinding: 'endpoint:user-one'),
        isFalse);
    expect(
        await ClientCommandIdentity.completeIntent('ticket_order', reordered,
            commandId: claims.first, principalBinding: 'endpoint:user-two'),
        isFalse);
    expect(
        await ClientCommandIdentity.completeIntent('ticket_order', reordered,
            commandId: claims.first, principalBinding: 'endpoint:user-one'),
        isTrue);
    final newer = await ClientCommandIdentity.claimIntent(
        'ticket_order', payload,
        principalBinding: 'endpoint:user-two');
    expect(newer, isNot(claims.first));
    expect(
        await ClientCommandIdentity.completeIntent('ticket_order', payload,
            commandId: claims.first, principalBinding: 'endpoint:user-one'),
        isFalse);
    expect(
        await ClientCommandIdentity.claimIntent('ticket_order', payload,
            principalBinding: 'endpoint:user-two'),
        newer);
    final submitted = <String>[];
    final transport = ClientCommandTransport((name, parameters) async {
      submitted.add(parameters['p_command_id'] as String);
      if (submitted.length == 1) throw TimeoutException('lost response');
      return {'status': 'expired', 'code': 410};
    }, maxAttempts: 1, principalBinding: 'endpoint:user-one');
    final original = {
      'p_expected_version': 7,
      'p_form': {
        'expected_product_versions': {'9': 4}
      },
      'p_config': {'id': 42}
    };
    await expectLater(transport.invoke('save_fixture', original),
        throwsA(isA<TimeoutException>()));
    await StorageHelper.closeDatabase('default.db');
    expect(
        (await transport.invoke('save_fixture', original) as Map)['code'], 410);
    // A tombstone preserves the original identity. It cannot force a new execution.
    expect(submitted.toSet(), hasLength(1));
    await transport.invoke('save_fixture', original);
    expect(submitted.toSet(), hasLength(1));
    await expectLater(
        transport
            .invoke('save_fixture', {...original, 'p_expected_version': 8}),
        throwsStateError);
    expect(submitted, hasLength(3));
    final pending = await transport.pendingIntent('save_fixture', original);
    expect(pending, isNotNull);
    expect((jsonDecode(pending!.requestJson) as Map)['p_expected_version'], 7);
    await transport.resume(pending);
    expect(submitted.toSet(), hasLength(1));

    final reopened = await StorageHelper.openDatabase();
    expect(
        (await StoreRef.main().find(reopened)).any((r) =>
            r.value is Map &&
            (r.value as Map)['/parameters/p_expected_version'] == 7 &&
            (r.value as Map)['/parameters/p_form/expected_product_versions']
                is Map &&
            ((r.value as Map)['/parameters/p_form/expected_product_versions']
                    as Map)['9'] ==
                4),
        isTrue);
  });
  group('durable transport identity guards', () {
    late Directory directory;
    late PathProviderPlatform provider;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('festapp-command-guard-');
      provider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Documents(directory.path);
    });
    tearDown(() async {
      await StorageHelper.closeDatabase('default.db');
      PathProviderPlatform.instance = provider;
      await directory.delete(recursive: true);
    });

    test('a mismatched response retains the original ID until confirmed replay', () async {
      final ids = <String>[];
      var wrong = true;
      final transport = ClientCommandTransport((name, parameters) async {
        ids.add(parameters['p_command_id'] as String);
        return {'code': 200, 'status': 'applied', 'mutation': {
          'commandId': wrong ? ClientCommandIdentity.newCommandId() : ids.last,
        }};
      }, principalBinding: 'backend:actor', maxAttempts: 1);
      final request = {'p_occasion': 7, 'p_group': {'id': 9}, 'p_expected_version': 3};
      await expectLater(transport.invoke('save_fixture', request), throwsFormatException);
      expect(await transport.pendingIntent('save_fixture', request), isNotNull);
      wrong = false;
      await transport.invoke('save_fixture', request);
      expect(ids.toSet(), hasLength(1));
      expect(await transport.pendingIntent('save_fixture', request), isNull);
    });

    test('an account change during dispatch preserves the prior actor intent', () async {
      var principal = 'backend:actor-a';
      final entered = Completer<void>();
      final release = Completer<void>();
      final ids = <String>[];
      final transport = ClientCommandTransport((name, parameters) async {
        ids.add(parameters['p_command_id'] as String);
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return {'code': 200, 'status': 'applied', 'mutation': {'commandId': ids.last}};
      }, principalProvider: () => principal, maxAttempts: 1);
      final request = {'p_occasion': 7, 'p_group': {'id': 9}};
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
    });

    test('two groups retain independent pending scopes', () async {
      final transport = ClientCommandTransport((name, parameters) async {
        throw TimeoutException('unknown result');
      }, principalBinding: 'backend:actor', maxAttempts: 1);
      final one = {'p_occasion': 7, 'p_group': {'id': 1}, 'p_expected_version': 3};
      final two = {'p_occasion': 7, 'p_group': {'id': 2}, 'p_expected_version': 3};
      await expectLater(transport.invoke('save_fixture', one), throwsA(isA<TimeoutException>()));
      await expectLater(transport.invoke('save_fixture', two), throwsA(isA<TimeoutException>()));
      final first = await transport.pendingIntent('save_fixture', one);
      final second = await transport.pendingIntent('save_fixture', two);
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.commandId, isNot(second!.commandId));
      await expectLater(transport.invoke('save_fixture', {...one, 'p_expected_version': 4}), throwsStateError);
    });
  });

}

class _Documents extends PathProviderPlatform {
  _Documents(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}
