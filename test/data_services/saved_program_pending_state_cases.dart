import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/saved_program_pending_state.dart';

void main() {
  test('a pending add is immediately projected over confirmed state', () {
    final pending = SavedProgramPendingState();
    final owner = pending.createOwner();

    pending.set(42, owner, true);

    expect(pending.apply(const []), [42]);
  });

  test('a pending removal is immediately projected over confirmed state', () {
    final pending = SavedProgramPendingState();
    final owner = pending.createOwner();

    pending.set(42, owner, false);

    expect(pending.apply(const [7, 42]), [7]);
  });

  test('an older mutation cannot clear a newer pending intent', () {
    final pending = SavedProgramPendingState();
    final oldOwner = pending.createOwner();
    final newOwner = pending.createOwner();

    pending.set(42, oldOwner, false);
    pending.set(42, newOwner, true);
    pending.clear(42, oldOwner);

    expect(pending.apply(const []), [42]);
    pending.clear(42, newOwner);
    expect(pending.apply(const []), isEmpty);
  });

  test('an older mutation cannot overwrite a newer pending intent', () {
    final pending = SavedProgramPendingState();
    final oldOwner = pending.createOwner();
    final newOwner = pending.createOwner();

    pending.set(42, newOwner, true);
    pending.set(42, oldOwner, false);

    expect(pending.apply(const []), [42]);
  });

  test('identity cleanup removes every pending intent', () {
    final pending = SavedProgramPendingState();
    final oldOwner = pending.createOwner();
    pending.set(42, oldOwner, true);
    pending.set(43, pending.createOwner(), false);

    pending.clearAll();

    expect(pending.apply(const [43]), [43]);
    pending.set(42, oldOwner, true);
    expect(pending.apply(const []), isEmpty,
        reason: 'a pre-logout owner must never repopulate the overlay');
  });

  test('online refresh waits while an optimistic mutation is pending', () {
    expect(
      shouldLoadSavedProgramOnline(
        isV1Selected: false,
        isOffline: false,
        hasPendingMutation: true,
      ),
      isFalse,
    );
    expect(
      shouldLoadSavedProgramOnline(
        isV1Selected: false,
        isOffline: false,
        hasPendingMutation: false,
      ),
      isTrue,
    );
  });

  test('listeners are notified when optimistic state starts and settles', () {
    final pending = SavedProgramPendingState();
    var notifications = 0;
    pending.addListener(() => notifications++);
    final owner = pending.createOwner();

    final before = pending.mutationVersion;
    pending.set(42, owner, true);
    final whilePending = pending.mutationVersion;
    pending.clear(42, owner);

    expect(notifications, 2);
    expect(whilePending, greaterThan(before));
    expect(pending.mutationVersion, greaterThan(whilePending));
  });
}
