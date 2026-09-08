import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/maplibre/maplibre_style_load_guard.dart';

void main() {
  test('reveals the base map even when scene decoration fails', () async {
    final events = <String>[];

    await completeMapLibreStyleLoad(
      revealBaseMap: () => events.add('revealed'),
      decorateStyle: () async {
        events.add('decorating');
        throw StateError('marker registration failed');
      },
      onDecorationError: (error, stackTrace) => events.add('logged'),
      markCameraReady: () => events.add('ready'),
    );

    expect(events, ['revealed', 'decorating', 'logged', 'ready']);
  });

  test('watchdog reveals the map when the native callback never arrives',
      () async {
    final events = <String>[];
    final watchdog = MapLibreStyleLoadWatchdog(
      timeout: const Duration(milliseconds: 10),
    );

    watchdog.arm(
      revealBaseMap: () => events.add('revealed'),
      onTimeout: () => events.add('timed-out'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(events, ['timed-out', 'revealed']);
    watchdog.dispose();
  });

  test('native style completion cancels the watchdog', () async {
    final events = <String>[];
    final watchdog = MapLibreStyleLoadWatchdog(
      timeout: const Duration(milliseconds: 10),
    );

    watchdog.arm(
      revealBaseMap: () => events.add('revealed'),
      onTimeout: () => events.add('timed-out'),
    );
    watchdog.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(events, isEmpty);
    watchdog.dispose();
  });

  test('optional native setup never blocks style readiness', () async {
    final pendingPermission = Completer<void>();
    final events = <String>[];

    await completeMapLibreStyleLoad(
      revealBaseMap: () => events.add('revealed'),
      decorateStyle: () async {
        startOptionalMapLibreSetup(
          setup: () => pendingPermission.future,
          onError: (error, stackTrace) => events.add('location-error'),
        );
        events.add('decorated');
      },
      onDecorationError: (error, stackTrace) => events.add('decoration-error'),
      markCameraReady: () => events.add('ready'),
    );

    expect(events, ['revealed', 'decorated', 'ready']);
    pendingPermission.complete();
  });

  test('a changed offline style is explicitly reloaded', () {
    final reloaded = <String>[];

    final changed = reloadMapLibreStyleIfChanged(
      previousStyle: '{"name":"old"}',
      nextStyle: '{"name":"new"}',
      reload: reloaded.add,
    );

    expect(changed, isTrue);
    expect(reloaded, ['{"name":"new"}']);
  });

  test('an unchanged offline style is not reloaded', () {
    final reloaded = <String>[];

    final changed = reloadMapLibreStyleIfChanged(
      previousStyle: '{"name":"same"}',
      nextStyle: '{"name":"same"}',
      reload: reloaded.add,
    );

    expect(changed, isFalse);
    expect(reloaded, isEmpty);
  });
}
