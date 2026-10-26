// companions_feature.dart
import 'feature.dart';
import 'feature_constants.dart';

/// Feature for companions with a max count.
class CompanionsFeature extends Feature {
  int? companionsMax;
  bool allowUserCreate;
  bool allowAdminAssign;

  CompanionsFeature({
    required super.code,
    super.isEnabled,
    super.title,
    super.description,
    this.companionsMax,
    this.allowUserCreate = true,
    this.allowAdminAssign = false,
  });

  factory CompanionsFeature.fromJson(Map<String, dynamic> json) {
    return CompanionsFeature(
      code: json[FeatureConstants.metaCode],
      isEnabled: json[FeatureConstants.metaIsEnabled] ?? false,
      companionsMax: json[FeatureConstants.companionsMax],
      allowUserCreate:
          json[FeatureConstants.companionsAllowUserCreate] as bool? ?? true,
      allowAdminAssign:
          json[FeatureConstants.companionsAllowAdminAssign] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = {
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
    };
    if (companionsMax != null) {
      data[FeatureConstants.companionsMax] = companionsMax!;
    }
    data[FeatureConstants.companionsAllowUserCreate] = allowUserCreate;
    data[FeatureConstants.companionsAllowAdminAssign] = allowAdminAssign;
    return data;
  }

  /// Builds the companions UI block.
}
