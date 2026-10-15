import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/counseling_feature.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';

/// Gating unit tests for the counseling feature. Speakers are core (never
/// gated); only the counseling flow depends on the "counseling" feature.
/// [FeatureService.isCounselingEnabled] is a pure feature check (decision R4),
/// exercised here via injected feature lists (no RightsService context needed).
void main() {
  group('FeatureService.isCounselingEnabled', () {
    test('true when the counseling feature element is enabled', () {
      final features = [
        CounselingFeature(code: FeatureConstants.counseling, isEnabled: true),
      ];
      expect(FeatureService.isCounselingEnabled(features: features), isTrue);
    });

    test('false when the counseling feature is present but disabled', () {
      final features = [
        CounselingFeature(code: FeatureConstants.counseling, isEnabled: false),
      ];
      expect(FeatureService.isCounselingEnabled(features: features), isFalse);
    });

    test('false when the counseling feature is absent', () {
      final features = [
        SimpleFeature(code: FeatureConstants.map, isEnabled: true),
      ];
      expect(FeatureService.isCounselingEnabled(features: features), isFalse);
    });

    test('a legacy "speakers" element alone does NOT enable counseling', () {
      final features = [
        SimpleFeature(code: 'speakers', isEnabled: true),
      ];
      expect(FeatureService.isCounselingEnabled(features: features), isFalse);
    });

    test('getCounselingFeature returns the typed config when present', () {
      final features = [
        CounselingFeature(
          code: FeatureConstants.counseling,
          isEnabled: true,
          counselingEventType: 'poradna',
          maxActiveBookings: 0,
        ),
      ];
      final f = FeatureService.getCounselingFeature(features: features);
      expect(f, isNotNull);
      expect(f!.counselingEventType, 'poradna');
      expect(f.maxActiveBookings, 0);
    });
  });
}
