import 'package:fstapp/services/time_helper.dart';

import 'feature.dart';
import 'feature_constants.dart';

/// Counseling feature configuration (plan 2026-07-10, decision R4).
///
/// The feature toggle itself is the "enable counseling" switch — there is no
/// separate `counseling_enabled` flag anymore. Speakers are core and never
/// gated; only the counseling flow depends on this feature.
///
/// Config (occasions.features "counseling" element):
///   counseling_event_type    — event type code used for generated slots
///   registration_start_time  — own booking window for counseling slots
///   max_active_bookings      — max future counseling reservations per user
///                              (default 1, 0 = unlimited)
class CounselingFeature extends Feature {
  String counselingEventType;
  DateTime? registrationStartTime;
  int maxActiveBookings;

  CounselingFeature({
    super.code = FeatureConstants.counseling,
    super.isEnabled = false,
    super.title,
    super.description,
    this.counselingEventType = FeatureConstants.counselingDefaultEventType,
    this.registrationStartTime,
    this.maxActiveBookings = 1,
  });

  factory CounselingFeature.fromJson(Map<String, dynamic> json) {
    DateTime? parsed;
    final rawStart = json[FeatureConstants.counselingRegistrationStartTime];
    if (rawStart != null) {
      parsed = DateTime.parse(rawStart as String).toUtcFromOccasionTime();
    }
    final rawType = json[FeatureConstants.counselingEventType] as String?;
    return CounselingFeature(
      code: json[FeatureConstants.metaCode] as String? ??
          FeatureConstants.counseling,
      isEnabled: json[FeatureConstants.metaIsEnabled] as bool? ?? false,
      counselingEventType: (rawType != null && rawType.isNotEmpty)
          ? rawType
          : FeatureConstants.counselingDefaultEventType,
      registrationStartTime: parsed,
      maxActiveBookings:
          (json[FeatureConstants.counselingMaxActiveBookings] as num?)
                  ?.toInt() ??
              1,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
      FeatureConstants.counselingEventType: counselingEventType,
      FeatureConstants.counselingMaxActiveBookings: maxActiveBookings,
    };
    if (registrationStartTime != null) {
      data[FeatureConstants.counselingRegistrationStartTime] =
          registrationStartTime!.toIso8601String();
    }
    return data;
  }
}
