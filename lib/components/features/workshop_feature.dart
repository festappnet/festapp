import 'package:fstapp/services/time_helper.dart';

import 'feature.dart';
import 'feature_constants.dart';

/// Feature for a workshop registration start time.
class WorkshopsFeature extends Feature {
  static const String metaStartTime = 'start_time';
  static const String metaWorkshops = 'workshops';
  static const String metaRegistrationNotOpenMessage =
      'registration_not_open_message';

  DateTime? startTime;
  String? registrationNotOpenMessage;

  WorkshopsFeature({
    super.code = metaWorkshops,
    super.isEnabled = true,
    super.title,
    super.description,
    this.startTime,
    this.registrationNotOpenMessage,
  });

  factory WorkshopsFeature.fromJson(Map<String, dynamic> json) {
    DateTime? parsed;
    if (json[metaStartTime] != null) {
      parsed =
          DateTime.parse(json[metaStartTime] as String).toUtcFromOccasionTime();
    }
    return WorkshopsFeature(
      code: json[FeatureConstants.metaCode] as String? ?? metaWorkshops,
      isEnabled: json[FeatureConstants.metaIsEnabled] as bool? ?? true,
      startTime: parsed,
      registrationNotOpenMessage:
          json[metaRegistrationNotOpenMessage] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
    };
    if (startTime != null) {
      data[metaStartTime] = startTime!.toIso8601String();
    }
    if (registrationNotOpenMessage != null) {
      data[metaRegistrationNotOpenMessage] = registrationNotOpenMessage;
    }
    return data;
  }

  /// Builds the form field for this feature in FeatureForm.
}
