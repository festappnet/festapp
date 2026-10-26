import 'package:fstapp/components/map/map_viewport_controller.dart';

sealed class MapIntent {
  const MapIntent();
}

final class MapPlaceIntent extends MapIntent {
  final int placeId;

  const MapPlaceIntent(this.placeId);
}

final class MapCategoryIntent extends MapIntent {
  final String placeType;

  const MapCategoryIntent(this.placeType);
}

enum MapFocusStatus { applied, unavailable, failed, cancelled }

final class MapFocusOutcome {
  final MapFocusStatus status;
  final String? reason;
  final CameraApplyResult? camera;

  const MapFocusOutcome._(this.status, {this.reason, this.camera});

  const MapFocusOutcome.applied(CameraApplyResult camera)
      : this._(MapFocusStatus.applied, camera: camera);

  const MapFocusOutcome.unavailable([String? reason])
      : this._(MapFocusStatus.unavailable, reason: reason);

  const MapFocusOutcome.failed([String? reason])
      : this._(MapFocusStatus.failed, reason: reason);

  const MapFocusOutcome.cancelled([String? reason])
      : this._(MapFocusStatus.cancelled, reason: reason);
}

final class PublicMapHostSnapshot {
  final String surfaceId;
  final int styleEpoch;
  final int readinessEpoch;
  final int catalogEpoch;
  final bool activeLayoutReady;

  const PublicMapHostSnapshot({
    required this.surfaceId,
    required this.styleEpoch,
    required this.readinessEpoch,
    required this.catalogEpoch,
    required this.activeLayoutReady,
  });

  String attemptKey(int requestId) =>
      '$requestId/$surfaceId/$styleEpoch/$catalogEpoch/$readinessEpoch';
}

final class PublicMapEffect {
  final int requestId;
  final MapIntent intent;
  final PublicMapHostSnapshot snapshot;

  const PublicMapEffect({
    required this.requestId,
    required this.intent,
    required this.snapshot,
  });
}

final class PublicMapHostResult {
  final MapFocusOutcome outcome;
  final bool retryable;

  const PublicMapHostResult._(this.outcome, {required this.retryable});

  PublicMapHostResult.applied(CameraApplyResult camera)
      : this._(MapFocusOutcome.applied(camera), retryable: false);

  PublicMapHostResult.unavailable([String? reason])
      : this._(MapFocusOutcome.unavailable(reason), retryable: false);

  PublicMapHostResult.failed([String? reason])
      : this._(MapFocusOutcome.failed(reason), retryable: false);

  PublicMapHostResult.retryable(String reason)
      : this._(MapFocusOutcome.failed(reason), retryable: true);
}

/// Renderer-neutral, mechanical boundary implemented by the retained map view.
abstract interface class PublicMapHost {
  PublicMapHostSnapshot get snapshot;

  Future<PublicMapHostResult> applyIntent(PublicMapEffect effect);

  /// Restores the retained public map to its canonical overview without
  /// replacing the native map surface.
  Future<void> resetToOverview();
}
