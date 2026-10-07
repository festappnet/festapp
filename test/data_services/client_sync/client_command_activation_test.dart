import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';
import 'package:fstapp/data_services/client_sync/client_sync_protocol.dart';

ClientCommandResponse response(
        {int revision = 2, Object payload = const {'a': 1, 'b': 2}}) =>
    ClientCommandResponse.from({
      'status': 'applied',
      'code': 200,
      'data': {},
      'mutation': {
        'commandId': '00000000-0000-4000-8000-000000000001',
        'receiptId': '00000000-0000-4000-8000-000000000001',
        'commitId': '00000000-0000-4000-8000-000000000002',
        'replayed': false,
        'occurredAt': '2026-10-07T10:00:00Z'
      },
      'sync': {
        'replacements': [
          {
            'component': 'map_catalog',
            'revision': revision,
            'payload': payload
          },
          {
            'component': 'private_profile',
            'revision': revision,
            'payload': payload
          }
        ]
      }
    });

class Activation implements ClientCommandActivation {
  Activation(this.contextToken);
  @override
  String contextToken;
  @override
  bool enabled = true;
  @override
  bool hasPrivateIdentity = true;
  final revisions = <ClientSyncComponent, int>{};
  int calls = 0, notifications = 0;
  final searchNotifications = <bool>[];
  bool failPrivate = false, switchContext = false;
  @override
  Future<int?> revision(ClientSyncComponent c) async => revisions[c];
  @override
  Future<void> apply(ClientSyncComponent c, int revision, Object? payload,
      String token) async {
    expect(token, contextToken);
    calls++;
    if (c.isPrivate && failPrivate) throw StateError('cache failure');
    if (switchContext) {
      contextToken = 'changed';
      return;
    }
    revisions[c] = revision;
  }

  @override
  void notify(bool searchIndexChanged) {
    notifications++;
    searchNotifications.add(searchIndexChanged);
  }
}

void main() {
  test('public and actor-private classes activate once with one notification',
      () async {
    final a = Activation('two-classes');
    await response().applyReplacements(activation: a);
    await response(payload: {'b': 2, 'a': 1}).applyReplacements(activation: a);
    expect(a.calls, 2);
    expect(a.notifications, 1);
  });
  test(
      'partial cache failure repairs only the unactivated class with same receipt',
      () async {
    final a = Activation('repair')..failPrivate = true;
    await expectLater(
        response().applyReplacements(activation: a), throwsStateError);
    expect(a.notifications, 0);
    a.failPrivate = false;
    await response().applyReplacements(activation: a);
    expect(a.calls, 3);
    expect(a.notifications, 1);
    expect(a.searchNotifications, [true]);
  });
  test('late context and lower revisions have no effects', () async {
    final a = Activation('scope')..switchContext = true;
    await response().applyReplacements(activation: a);
    expect(a.calls, 1);
    expect(a.notifications, 0);
    final b = Activation('lower');
    b.revisions.addAll({
      ClientSyncComponent.mapCatalog: 3,
      ClientSyncComponent.privateProfile: 3
    });
    await response().applyReplacements(activation: b);
    expect(b.calls, 0);
    expect(b.notifications, 0);
  });
  test('same command revision with divergent content is diagnosed', () async {
    final a = Activation('divergence');
    await response().applyReplacements(activation: a);
    await expectLater(
        response(payload: {'a': 3}).applyReplacements(activation: a),
        throwsStateError);
    expect(a.calls, 2);
  });
}
