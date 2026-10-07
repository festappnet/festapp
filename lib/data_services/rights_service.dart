import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_model.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/data_services/update_service.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/synchro_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/components/occasion/link_model.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/organization/organization_model.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';

class RightsService {
  static final _supabase = Supabase.instance.client;

  // The model is now wrapped in a ValueNotifier.
  static final occasionLinkModelNotifier =
      ValueNotifier<OccasionLinkModel?>(null);
  static OccasionLinkModel? get occasionLinkModel =>
      occasionLinkModelNotifier.value;

  // All getters now read from the notifier's current value.
  static UserInfoModel? currentUser() =>
      occasionLinkModelNotifier.value?.userInfo;
  static OccasionUserModel? currentOccasionUser() =>
      occasionLinkModelNotifier.value?.occasionUser;
  static OccasionUserModel? currentUnitUser() =>
      occasionLinkModelNotifier.value?.unitUser;
  static int? currentOccasionId() =>
      occasionLinkModelNotifier.value?.occasion?.id;
  static OccasionModel? currentOccasion() =>
      occasionLinkModelNotifier.value?.occasion;
  static UnitModel? currentUnit() => occasionLinkModelNotifier.value?.unit;

  static String? currentLink;
  static bool useOfflineVersion = false;

  static List<int>? bankAccountAdmin() =>
      occasionLinkModelNotifier.value?.bankAccountsAdmin;

  // Serializes concurrent updateAppData calls to prevent state interleaving.
  static Future<bool> _lastUpdate = Future.value(true);

  static Future<bool> updateAppData(
      {int? unitId,
      String? link,
      bool force = false,
      bool refreshOffline = AppConfig.isAppSupported,
      String? formLink}) {
    final previous = _lastUpdate;
    final current = previous.catchError((_) => false).then((_) =>
        _doUpdateAppData(
            unitId: unitId,
            link: link,
            force: force,
            refreshOffline: refreshOffline,
            formLink: formLink));
    _lastUpdate = current;
    return current;
  }

  static Future<bool> _doUpdateAppData(
      {int? unitId,
      String? link,
      bool force = false,
      bool refreshOffline = AppConfig.isAppSupported,
      String? formLink}) async {
    // Check if an update is needed
    // Logic: If force is true, update.
    // If unitId is specified (Unit Admin mode), only update if we aren't already on that unit.
    // Otherwise (Occasion mode), update if we don't have an occasion or the link changed.
    bool needsUpdate = force;
    if (!needsUpdate) {
      if (unitId != null) {
        if (occasionLinkModelNotifier.value?.unit?.id != unitId) {
          needsUpdate = true;
        }
      } else if (occasionLinkModelNotifier.value?.occasion?.id == null ||
          link != currentLink) {
        needsUpdate = true;
      }
    }

    if (needsUpdate) {
      LinkModel model =
          LinkModel(occasionLink: link, unitId: unitId, formLink: formLink);
      if (unitId == null) {
        var occasionLink = link ?? RouterService.currentOccasionLink;
        if (occasionLink.isEmpty) {
          model = LinkModel.extractOccasionLink(Uri.base.toString());
        }
      }

      // A tenant landing occasion must not replace an explicit admin context.
      if (unitId == null &&
          (link == null || link.isEmpty) &&
          AppConfig.forceOccasionLink != null) {
        model.occasionLink = AppConfig.forceOccasionLink;
      }

      // Get the new data
      var checkedObject = await SynchroService.getAppConfig(model);

      // Update global state from the fetched object
      RightsService.currentLink = checkedObject.occasion?.link;
      UpdateService.configurePlatforms(checkedObject.organization?.platforms);

      // Handle access denied or not found cases
      if (checkedObject.isAccessDenied() || checkedObject.isNotFound()) {
        occasionLinkModelNotifier.value =
            checkedObject; // Update with error state to notify UI
        throw Exception("Cannot continue. Access denied or not found.");
      }

      // This is the key change: update the notifier's value,
      // which will automatically alert any listening widgets.
      occasionLinkModelNotifier.value = checkedObject;
      await ClientSyncRuntime.bootstrap(checkedObject);

      // Update other dependent services
      TimeHelper.setTimeZoneLocation(
          RightsService.currentOccasion()?.data?["timezone"]);
      RouterService.currentOccasionLink = currentLink ?? "";

      if (occasionLinkModel?.occasion != null) {
        var globalSettings =
            OccasionSettingsModel.fromOccasion(occasionLinkModel!.occasion!);
        SynchroService.globalSettingsModel = globalSettings;
        await OfflineDataService.saveGlobalSettings(globalSettings);
        if (refreshOffline && !ClientSyncRuntime.isV1Selected) {
          await SynchroService.refreshOfflineData();
        }
      } else {
        SynchroService.globalSettingsModel =
            OccasionSettingsModel.defaultSettings;
      }
    }
    return true;
  }

