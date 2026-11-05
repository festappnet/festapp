import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/form_opening_timer.dart';

void main() {
  testWidgets(
    'forty-day opening uses browser-safe waits and reloads only once at the target',
    (tester) async {
      final delays = <Duration>[];
      var opened = 0;
      late FormOpeningTimer alarm;
      runZoned(
        () {
          alarm = FormOpeningTimer(
            tester.binding.clock.now().add(
              const Duration(days: 40, seconds: 1),
            ),
            () => opened++,
            now: tester.binding.clock.now,
          );
        },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            delays.add(duration);
            return parent.createTimer(zone, duration, callback);
          },
        ),
      );
      addTearDown(alarm.cancel);
      expect(delays.single.inMilliseconds, lessThanOrEqualTo(2147483647));
      await tester.pump(const Duration(days: 40));
      expect(opened, 0, reason: 'daily rearming must not send network reloads');
      expect(
        delays.every((delay) => delay.inMilliseconds <= 2147483647),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(opened, 1);
      await tester.pump(const Duration(days: 2));
      expect(opened, 1);
    },
  );
  testWidgets('cancelling a distant opening prevents future reloads', (
    tester,
  ) async {
    var opened = 0;
    final alarm = FormOpeningTimer(
      tester.binding.clock.now().add(const Duration(days: 40)),
      () => opened++,
      now: tester.binding.clock.now,
    );
    await tester.pump(const Duration(days: 2));
    alarm.cancel();
    await tester.pump(const Duration(days: 40));
    expect(opened, 0);
  });
  testWidgets('near opening is neither rounded nor fired early', (
    tester,
  ) async {
    var opened = 0;
    final alarm = FormOpeningTimer(
      tester.binding.clock.now().add(const Duration(milliseconds: 1500)),
      () => opened++,
      now: tester.binding.clock.now,
    );
    addTearDown(alarm.cancel);
    await tester.pump(const Duration(milliseconds: 1499));
    expect(opened, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(opened, 1);
  });
}
