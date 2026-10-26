import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';
import 'package:fstapp/components/map/public_map_host.dart';
import 'package:fstapp/components/map/public_map_session.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('first and second visits retain one surface and complete on Back',
      () async {
    final navigation = _VisitNavigation();
    final host = _RetainedHost();
    final session = PublicMapSession()
      ..bindNavigation(navigation)
      ..attachHost(host);

    final first = session.openPlace(1);
    var firstCompleted = false;
    first.then((_) => firstCompleted = true);
    expect(navigation.pushes, 1);
    session.setVisible(true);
    await Future<void>.delayed(Duration.zero);
    expect(host.placeIds, [1]);
    expect(host.surfaceId, 'retained-surface');
    expect(firstCompleted, isFalse);
    navigation.pop();
    expect((await first).kind, MapVisitKind.returned);

    session.setVisible(false);
    final second = session.openPlace(2);
    var secondCompleted = false;
    second.then((_) => secondCompleted = true);
    expect(navigation.pushes, 2);
    session.setVisible(true);
    await Future<void>.delayed(Duration.zero);
    expect(host.placeIds, [1, 2]);
    expect(host.surfaceId, 'retained-surface');
    expect(secondCompleted, isFalse);
    navigation.pop();
    expect((await second).kind, MapVisitKind.returned);

    expect(host.mounts, 1);
    session.dispose();
  });
}

final class _VisitNavigation implements MapTabNavigationAdapter {
  int pushes = 0;
  Completer<void>? _route;

  @override
  Future<void> activateMap() {
    pushes++;
    _route = Completer<void>();
    return _route!.future;
  }

  @override
  Future<void> deactivateMap() async => pop();

  void pop() => _route!.complete();
}

final class _RetainedHost implements PublicMapHost {
  final int mounts = 1;
  final String surfaceId = 'retained-surface';
  final List<int> placeIds = [];

  @override
  PublicMapHostSnapshot get snapshot => PublicMapHostSnapshot(
        surfaceId: surfaceId,
        styleEpoch: 1,
        readinessEpoch: 1,
        catalogEpoch: 1,
        activeLayoutReady: true,
      );

  @override
  Future<PublicMapHostResult> applyIntent(PublicMapEffect effect) async {
    final placeId = (effect.intent as MapPlaceIntent).placeId;
    placeIds.add(placeId);
    final command = CameraCommand(
      surfaceId: surfaceId,
      destination: LatLng(49.8 + placeId / 1000, 18.2),
      zoom: 18,
    );
    return PublicMapHostResult.applied(CameraApplyResult(
      status: CameraApplyStatus.applied,
      surfaceId: surfaceId,
      command: command,
      actual: MapCameraState(
        center: command.destination,
        zoom: command.zoom,
      ),
    ));
  }

  @override
  Future<void> resetToOverview() async {}
}
