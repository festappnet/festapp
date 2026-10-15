import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/saved_program_mutation_coordinator.dart';

void main() {
  test('serializes mutations across different events and pages', () async {
    var scope = 'user-a';
    final first = Completer<bool>();
    final started = <int>[];
    final coordinator = SavedProgramMutationCoordinator(
      currentScope: () => scope,
      persist: (scope, eventId, saved) {
        started.add(eventId);
        return eventId == 1 ? first.future : Future.value(true);
      },
    );

    final eventOne = coordinator.enqueue(
      scope: scope,
      eventId: 1,
      saved: true,
    );
    final eventTwo = coordinator.enqueue(
      scope: scope,
      eventId: 2,
      saved: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(started, [1]);

    first.complete(true);
    expect((await eventOne).outcome, SavedProgramMutationOutcome.applied);
    expect((await eventTwo).outcome, SavedProgramMutationOutcome.applied);
    expect(started, [1, 2]);
  });

  test('coalesces pending choices for the same event to the latest', () async {
    const scope = 'user-a';
    final blocker = Completer<bool>();
    final persisted = <bool>[];
    final coordinator = SavedProgramMutationCoordinator(
      currentScope: () => scope,
      persist: (_, eventId, saved) {
        if (eventId == 1) return blocker.future;
        persisted.add(saved);
        return Future.value(true);
      },
    );

    final inFlight = coordinator.enqueue(
      scope: scope,
      eventId: 1,
      saved: true,
    );
    final oldPending = coordinator.enqueue(
      scope: scope,
      eventId: 2,
      saved: true,
    );
    final latestPending = coordinator.enqueue(
      scope: scope,
      eventId: 2,
      saved: false,
    );

    expect((await oldPending).outcome, SavedProgramMutationOutcome.superseded);
    blocker.complete(true);
    await inFlight;
    expect((await latestPending).outcome, SavedProgramMutationOutcome.applied);
    expect(persisted, [false]);
  });

  test('applies a remove queued behind an in-flight add in order', () async {
    const scope = 'user-a';
    final first = Completer<bool>();
    final persisted = <bool>[];
    final coordinator = SavedProgramMutationCoordinator(
      currentScope: () => scope,
      persist: (_, __, saved) {
        persisted.add(saved);
        return persisted.length == 1 ? first.future : Future.value(true);
      },
    );

    final add = coordinator.enqueue(scope: scope, eventId: 1, saved: true);
    await Future<void>.delayed(Duration.zero);
    final remove = coordinator.enqueue(scope: scope, eventId: 1, saved: false);
    first.complete(true);

    expect((await add).outcome, SavedProgramMutationOutcome.applied);
    expect((await remove).outcome, SavedProgramMutationOutcome.applied);
    expect(persisted, [true, false]);
  });

  test('never starts a queued mutation after identity changes', () async {
    var scope = 'user-a';
    final blocker = Completer<bool>();
    var secondStarted = false;
    final coordinator = SavedProgramMutationCoordinator(
      currentScope: () => scope,
      persist: (requestScope, eventId, saved) {
        if (eventId == 1) return blocker.future;
        secondStarted = true;
        return Future.value(true);
      },
    );

    final first = coordinator.enqueue(
      scope: scope,
      eventId: 1,
      saved: true,
    );
    final second = coordinator.enqueue(
      scope: scope,
      eventId: 2,
      saved: true,
    );
    scope = 'user-b';
    blocker.complete(true);

    expect((await first).outcome, SavedProgramMutationOutcome.scopeChanged);
    expect((await second).outcome, SavedProgramMutationOutcome.scopeChanged);
    expect(secondStarted, isFalse);
  });
}
