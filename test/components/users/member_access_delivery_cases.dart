import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/member_access_delivery.dart';

void main() {
  Map<String, dynamic> receipt(String id) => {
    'communication': {'messageId': id, 'state': 'queued'},
  };
  Map<String, dynamic> status(Map<String, String> states) => {
    'messages': [
      for (final entry in states.entries)
        {'messageId': entry.key, 'state': entry.value},
    ],
  };

  test(
    'receipt status progresses automatically and unrelated history is excluded',
    () {
      fakeAsync((clock) {
        var reads = 0;
        final delivery = MemberAccessDelivery(
          isCurrent: () => true,
          readStatus: () async {
            reads++;
            return status({
              'own': reads == 1
                  ? 'queued'
                  : reads == 2
                  ? 'provider_accepted'
                  : 'delivered',
              'other': 'delivered',
            });
          },
        );
        delivery.track(receipt('own'));
        delivery.refresh();
        clock.flushMicrotasks();
        expect(delivery.states, {'own': 'queued'});
        clock.elapse(const Duration(seconds: 2));
        expect(delivery.states['own'], 'provider_accepted');
        expect(delivery.delivered, 0);
        clock.elapse(const Duration(seconds: 5));
        expect(delivery.delivered, 1);
        expect(delivery.watching, isFalse);
        clock.elapse(const Duration(minutes: 3));
        expect(reads, 3);
        delivery.dispose();
      });
    },
  );

  test(
    'partial failure and unknown delivery remain separate until all terminal',
    () {
      fakeAsync((clock) {
        var state = 'dispatch_unresolved';
        final delivery = MemberAccessDelivery(
          isCurrent: () => true,
          readStatus: () async => status({'a': 'failed', 'b': state}),
        );
        delivery.track(receipt('a'));
        delivery.track(receipt('b'));
        delivery.refresh();
        clock.flushMicrotasks();
        expect(delivery.states, {'a': 'failed', 'b': 'dispatch_unresolved'});
        expect(delivery.watching, isTrue);
        state = 'delivered';
        clock.elapse(const Duration(seconds: 2));
        expect(delivery.states['a'], 'failed');
        expect(delivery.delivered, 1);
        expect(delivery.watching, isFalse);
        delivery.dispose();
      });
    },
  );

  test(
    'slow reads stop loading without overlapping and manual refresh recovers',
    () {
      fakeAsync((clock) {
        var reads = 0;
        final pending = Completer<Map<String, dynamic>>();
        final delivery = MemberAccessDelivery(
          isCurrent: () => true,
          readStatus: () {
            reads++;
            return reads == 1
                ? pending.future
                : Future.value(status({'a': 'delivered'}));
          },
        );
        delivery.track(receipt('a'));
        final first = delivery.refresh();
        expect(delivery.refresh(restart: true), same(first));
        clock.elapse(const Duration(seconds: 16));
        expect(delivery.showingLoading, isFalse);
        expect(delivery.delayed, isTrue);
        expect(delivery.reading, isTrue);
        clock.elapse(const Duration(minutes: 3));
        expect(reads, 1);
        pending.complete(status({'a': 'queued'}));
        clock.flushMicrotasks();
        expect(delivery.watching, isFalse);
        delivery.refresh(restart: true);
        clock.flushMicrotasks();
        expect(delivery.delivered, 1);
        expect(delivery.delayed, isFalse);
        delivery.dispose();
      });
    },
  );

  test('observation window is bounded and manual refresh restarts read-only tracking', () {
    fakeAsync((clock) {
      var reads = 0;
      final delivery = MemberAccessDelivery(
        isCurrent: () => true,
        readStatus: () async {
          reads++;
          return status({'a': 'queued'});
        },
      );
      delivery.track(receipt('a'));
      delivery.refresh();
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 2));
      expect(delivery.delayed, isTrue);
      expect(delivery.watching, isFalse);
      final stoppedAt = reads;
      clock.elapse(const Duration(minutes: 5));
      expect(reads, stoppedAt);
      delivery.refresh(restart: true);
      clock.flushMicrotasks();
      expect(delivery.watching, isTrue);
      clock.elapse(const Duration(seconds: 2));
      expect(reads, greaterThan(stoppedAt + 1));
      delivery.dispose();
    });
  });

  test('reopening tracks only pending selected members and retains last status on read error', () {
    fakeAsync((clock) {
      var fail = false;
      final delivery = MemberAccessDelivery(
        isCurrent: () => true,
        selectedUserIds: {'selected'},
        readStatus: () async {
          if (fail) throw StateError('offline');
          return {
            'messages': [
              {'messageId': 'a', 'userId': 'selected', 'state': 'queued'},
              {'messageId': 'b', 'userId': 'selected', 'state': 'delivered'},
              {'messageId': 'c', 'userId': 'other', 'state': 'queued'},
            ],
          };
        },
      );
      delivery.refresh();
      clock.flushMicrotasks();
      expect(delivery.states, {'a': 'queued'});
      fail = true;
      clock.elapse(const Duration(seconds: 2));
      expect(delivery.readFailed, isTrue);
      expect(delivery.states['a'], 'queued');
      delivery.dispose();
    });
  });

  test('context invalidation and disposal discard stale responses and cancel polls', () {
    for (final dispose in [false, true]) {
      fakeAsync((clock) {
        var current = true;
        final pending = Completer<Map<String, dynamic>>();
        final delivery = MemberAccessDelivery(
          isCurrent: () => current,
          readStatus: () => pending.future,
        );
        delivery.track(receipt('a'));
        delivery.refresh();
        var notifications = 0;
        delivery.addListener(() => notifications++);
        if (dispose) {
          delivery.dispose();
        } else {
          current = false;
        }
        pending.complete(status({'a': 'delivered'}));
        clock.flushMicrotasks();
        clock.elapse(const Duration(minutes: 3));
        expect(delivery.states['a'], 'queued');
        expect(notifications, 0);
        expect(clock.pendingTimers, isEmpty);
        if (!dispose) delivery.dispose();
      });
    }
  });
}
