import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/last_administration_context.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/rights_service.dart';

abstract interface class UnitAdministrationAccess {
  Listenable get changes;
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
  Listenable get changes => RightsService.occasionLinkModelNotifier;
  @override
  bool get isSignedIn => AuthService.isLoggedIn();
  @override
  UnitModel? get currentUnit => RightsService.currentUnit();
  @override
  bool get hasOccasion => RightsService.currentOccasionId() != null;
  @override
  bool get canAccess => RightsService.isUnitEditorView();
  @override
  Future<void> load(int unitId, {required bool force}) async {
    await RightsService.updateAppData(
        unitId: unitId, force: force, refreshOffline: false);
    if (isSignedIn && currentUnit?.id == unitId && canAccess) {
      await LastAdministrationContext.instance.remember(AppConfig.organization,
          RightsService.currentUser()?.id, '/unit/$unitId/edit');
    }
  }

  @override
  Future<List<OccasionModel>> occasions(int unitId) =>
      DbOccasions.getAllOccasionsForEdit(unitId);
}
