import 'dart:math';

import 'package:festapp_core/sync.dart';

typedef SyncClock = DateTime Function();

class SyncPollingPolicy {
  SyncPollingPolicy({Random? random}) : _random = random ?? Random.secure();

  static const publicFreshness = Duration(seconds: 15);
  static const privateFreshness = Duration(seconds: 60);
  static const maximumBackoff = Duration(minutes: 5);

  final Random _random;

  Duration nextTickDelay() =>
      publicFreshness + Duration(milliseconds: _random.nextInt(3001));

  bool publicIsDue(
    DateTime now,
    DateTime? lastSuccess, {
    required bool missingRequiredData,
    required SyncReason reason,
  }) =>
      missingRequiredData ||
      lastSuccess == null ||
      now.difference(lastSuccess) >= publicFreshness ||
      reason == SyncReason.bootstrap ||
      reason == SyncReason.reconnect ||
      reason == SyncReason.resume;

  bool privateIsDue(
    DateTime now,
    DateTime? lastSuccess, {
    required bool privateConsumer,
    required SyncReason reason,
  }) =>
      privateConsumer &&
      (lastSuccess == null ||
          now.difference(lastSuccess) >= privateFreshness ||
          reason == SyncReason.bootstrap ||
          reason == SyncReason.login ||
          reason == SyncReason.reconnect ||
          reason == SyncReason.resume);

  Duration backoffForFailure(int consecutiveFailures) {
    final seconds = 15 * (1 << consecutiveFailures.clamp(0, 4));
    return Duration(seconds: min(seconds, maximumBackoff.inSeconds));
  }
}
