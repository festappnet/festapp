import 'package:fstapp/services/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
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
import 'package:fstapp/components/organization/organization_model.dart';

class RightsService {
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
  static int? currentOccasionId() =>
      occasionLinkModelNotifier.value?.occasion?.id;
  static OccasionModel? currentOccasion() =>
      occasionLinkModelNotifier.value?.occasion;
  static UnitModel? currentUnit() => occasionLinkModelNotifier.value?.unit;

  static String? currentLink;
  static bool useOfflineVersion = false;

  static bool hasBankCapability(int? accountId, String id) =>
      accountId != null &&
      occasionLinkModel?.capabilities.isNotEmpty == true &&
      occasionLinkModel?.bankCapabilities[accountId]?[id] == true;

  static List<int> banksWithCapability(String id) =>
      occasionLinkModel?.capabilities.isNotEmpty != true
          ? const []
          : occasionLinkModel!.bankCapabilities.entries
              .where((entry) => entry.value[id] == true)
              .map((entry) => entry.key)
              .toList(growable: false);

  // Serializes concurrent updateAppData calls to prevent state interleaving.
  static Future<bool> _lastUpdate = Future.value(true);
  static int _contextGeneration = 0;

  static Future<bool> updateAppData(
      {int? unitId,
      String? link,
      bool force = false,
      bool refreshOffline = AppConfig.isAppSupported,
      String? formLink}) {
    final contextGeneration = ++_contextGeneration;
    if (force ||
        (unitId != null && unitId != currentUnit()?.id) ||
        (link != null && link != currentLink) ||
        formLink != null) {
      invalidateCapabilities();
    }
    final previous = _lastUpdate;
    final current = previous.catchError((_) => false).then((_) =>
        _doUpdateAppData(
            contextGeneration: contextGeneration,
            unitId: unitId,
            link: link,
            force: force,
            refreshOffline: refreshOffline,
            formLink: formLink));
    _lastUpdate = current;
    return current;
  }

