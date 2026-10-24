// form_feature.dart
import 'package:fstapp/app_config.dart'; // Import AppConfig
import 'feature.dart';
import 'feature_constants.dart';

const int _secondsInADay = 86400;
const int _secondsInAWeek = _secondsInADay * 7;

/// Feature for external form & custom button title.
class FormFeature extends Feature {
  bool? formUseExternal;
  String? formExternalLink;
  String? formExternalPrice;
  String? reserveButtonTitle;
  bool? reminderIsEnabled;
  int? reminderIntervalSeconds;
  int? deadlineDurationSeconds;

  FormFeature({
    required super.code,
    bool? isEnabled, // Make this a normal parameter, not 'super.isEnabled'
    super.title,
    super.description,
    this.formUseExternal,
    this.formExternalLink,
    this.formExternalPrice,
    this.reserveButtonTitle,
    this.reminderIsEnabled,
    this.deadlineDurationSeconds,
    this.reminderIntervalSeconds,
  }) : super(
          // Pass the processed value to the super constructor.
          // This is the new centralized logic.
          isEnabled: (!AppConfig.isAppSupported) ? true : (isEnabled ?? false),
        );

  /// This feature can only be disabled if the app is supported.
  @override
  bool get canBeDisabled => AppConfig.isAppSupported;

  factory FormFeature.fromJson(Map<String, dynamic> json) {
    // This factory is now simpler. It just passes the JSON value
    // to the main constructor, which will handle the logic.
    return FormFeature(
      code: json[FeatureConstants.metaCode],
      isEnabled:
          json[FeatureConstants.metaIsEnabled], // Let the constructor handle it
      formUseExternal: json[FeatureConstants.formUseExternal],
      formExternalLink: json[FeatureConstants.formExternalLink],
      formExternalPrice: json[FeatureConstants.formExternalPrice],
      reserveButtonTitle: json[FeatureConstants.reserveButtonTitle],
      reminderIsEnabled: json[FeatureConstants.reminderIsEnabled] ?? true,
      reminderIntervalSeconds:
          json[FeatureConstants.reminderIntervalSeconds] ?? _secondsInADay,
      deadlineDurationSeconds:
          json[FeatureConstants.deadlineDurationSeconds] ?? _secondsInAWeek,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final bool mustBeEnabled = !AppConfig.isAppSupported;

    final data = {
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: mustBeEnabled ? true : isEnabled,
    };
    if (formUseExternal != null)
      data[FeatureConstants.formUseExternal] = formUseExternal!;
    if (formExternalLink != null)
      data[FeatureConstants.formExternalLink] = formExternalLink!;
    if (formExternalPrice != null)
      data[FeatureConstants.formExternalPrice] = formExternalPrice!;
    if (reserveButtonTitle != null)
      data[FeatureConstants.reserveButtonTitle] = reserveButtonTitle!;
    if (reminderIsEnabled != null)
      data[FeatureConstants.reminderIsEnabled] = reminderIsEnabled!;
    if (reminderIntervalSeconds != null)
      data[FeatureConstants.reminderIntervalSeconds] = reminderIntervalSeconds!;
    if (deadlineDurationSeconds != null)
      data[FeatureConstants.deadlineDurationSeconds] = deadlineDurationSeconds!;
    return data;
  }
}
