import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/services_feature.dart';

void main() {
  group('ServicesFeature defaults', () {
    test('new feature defaults to stay mode with both sub-types allowed', () {
      final f = ServicesFeature(code: FeatureConstants.services);
      expect(f.isStayMode, isTrue);
      expect(f.isCapacityGroupsMode, isFalse);
      expect(f.allowsAccommodation, isTrue);
      expect(f.allowsFood, isTrue);
      expect(f.allowsCapacityGroups, isFalse);
    });

    test('legacy JSON without a mode decodes as stay mode', () {
      final f = ServicesFeature.fromJson({
        FeatureConstants.metaCode: FeatureConstants.services,
        FeatureConstants.metaIsEnabled: true,
      });
      expect(f.isEnabled, isTrue);
      expect(f.isStayMode, isTrue);
      expect(f.allowsAccommodation, isTrue);
      expect(f.allowsFood, isTrue);
    });
  });

  group('ServicesFeature mode exclusivity', () {
    test('capacity-groups mode disallows accommodation and food', () {
      final f = ServicesFeature(
        code: FeatureConstants.services,
        mode: FeatureConstants.servicesModeCapacityGroups,
        allowAccommodation: true,
        allowFood: true,
      );
      expect(f.allowsCapacityGroups, isTrue);
      // Sub-toggles are irrelevant outside stay mode.
      expect(f.allowsAccommodation, isFalse);
      expect(f.allowsFood, isFalse);
    });

    test('stay mode honours the independent sub-toggles', () {
      final foodOnly = ServicesFeature(
        code: FeatureConstants.services,
        allowAccommodation: false,
        allowFood: true,
      );
      expect(foodOnly.allowsAccommodation, isFalse);
      expect(foodOnly.allowsFood, isTrue);
      expect(foodOnly.allowsCapacityGroups, isFalse);
    });
  });

  group('ServicesFeature round-trip', () {
    test('stay mode persists sub-toggles', () {
      final original = ServicesFeature(
        code: FeatureConstants.services,
        isEnabled: true,
        allowAccommodation: true,
        allowFood: false,
      );
      final decoded = Feature.fromJson(original.toJson()) as ServicesFeature;
      expect(decoded.mode, FeatureConstants.servicesModeStay);
      expect(decoded.allowAccommodation, isTrue);
      expect(decoded.allowFood, isFalse);
    });

    test('capacity-groups mode omits sub-toggles from JSON', () {
      final original = ServicesFeature(
        code: FeatureConstants.services,
        isEnabled: true,
        mode: FeatureConstants.servicesModeCapacityGroups,
      );
      final json = original.toJson();
      expect(json.containsKey(FeatureConstants.servicesAllowAccommodation),
          isFalse);
      expect(json.containsKey(FeatureConstants.servicesAllowFood), isFalse);

      final decoded = Feature.fromJson(json) as ServicesFeature;
      expect(decoded.isCapacityGroupsMode, isTrue);
    });

    test('Feature.fromJson dispatches services code to ServicesFeature', () {
      final decoded = Feature.fromJson({
        FeatureConstants.metaCode: FeatureConstants.services,
        FeatureConstants.metaIsEnabled: false,
      });
      expect(decoded, isA<ServicesFeature>());
    });
  });
}
