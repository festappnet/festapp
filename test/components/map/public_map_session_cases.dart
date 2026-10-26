import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';
import 'package:fstapp/components/map/public_map_host.dart';
import 'package:fstapp/components/map/public_map_session.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('PublicMapSession', () {
    test('rapid intents share one activation and latest request wins',
        () async {
      final navigation = _FakeNavigation();
      final host = _FakeHost();
      final session = PublicMapSession()
        ..bindNavigation(navigation)
        ..attachHost(host);

      final first = session.openPlace(1);
      final second = session.openPlace(2);

      expect(identical(first, second), isTrue);
      expect(navigation.pushes, 1);
      session.setVisible(true);
      await _flush();
      expect(host.effects, hasLength(1));
      expect(host.effects.single.intent, isA<MapPlaceIntent>());
      expect((host.effects.single.intent as MapPlaceIntent).placeId, 2);

      navigation.pop();
      final result = await first;
      expect(result.kind, MapVisitKind.returned);
      expect(result.outcome.status, MapFocusStatus.applied);
      session.dispose();
    });

    test('duplicate place intent during one activation is coalesced', () async {
      final navigation = _FakeNavigation();
      final host = _FakeHost();
      final session = PublicMapSession()
        ..bindNavigation(navigation)
        ..attachHost(host);

      final first = session.openPlace(7);
      final duplicate = session.openPlace(7);
      session.setVisible(true);
      await _flush();

      expect(identical(first, duplicate), isTrue);
      expect(session.requestId, 1);
      expect(host.effects, hasLength(1));
      navigation.pop();
      await first;
      session.dispose();
    });

    test('active map resolves in place without pushing history', () async {
      final navigation = _FakeNavigation();
      final host = _FakeHost();
      final session = PublicMapSession()
        ..bindNavigation(navigation)
        ..attachHost(host)
        ..setVisible(true);

      final result = await session.openCategory('wc');

      expect(result.kind, MapVisitKind.resolvedInPlace);
      expect(navigation.pushes, 0);
      expect(host.effects.single.intent, isA<MapCategoryIntent>());
      session.dispose();
    });

    test('active map reselection resets the retained host to overview',
        () async {
      final host = _FakeHost();
      final session = PublicMapSession()
        ..attachHost(host)
        ..setVisible(true);

      await session.resetToOverview();

      expect(host.overviewResets, 1);
      session.dispose();
    });

    test('hidden map ignores overview resets', () async {
      final host = _FakeHost();
      final session = PublicMapSession()..attachHost(host);

      await session.resetToOverview();

      expect(host.overviewResets, 0);
      session.dispose();
    });

    test('one readiness tuple is attempted at most once', () async {
      final host = _FakeHost(
        result: PublicMapHostResult.retryable('layoutChanged'),
      );
      final session = PublicMapSession()
        ..attachHost(host)
        ..setVisible(true);
      final result = session.openPlace(7);
      await _flush();
      expect(host.effects, hasLength(1));

      session.hostChanged();
      session.hostChanged();
      await _flush();
      expect(host.effects, hasLength(1));

      host.readinessEpoch++;
      session.hostChanged();
      await _flush();
      expect(host.effects, hasLength(2));

      session.dispose();
      expect((await result).kind, MapVisitKind.cancelled);
    });

    test('applied intent is not presented again after host epoch changes',
        () async {
      final host = _FakeHost();
      final session = PublicMapSession()
        ..attachHost(host)
        ..setVisible(true);

      final result = await session.openPlace(7);
      expect(result.kind, MapVisitKind.resolvedInPlace);
      expect(host.effects, hasLength(1));

      host.readinessEpoch++;
      host.catalogEpoch++;
      session.hostChanged();
      await _flush();

      expect(host.effects, hasLength(1));
      session.dispose();
    });

    test('stale camera completion cannot overwrite a newer request', () async {
      final host = _ControllableHost();
      final session = PublicMapSession()
        ..attachHost(host)
        ..setVisible(true);

      final first = session.openPlace(1);
      await _flush();
      final second = session.openPlace(2);
      await _flush();
      expect((await first).kind, MapVisitKind.cancelled);

      host.complete(0, _applied(host.effects[0]));
      await _flush();
      expect(session.phase, PublicMapPhase.applying);
      host.complete(1, _applied(host.effects[1]));
      final result = await second;
      expect(result.kind, MapVisitKind.resolvedInPlace);
      expect(session.requestId, 2);
      session.dispose();
    });

    test('renderer swap ignores old completion and retries latest intent',
        () async {
      final host = _ControllableHost();
      final session = PublicMapSession()
        ..attachHost(host)
        ..setVisible(true);
      final result = session.openPlace(9);
      await _flush();

      host.surfaceId = 'surface-2';
      host.readinessEpoch++;
      session.hostChanged();
      await _flush();
      host.complete(0, _applied(host.effects[0]));
      await _flush();
      expect(session.phase, PublicMapPhase.applying);
      host.complete(1, _applied(host.effects[1]));

      expect((await result).outcome.status, MapFocusStatus.applied);
      session.dispose();
    });

    test('Back before readiness returns cancellation and suppresses late work',
        () async {
      final navigation = _FakeNavigation();
      final host = _FakeHost()..ready = false;
      final session = PublicMapSession()
        ..bindNavigation(navigation)
        ..attachHost(host);
      final visit = session.openPlace(3);
      session.setVisible(true);
      navigation.pop();

      final result = await visit;
      expect(result.kind, MapVisitKind.returned);
      expect(result.outcome.status, MapFocusStatus.cancelled);
      session.setVisible(false);
      host.ready = true;
      host.readinessEpoch++;
      session.hostChanged();
      await _flush();
      expect(host.effects, isEmpty);
      session.dispose();
    });

    test('closeVisit returns through the bound retained-tab adapter', () async {
      final navigation = _FakeNavigation();
      final session = PublicMapSession()..bindNavigation(navigation);
      final visit = session.openPlace(3);
      session.setVisible(true);

      expect(await session.closeVisit(), isTrue);
      expect(navigation.deactivations, 1);
      expect((await visit).kind, MapVisitKind.returned);
      session.dispose();
    });

    test('navigation failure and dispose complete typed results', () async {
      final failed = PublicMapSession()..bindNavigation(_FailingNavigation());
      expect(
        (await failed.openPlace(1)).kind,
        MapVisitKind.navigationFailed,
      );
      failed.dispose();

      final navigation = _FakeNavigation();
      final disposed = PublicMapSession()..bindNavigation(navigation);
      final pending = disposed.openPlace(2);
      disposed.dispose();
      expect((await pending).kind, MapVisitKind.cancelled);
    });
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

