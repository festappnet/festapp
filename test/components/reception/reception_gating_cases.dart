import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

OccasionModel _occasion(bool enabled) => OccasionModel(
      id: 42,
      isOpen: true,
      isHidden: false,
      isPromoted: false,
      features: [
        SimpleFeature(code: FeatureConstants.reception, isEnabled: enabled),
      ],
    );

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  tearDown(() => RightsService.occasionLinkModelNotifier.value = null);

  test('feature off denies an explicitly assigned receptionist', () {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasion: _occasion(false),
      occasionUser: OccasionUserModel(isReceptionist: true),
    );
    expect(RightsService.isReceptionist(), isTrue);
    expect(RightsService.canUseReception(), isFalse);
  });

  test('enabled feature permits receptionist and manager oversight', () {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasion: _occasion(true),
      occasionUser: OccasionUserModel(isReceptionist: true),
    );
    expect(RightsService.canUseReception(), isTrue);

    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasion: _occasion(true),
      occasionUser: OccasionUserModel(isManager: true),
    );
    expect(RightsService.isReceptionist(), isFalse);
    expect(RightsService.canUseReception(), isTrue);
    expect(RightsService.canManageReceptionParticipants(), isTrue);
  });

  test('receptionist cannot browse existing occasion participants', () {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasion: _occasion(true),
      occasionUser: OccasionUserModel(isReceptionist: true),
    );

    expect(RightsService.canManageReceptionParticipants(), isFalse);
  });

  test('production app-config shape exposes an assigned receptionist', () {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel.fromJson({
      'code': 200,
      'client_sync_v1': true,
      'occasion': {
        'id': 643,
        'link': 'csmostrava2026',
        'features': [
          {'code': 'reception', 'is_enabled': true},
        ],
      },
      'occasion_user': {
        'occasion': 643,
        'user': 'e03394ac-8995-4dac-bf15-af32f86eeb03',
        'is_receptionist': true,
        'is_manager': false,
      },
    });

    expect(RightsService.isReceptionist(), isTrue);
    expect(RightsService.canUseReception(), isTrue);
  });
}