  static Future<bool> _doUpdateAppData(
      {required int contextGeneration,
      int? unitId,
      String? link,
      bool force = false,
      bool refreshOffline = AppConfig.isAppSupported,
      String? formLink}) async {
    if (contextGeneration != _contextGeneration) return false;
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
      if (unitId == null &&
          (link == null || link.isEmpty) &&
          (formLink == null || formLink.isEmpty)) {
        model = LinkModel.extractOccasionLink(
            RouterService.getCurrentBrowserUri().toString());
      }

      // Resolve an explicit public/admin path before applying a tenant landing
      // default, including when an older context was restored from offline data.
      if (unitId == null &&
          (model.occasionLink?.isEmpty ?? true) &&
          (model.formLink?.isEmpty ?? true) &&
          AppConfig.forceOccasionLink != null) {
        model.occasionLink = AppConfig.forceOccasionLink;
      }

      // Get the new data
      final identity = _capabilityIdentity;
      final actor = Supabase.instance.client.auth.currentUser?.id;
      final organization = AppConfig.organization;
      var checkedObject = await SynchroService.getAppConfig(model);
      if (contextGeneration != _contextGeneration ||
          organization != AppConfig.organization ||
          identity != _capabilityIdentity ||
          actor != Supabase.instance.client.auth.currentUser?.id) {
        return false;
      }

      // Update global state from the fetched object
      RightsService.currentLink = checkedObject.occasion?.link;
      UpdateService.configurePlatforms(checkedObject.organization?.platforms);

      // Handle access denied or not found cases
      if (checkedObject.isAccessDenied() || checkedObject.isNotFound()) {
        occasionLinkModelNotifier.value =
            checkedObject; // Update with error state to notify UI
        throw Exception("Cannot continue. Access denied or not found.");
      }

      RouterService.canonicalizePublicLink(
          'occasion', model.occasionLink, checkedObject.occasion?.link);
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
        if (!checkedObject.demoReadOnly) {
          await OfflineDataService.saveGlobalSettings(globalSettings);
        }
        if (refreshOffline &&
            !checkedObject.demoReadOnly &&
            !ClientSyncRuntime.isV1Selected) {
          await SynchroService.refreshOfflineData();
        }
      } else {
        SynchroService.globalSettingsModel =
            OccasionSettingsModel.defaultSettings;
      }
    }
    return true;
  }

  static bool canSeeAdmin() =>
      hasCapability(AuthorizationCapabilities.navigationAdminApp);

  static int _capabilityIdentity = 0;
  static void invalidateCapabilities({bool clearIdentity = false}) {
    _capabilityIdentity++;
    final context = occasionLinkModel;
    if (context != null &&
        (clearIdentity ||
            (context.capabilities.isNotEmpty ||
                context.bankCapabilities.isNotEmpty))) {
      final invalidated =
          context.copyWith(capabilities: const {}, bankCapabilities: const {});
      if (clearIdentity) {
        invalidated.occasionUser = null;
        invalidated.unitUser = null;
        invalidated.userInfo = null;
        invalidated.bankAccountsAdmin = null;
        invalidated.isAdmin = false;
      }
      occasionLinkModelNotifier.value = invalidated;
    }
  }

  static bool _authorizationRefreshing = false;
  static final _handledAuthorizationDenials = Expando<bool>();

  /// A rejection discards the informative snapshot before any further UI action.
  /// Refreshes share the normal context RPC and never retry the denied mutation.
  static Future<void> refreshAfterAuthorizationDenial(
      {Exception? error}) async {
    // The transport and UI can see the same exception. Refresh once for that
    // response; a later failed request carries a new exception and checks again.
    if (error != null) {
      if (_handledAuthorizationDenials[error] == true) return;
      _handledAuthorizationDenials[error] = true;
    }
    if (_authorizationRefreshing || occasionLinkModel == null) return;
    _authorizationRefreshing = true;
    try {
      await refreshAfterAuthorizationChange();
    } finally {
      _authorizationRefreshing = false;
    }
  }

  /// Role/link changes can grant or revoke capabilities. Load their SQL
  /// projection after the successful mutation, before continuing the workflow.
  static Future<void> refreshAfterAuthorizationChange() async {
    if (occasionLinkModel == null) return;
    final unitId = currentOccasionId() == null ? currentUnit()?.id : null;
    final link = currentLink;
    invalidateCapabilities();
    try {
      await updateAppData(
          unitId: unitId, link: link, force: true, refreshOffline: false);
    } catch (error) {
      AppLogger.error('Authorization context refresh failed: $error');
    }
  }

  static bool hasGroupCapability(int? groupId, String id) {
    if (groupId == null || occasionLinkModel?.capabilities.isNotEmpty != true) {
      return false;
    }
    return currentUser()?.userGroups?.any(
            (group) => group.id == groupId && group.capabilities[id] == true) ??
        false;
  }

  static bool canMovePlace(int? placeId) {
    if (placeId == null || occasionLinkModel?.capabilities.isNotEmpty != true) {
      return false;
    }
    if (hasCapability(AuthorizationCapabilities.mapPlacesWrite)) return true;
    return currentUser()?.userGroups?.any((group) =>
            group.placeId == placeId &&
            group.capabilities[AuthorizationCapabilities.mapPlaceMove] ==
                true) ??
        false;
  }

  static bool hasCapability(String id) =>
      occasionLinkModel?.capabilities[id] == true;

  static bool canUpdateUsers() =>
      hasCapability(AuthorizationCapabilities.usersWrite);

  static bool canUpdateOrders() =>
      hasCapability(AuthorizationCapabilities.ordersWrite);

  /// Crew navigation remains narrower than editor oversight of cleaning data.
  static bool canOpenCleaningCrewWorkspace() =>
      hasCapability(AuthorizationCapabilities.navigationCleaningCrew);

  static bool canManageReceptionParticipants() =>
      hasCapability(AuthorizationCapabilities.receptionParticipantsManage);

  static bool canUseReception() =>
      hasCapability(AuthorizationCapabilities.receptionUse);

  static bool canSeeUnitUsers() =>
      hasCapability(AuthorizationCapabilities.unitUsersRead);

  static bool canUpdateUnitUsers() =>
      hasCapability(AuthorizationCapabilities.unitUsersWrite);

  static bool canEditOccasion() =>
      hasCapability(AuthorizationCapabilities.occasionsWrite);

  static bool get isDemoReadOnly =>
      occasionLinkModelNotifier.value?.demoReadOnly == true;

  static bool canSeeReservations() =>
      hasCapability(AuthorizationCapabilities.ordersRead);

  static bool canSeeAdministration() =>
      hasCapability(AuthorizationCapabilities.navigationAdministration);

  static bool canUserSeeUnitWorkspace() =>
      hasCapability(AuthorizationCapabilities.navigationUnitWorkspace);

  static bool canOpenScheduleEntryCheck() =>
      hasCapability(AuthorizationCapabilities.navigationScheduleEntryCheck);

  static bool hasGroup() {
    return (currentUser()?.userGroups?.length ?? 0) > 0;
  }

  static UserGroupInfoModel? currentUserGroup() {
    return currentUser()?.userGroups?.firstWhereOrNull((g) => g.type == null);
  }

  static void updateOrganizationLocally(OrganizationModel newOrg) {
    var valid = occasionLinkModelNotifier.value;
    if (valid != null) {
      occasionLinkModelNotifier.value = valid.copyWith(organization: newOrg);
    }
  }
}
