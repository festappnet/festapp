import 'dart:convert';
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
    await ClientCommandIdentity.completeIntent('ticket_order', reordered);
    expect(
        await ClientCommandIdentity.claimIntent('ticket_order', payload,
            principalBinding: 'endpoint:user-two'),
        isNot(claims.first));
  });
}

class _Documents extends PathProviderPlatform {
  _Documents(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}
