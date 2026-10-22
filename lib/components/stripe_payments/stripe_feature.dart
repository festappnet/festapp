import 'package:fstapp/data_services/rights_service.dart';

/// Hidden preview only. SQL runtime policy independently authorizes new sales.
abstract final class StripeFeature {
  static bool get canManage => !RightsService.isDemoReadOnly &&
      (RightsService.occasionLinkModelNotifier.value?.unitUser?.isManager ?? false);
  static const visible =
      bool.fromEnvironment('FESTAPP_STRIPE_PREVIEW', defaultValue: false);
}
