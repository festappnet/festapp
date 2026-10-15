import 'feature.dart';
import 'feature_constants.dart';

class DepositFeature extends Feature {
  String? depositDeadline;
  int? depositDeadlineDays;
  String? metaSurchargeDescription;

  /// Mutually exclusive modes:
  ///   "real"    → payment-linked deposit (default)
  ///   "virtual" → visual-only meta doplatek (no payment impact, slevy allowed)
  String mode;

  DepositFeature({
    required super.code,
    super.isEnabled,
    super.title,
    super.description,
    this.depositDeadline,
    this.depositDeadlineDays,
    this.metaSurchargeDescription,
    String? mode,
  }) : mode = mode ?? FeatureConstants.depositModeReal;

  bool get isVirtualMode => mode == FeatureConstants.depositModeVirtual;
  bool get isRealMode => !isVirtualMode;

  factory DepositFeature.fromJson(Map<String, dynamic> json) {
    return DepositFeature(
      code: json[FeatureConstants.metaCode],
      isEnabled: json[FeatureConstants.metaIsEnabled] ?? false,
      depositDeadline: json[FeatureConstants.depositDeadline],
      depositDeadlineDays: json[FeatureConstants.depositDeadlineDays],
      metaSurchargeDescription: json[FeatureConstants.metaSurchargeDescription],
      mode: json[FeatureConstants.depositMode],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
      FeatureConstants.depositMode: mode,
    };
    if (isRealMode) {
      if (depositDeadline != null) {
        data[FeatureConstants.depositDeadline] = depositDeadline;
      }
      if (depositDeadlineDays != null) {
        data[FeatureConstants.depositDeadlineDays] = depositDeadlineDays;
      }
    } else {
      if (metaSurchargeDescription != null &&
          metaSurchargeDescription!.isNotEmpty) {
        data[FeatureConstants.metaSurchargeDescription] =
            metaSurchargeDescription;
      }
    }
    return data;
  }
}
