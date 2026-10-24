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
}

class _Documents extends PathProviderPlatform {
  _Documents(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}
