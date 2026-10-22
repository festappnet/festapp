import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';

/// Unit-scoped discovery gate projected by SQL. Sales have an independent gate.
abstract final class StripeFeature {
  static bool get canManage =>
      !RightsService.isDemoReadOnly &&
      (RightsService.occasionLinkModelNotifier.value?.unitUser?.isManager ??
          false);
  static bool get canActivate =>
      !RightsService.isDemoReadOnly &&
      RightsService.hasCapability(
          AuthorizationCapabilities.organizationSettingsWrite);
  static bool get visible =>
      !RightsService.isDemoReadOnly &&
      (RightsService.currentUnit()?.stripePreviewEnabled ?? false);
}
