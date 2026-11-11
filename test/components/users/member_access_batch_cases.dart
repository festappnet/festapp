import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/member_access_batch.dart';
import 'package:fstapp/components/users/member_access_commands.dart';
import 'package:fstapp/components/users/unit_user_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';

void main() {
  final manager = UnitUserModel(
    user: 'manager',
    emailReadonly: 'manager@example.test',
    isManager: true,
  );
  final viewer = UnitUserModel(
    user: 'viewer',
    emailReadonly: 'viewer@example.test',
    isEditorView: true,
  );
  MemberAccessBatch batch({
    String communication = 'notify_existing_access',
    Map<String, bool> roles = const {},
  }) => MemberAccessBatch(
    scope: 'unit',
    scopeId: 2,
    recipients: [manager, viewer].map(MemberAccessRecipient.fromUnit).toList(),
    communication: communication,
    offeredRoles: roles,
  );

  test(
    'selected IDs resolve saved memberships and retain differing grants',
    () {
      final selection = MemberAccessSelection(
        {'manager', 'viewer'},
        [manager, viewer],
      );
      expect(selection.unavailable, isFalse);
      expect(selection.recipients.first.roles['is_manager'], isTrue);
      expect(selection.recipients.last.roles['is_manager'], isFalse);
      expect(selection.recipients.last.roles['is_editor_view'], isTrue);
      expect(
        MemberAccessSelection({null, 'viewer'}, [viewer]).unavailable,
        isTrue,
      );
      expect(MemberAccessSelection({'removed'}, [viewer]).unavailable, isTrue);
      expect(MemberAccessSelection({}, [viewer]).recipients, isEmpty);
    },
  );

  test(
    'occasion snapshot includes grants absent from visible grid columns',
    () {
      final recipient = MemberAccessRecipient.fromOccasion(
        OccasionUserModel(
          user: 'occasion-user',
          data: {'email': 'person@example.test'},
          isReceptionist: true,
          isCleaningBlocked: true,
        ),
      );
      expect(recipient.roles['is_receptionist'], isTrue);
      expect(recipient.roles['is_cleaning_blocked'], isTrue);
    },
  );

  test(
    'default bulk notice binds identities without role or profile writes',
    () {
      for (final request in batch().requests.values) {
        expect(request['operation'], 'send_invitation');
        expect(request['communication'], 'notify_existing_access');
        expect(request['userId'], isNotEmpty);
        expect(request.containsKey('roles'), isFalse);
        expect(request.containsKey('changes'), isFalse);
        expect(request.containsKey('email'), isFalse);
      }
    },
  );

  test('explicit offers snapshot only the chosen additional roles', () {
    final roles = {'is_editor': true};
    final value = batch(communication: 'invite_to_accept', roles: roles);
    roles['is_manager'] = true;
    expect(value.requests['manager']!['roles'], {'is_editor': true});
    expect(value.requests['manager']!.containsKey('changes'), isFalse);
  });

  test(
    'partial failure retries only unconfirmed users with same request',
    () async {
      final value = batch();
      final calls = <String>[];
      var fail = true;
      Future<Map<String, dynamic>> send(Map<String, dynamic> request) async {
        final id = request['userId'] as String;
        calls.add(id);
        if (id == 'viewer' && fail)
          throw const MemberAccessFailure('preparation_deferred');
        return {
          'communication': {'state': 'queued', 'messageId': id},
        };
      }

      await value.send(send, isCurrent: () => true, onProgress: () {});
      expect(value.confirmed.keys, ['manager']);
      expect(value.failures, {'viewer': 'preparation_deferred'});
      final retry = value.requests['viewer'];
      fail = false;
      await value.send(send, isCurrent: () => true, onProgress: () {});
      expect(value.requests['viewer'], same(retry));
      expect(calls, ['manager', 'viewer', 'viewer']);
      expect(value.complete, isTrue);
      expect(value.failures, isEmpty);
      await value.send(send, isCurrent: () => true, onProgress: () {});
      expect(calls.length, 3);
    },
  );

  test('authorization or context loss stops further recipients', () async {
    final value = batch();
    var calls = 0;
    await value.send(
      (_) async {
        calls++;
        throw const MemberAccessFailure('scope_denied');
      },
      isCurrent: () => true,
      onProgress: () {},
    );
    expect(calls, 1);
    await value.send(
      (_) async {
        calls++;
        return {};
      },
      isCurrent: () => false,
      onProgress: () {},
    );
    expect(calls, 1);
  });
}
