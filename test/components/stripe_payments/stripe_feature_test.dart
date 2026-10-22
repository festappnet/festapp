import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/stripe_payments/stripe_feature.dart';
import 'package:fstapp/data_services/rights_service.dart';

void main() {
  tearDown(() => RightsService.occasionLinkModelNotifier.value = null);
  test('unit SQL projection defaults hidden and changes with context', () {
    RightsService.occasionLinkModelNotifier.value =
        OccasionLinkModel(unit: UnitModel(id: 8));
    expect(StripeFeature.visible, isFalse);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        unit: UnitModel.fromJson({'id': 8, 'stripe_preview_enabled': true}),
        unitUser: OccasionUserModel(isManager: true));
    expect(StripeFeature.visible, isTrue);
    expect(StripeFeature.canManage, isTrue);
    expect(StripeFeature.canActivate, isFalse);
    RightsService.occasionLinkModelNotifier.value =
        OccasionLinkModel(unit: UnitModel(id: 9));
    expect(StripeFeature.visible, isFalse);
  });
  test('only tenant admin can activate and demo remains hidden', () {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        unit: UnitModel(id: 8, stripePreviewEnabled: true),
        capabilities: const {'organization.settings.write': true});
    expect(StripeFeature.canActivate, isTrue);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        unit: UnitModel(id: 8, stripePreviewEnabled: true),
        demoReadOnly: true,
        capabilities: const {'organization.settings.write': true});
    expect(StripeFeature.visible, isFalse);
    expect(StripeFeature.canActivate, isFalse);
    RightsService.occasionLinkModelNotifier.value = null;
    expect(StripeFeature.visible, isFalse);
    expect(StripeFeature.canActivate, isFalse);
  });
}