  static Future<bool> getIsAdmin() async {
    var data = await _supabase.rpc("get_is_admin_on_occasion",
        params: {"oc": RightsService.currentOccasionId()!});
    return data;
  }

  static bool canSeeAdmin() {
    return isEditor() || isManager() || isUnitEditorView() || isAdmin();
  }

  static bool canUpdateUsers() {
    return isManager() || isAdmin() || isUnitEditor();
  }

  static bool canUpdateOrders() {
    return isEditorOrder() || isAdmin() || isUnitEditor();
  }

  /// Whether the current user is on the cleaning crew — the per-occasion
  /// is_cleaning_crew flag ONLY. Editors/admins are deliberately NOT treated as
  /// implicit crew: only actual crew receive the report push notifications, so
  /// only they should see the crew section on the Cleaning page (tabs, reports,
  /// "Cleaned", the notification opt-out). The backend get_cleaning_reports /
  /// resolve_cleaning_place still permit editors for oversight, but the UI is
  /// intentionally stricter.
  static bool isCleaningCrew() {
    return occasionLinkModelNotifier.value?.occasionUser?.isCleaningCrew ??
        false;
  }

  static bool isReceptionist() =>
      occasionLinkModelNotifier.value?.occasionUser?.isReceptionist ?? false;

  static bool canManageReceptionParticipants() => isManager() || isAdmin();

  static bool canUseReception() =>
      FeatureService.isFeatureEnabled(FeatureConstants.reception) &&
      (isReceptionist() || isManager() || isAdmin());

  static bool canSeeUnitUsers() {
    return isUnitEditor() || isUnitManager() || isAdmin();
  }

  static bool canUpdateUnitUsers() {
    return isUnitManager() || isAdmin();
  }

  static bool canEditOccasion() {
    return isManager() || isEditor();
  }

  static bool canSignInOutUsersFromEvents() {
    return currentOccasionUser()?.isEditor ?? false;
  }

  static bool canSeeReservations() {
    return isUnitEditorView() || isEditorOrderView();
  }

  static bool canSeeAdministration() {
    return isUnitEditorView() || isEditorView();
  }

  static bool isAdmin() {
    return occasionLinkModelNotifier.value?.isAdmin ?? false;
  }

  static bool isEditor() {
    return occasionLinkModelNotifier.value?.occasionUser?.isEditor ?? false;
  }

  static bool isEditorView() {
    return occasionLinkModelNotifier.value?.occasionUser?.isEditorView ?? false;
  }

  static bool isOrderEditor() {
    return occasionLinkModelNotifier.value?.occasionUser?.isEditorOrder ??
        false;
  }

  static bool isUnitEditor() {
    return occasionLinkModelNotifier.value?.unitUser?.isEditor ?? false;
  }

  static bool isUnitEditorView() {
    return occasionLinkModelNotifier.value?.unitUser?.isEditorView ?? false;
  }

  static bool isEditorOrderView() {
    return occasionLinkModelNotifier.value?.occasionUser?.isEditorOrderView ??
        false;
  }

  static bool isEditorOrder() {
    return occasionLinkModelNotifier.value?.occasionUser?.isEditorOrder ??
        false;
  }

  static bool canUserSeeUnitWorkspace() {
    if (currentUser()?.units?.any((u) => u.id == currentUnit()?.id) ?? false) {
      return true;
    }
    return isUnitEditor() || isUnitManager() || isUnitEditorView();
  }

  static bool isManager() {
    return occasionLinkModelNotifier.value?.occasionUser?.isManager ?? false;
  }

  static bool isUnitManager() {
    return occasionLinkModelNotifier.value?.unitUser?.isManager ?? false;
  }

  static bool isApprover() {
    return occasionLinkModelNotifier.value?.occasionUser?.isApprover ?? false;
  }

  static bool hasGroup() {
    return (currentUser()?.userGroups?.length ?? 0) > 0;
  }

  static bool isGroupAdmin() {
    return currentUser()?.userGroups?.any((g) => g.isAdmin ?? false) ?? false;
  }

  static UserGroupInfoModel? currentUserGroup() {
    return currentUser()?.userGroups?.firstWhereOrNull((g) => g.type == null);
  }

  static void updateOrganizationLocally(OrganizationModel newOrg) {
    var valid = occasionLinkModelNotifier.value;
    if (valid != null) {
      // Create shallow copy to trigger ValueNotifier
      occasionLinkModelNotifier.value = OccasionLinkModel(
        code: valid.code,
        userInfo: valid.userInfo,
        occasionUser: valid.occasionUser,
        unitUser: valid.unitUser,
        bankAccountsAdmin: valid.bankAccountsAdmin,
        occasion: valid.occasion,
        unit: valid.unit,
        isAdmin: valid.isAdmin,
        organization: newOrg,
        clientSyncV1: valid.clientSyncV1,
      );
    }
  }
}
