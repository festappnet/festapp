import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/last_administration_context.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/components/unit/unit_occasion_dashboard.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/rights_service.dart';

abstract interface class UnitAdministrationAccess {
  Listenable get changes;
  UnitOccasionDashboard? get dashboard;
  bool get isSignedIn;
  UnitModel? get currentUnit;
  bool get hasOccasion;
  bool get canAccess;
  Future<void> load(int unitId, {required bool force});
  Future<List<OccasionModel>> occasions(int unitId);
}

class RightsUnitAdministrationAccess implements UnitAdministrationAccess {
  const RightsUnitAdministrationAccess();
  @override
  UnitOccasionDashboard? get dashboard {
    final raw = RightsService.occasionLinkModel?.unitDashboard;
    if (raw == null) return null;
    final value = UnitOccasionDashboard.fromJson(raw);
    return value.unitId == currentUnit?.id ? value : null;
  }

  @override
  Listenable get changes => RightsService.occasionLinkModelNotifier;
  @override
  bool get isSignedIn => AuthService.isLoggedIn();
  @override
  UnitModel? get currentUnit => RightsService.currentUnit();
  @override
  bool get hasOccasion => RightsService.currentOccasionId() != null;
  @override
  bool get canAccess => RightsService.hasCapability(
    AuthorizationCapabilities.unitAdministrationRead,
  );
  @override
  Future<void> load(int unitId, {required bool force}) async {
    final pending = RightsService.pendingContextUpdate;
    // A departing/deleted occasion may fail its in-flight refresh. The new
    // unit route still needs its own authoritative, permission-checked load.
    final joined = pending != null && await pending.catchError((_) => false);
    // Reuse the authoritative refresh already in flight for this unit. A
    // different context still needs its own read before the page can use it.
    if (!joined || currentUnit?.id != unitId || hasOccasion) {
      await RightsService.updateAppData(
        unitId: unitId,
        force: true,
        refreshOffline: false,
      );
    }
    if (isSignedIn && currentUnit?.id == unitId && canAccess) {
      await LastAdministrationContext.instance.remember(
        AppConfig.organization,
        RightsService.currentUser()?.id,
        '/unit/$unitId/edit',
      );
    }
  }

  @override
  Future<List<OccasionModel>> occasions(int unitId) async {
    final value = dashboard;
    if (value == null || value.unitId != unitId) {
      throw StateError('Missing unit dashboard');
    }
    return value.occasions;
  }
}
