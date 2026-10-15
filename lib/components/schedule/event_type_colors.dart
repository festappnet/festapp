import 'package:collection/collection.dart';
import 'package:flutter/painting.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/schedule_feature.dart';
import 'package:fstapp/theme_config.dart';

/// Schedule-specific feature lookup belongs beside program presentation.
/// Generic application themes have no dependency on rights, features or routes.
class EventTypeColors {
  static Color background(String? typeCode) {
    if (typeCode == null) {
      return ThemeConfig.appBarColor();
    }

    final feature = FeatureService.getFeatureDetails(FeatureConstants.schedule);

    if (feature is ScheduleFeature) {
      final scheduleFeature = feature;
      // Find the event type by its code
      final eventType = scheduleFeature.eventTypes
          .firstWhereOrNull((et) => et.code == typeCode);

      if (eventType != null) {
        return eventType.getColor();
      }
    }

    return ThemeConfig.appBarColor();
  }

  static Color foreground(String? type) {
    final Color backgroundColor = background(type);
    return ThemeConfig.textColorForBackground(backgroundColor);
  }
}
