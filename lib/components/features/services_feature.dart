import 'feature.dart';
import 'feature_constants.dart';

/// Feature backing the "Pobyt (kapacitní skupiny)" / Inventory module.
///
/// Lets an occasion decide which kinds of capacity groups are allowed. The two
/// top-level modes are mutually exclusive:
///   * [FeatureConstants.servicesModeStay] – accommodation and/or food pools.
///   * [FeatureConstants.servicesModeCapacityGroups] – generic capacity groups
///     only (the `other` pool type).
///
/// Within stay mode, accommodation and food are independently toggleable.
class ServicesFeature extends Feature {
  String mode;
  bool allowAccommodation;
  bool allowFood;

  ServicesFeature({
    required super.code,
    super.isEnabled,
    super.title,
    super.description,
    String? mode,
    bool? allowAccommodation,
    bool? allowFood,
  })  : mode = mode ?? FeatureConstants.servicesModeStay,
        allowAccommodation = allowAccommodation ?? true,
        allowFood = allowFood ?? true;

  bool get isCapacityGroupsMode =>
      mode == FeatureConstants.servicesModeCapacityGroups;
  bool get isStayMode => !isCapacityGroupsMode;

  /// Accommodation is offered only in stay mode when its sub-toggle is on.
  bool get allowsAccommodation => isStayMode && allowAccommodation;

  /// Food is offered only in stay mode when its sub-toggle is on.
  bool get allowsFood => isStayMode && allowFood;

  /// Generic capacity groups are offered only in capacity-groups mode.
  bool get allowsCapacityGroups => isCapacityGroupsMode;

  factory ServicesFeature.fromJson(Map<String, dynamic> json) {
    return ServicesFeature(
      code: json[FeatureConstants.metaCode],
      isEnabled: json[FeatureConstants.metaIsEnabled] ?? false,
      mode: json[FeatureConstants.servicesMode],
      allowAccommodation: json[FeatureConstants.servicesAllowAccommodation],
      allowFood: json[FeatureConstants.servicesAllowFood],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
      FeatureConstants.servicesMode: mode,
    };
    if (isStayMode) {
      data[FeatureConstants.servicesAllowAccommodation] = allowAccommodation;
      data[FeatureConstants.servicesAllowFood] = allowFood;
    }
    return data;
  }
}
