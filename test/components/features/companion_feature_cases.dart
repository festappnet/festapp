import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/companion_feature.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';

void main() {
  test('legacy JSON keeps self-create and does not enable admin assignment',
      () {
    final feature = CompanionsFeature.fromJson({
      FeatureConstants.metaCode: FeatureConstants.companions,
      FeatureConstants.metaIsEnabled: true,
      FeatureConstants.companionsMax: 2,
    });
    expect(feature.allowUserCreate, isTrue);
    expect(feature.allowAdminAssign, isFalse);
    expect(FeatureService.allowsUserCompanionCreation(features: [feature]),
        isTrue);
    expect(FeatureService.allowsAdminCompanionAssignment(features: [feature]),
        isFalse);
  });

  test('capabilities round-trip and master gate wins', () {
    final original = CompanionsFeature(
      code: FeatureConstants.companions,
      isEnabled: false,
      companionsMax: 3,
      allowUserCreate: true,
      allowAdminAssign: true,
    );
    final decoded = Feature.fromJson(original.toJson()) as CompanionsFeature;
    expect(decoded.companionsMax, 3);
    expect(decoded.allowUserCreate, isTrue);
    expect(decoded.allowAdminAssign, isTrue);
    expect(FeatureService.allowsUserCompanionCreation(features: [decoded]),
        isFalse);
    expect(FeatureService.allowsAdminCompanionAssignment(features: [decoded]),
        isFalse);
  });

  test('maximum is clamped to the server-side minimum', () {
    final feature = CompanionsFeature(
      code: FeatureConstants.companions,
      isEnabled: true,
      companionsMax: 0,
    );

    expect(FeatureService.getMaxCompanions(features: [feature]), 1);
  });
}