PublicMapHostResult _applied(PublicMapEffect effect) {
  final command = CameraCommand(
    surfaceId: effect.snapshot.surfaceId,
    destination: const LatLng(49.82, 18.27),
    zoom: 18,
  );
  return PublicMapHostResult.applied(CameraApplyResult(
    status: CameraApplyStatus.applied,
    surfaceId: command.surfaceId,
    command: command,
    actual: MapCameraState(center: command.destination, zoom: command.zoom),
  ));
}

final class _FakeNavigation implements MapTabNavigationAdapter {
  int pushes = 0;
  int deactivations = 0;
  Completer<void> route = Completer<void>();

  @override
  Future<void> activateMap() {
    pushes++;
    return route.future;
  }

  @override
  Future<void> deactivateMap() async {
    deactivations++;
    pop();
  }

  void pop() => route.complete();
}

final class _FailingNavigation implements MapTabNavigationAdapter {
  @override
  Future<void> activateMap() => Future<void>.error(StateError('guard'));

  @override
  Future<void> deactivateMap() => Future<void>.error(StateError('guard'));
}

class _FakeHost implements PublicMapHost {
  _FakeHost({this.result});

  String surfaceId = 'surface-1';
  int styleEpoch = 1;
  int readinessEpoch = 1;
  int catalogEpoch = 1;
  bool ready = true;
  PublicMapHostResult? result;
  final List<PublicMapEffect> effects = [];
  int overviewResets = 0;

  @override
  PublicMapHostSnapshot get snapshot => PublicMapHostSnapshot(
        surfaceId: surfaceId,
        styleEpoch: styleEpoch,
        readinessEpoch: readinessEpoch,
        catalogEpoch: catalogEpoch,
        activeLayoutReady: ready,
      );

  @override
  Future<PublicMapHostResult> applyIntent(PublicMapEffect effect) async {
    effects.add(effect);
    return result ?? _applied(effect);
  }

  @override
  Future<void> resetToOverview() async {
    overviewResets++;
  }
}

final class _ControllableHost extends _FakeHost {
  final List<Completer<PublicMapHostResult>> _completers = [];

  @override
  Future<PublicMapHostResult> applyIntent(PublicMapEffect effect) {
    effects.add(effect);
    final completer = Completer<PublicMapHostResult>();
    _completers.add(completer);
    return completer.future;
  }

  void complete(int index, PublicMapHostResult result) =>
      _completers[index].complete(result);
}
