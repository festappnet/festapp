import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/cleaning/db_cleaning.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_model.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:fstapp/components/inventory/db_inventory_pools.dart';
import 'package:fstapp/components/news/db_news.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/app_config_rpc.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/components/occasion/link_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/services/platform_helper.dart';
import 'package:fstapp/components/search/db_search.dart';
import 'package:fstapp/components/speakers/db_speakers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SynchroService {
  static final _supabase = Supabase.instance.client;
  static OccasionSettingsModel? globalSettingsModel =
      OccasionSettingsModel.defaultSettings;

  // Injected callbacks — configured once at startup to break circular imports.
  static bool Function() _isLoggedIn = () => false;
  static Future<UserInfoModel> Function() _getFullUserInfo =
      () => throw StateError('SynchroService not configured');
  static int? Function() _getCurrentOccasionId = () => null;
  static bool _useLegacyAppConfig = false;

  static void configure({
    required bool Function() isLoggedIn,
    required Future<UserInfoModel> Function() getFullUserInfo,
    required int? Function() getCurrentOccasionId,
    required bool useLegacyAppConfig,
  }) {
    _isLoggedIn = isLoggedIn;
    _getFullUserInfo = getFullUserInfo;
    _getCurrentOccasionId = getCurrentOccasionId;
    _useLegacyAppConfig = useLegacyAppConfig;
  }

  static Future<void> refreshOfflineData() async {
    if (ClientSyncRuntime.isV1Selected) {
      await ClientSyncRuntime.refresh(
        SyncReason.manual,
        privateConsumer: true,
      );
      await DbSearch.rebuildOfflineIndex();
      return;
    }
    await refreshUserOfflineData();

    final occasionId = _getCurrentOccasionId();
    var places = await DbPlaces.getAllPlaces();
    await OfflineDataService.saveAllPlaces(places);

    var paths = await DbPlaces.getAllPathGroups();
    await OfflineDataService.saveAllPathGroups(paths);

    var icons = await DbPlaces.getAllIcons();
    await OfflineDataService.saveAllIcons(icons);

    var info = await DbInformation.getAllActiveInformation();
    await OfflineDataService.saveAllInfo(info);

    var messages = await DbNews.getAllNewsMessages();
    await OfflineDataService.saveAllMessages(messages);

    // Speakers are core — always cached when an occasion is present (R7).
    if (occasionId != null) {
      final speakers =
          await DbSpeakers.getSpeakers(occasionId, includeDescription: true);
      await OfflineDataService.saveSpeakers(speakers);

      // Cleaning statuses are public data — cache them so the toilet list and
      // map pin colors survive offline (R2.2). Own try/catch: a cleaning
      // failure must not break the rest of the sync chain.
      if (FeatureService.isFeatureEnabled(FeatureConstants.cleaning)) {
        try {
          final status = await DbCleaning.getStatus(occasionId);
          await OfflineDataService.saveCleaningStatus(
              status.places, DateTime.now());
        } catch (_) {
          // Best-effort cache only.
        }
      }
    }

    // Full event list (incl. HTML descriptions) — cached on every platform,
    // plain browser tabs included (R5). Guarded: an anonymous web visit
    // without an occasion used to hit `occasionId!` here.
    if (occasionId != null) {
      var events = await DbEvents.getAllEvents(occasionId, true);
      await OfflineDataService.saveAllEvents(events);
    }

    await DbEvents.synchronizeMySchedule();

    // Refresh the GlobalSearch offline index from the freshly cached data.
    await DbSearch.rebuildOfflineIndex();

    // One "last synced" stamp for the whole bundle (the offline banner).
    await OfflineDataService.saveLastSyncedAt(DateTime.now());
  }

  /// Refreshes the signed-in user's profile, activities, and stay assignment.
  /// Kept separate so startup can make this private offline snapshot available
  /// without blocking first paint on the complete public-data refresh.
  static Future<void> refreshUserOfflineData() async {
    if (ClientSyncRuntime.isV1Selected) {
      await ClientSyncRuntime.refresh(
        SyncReason.manual,
        privateConsumer: true,
      );
      return;
    }
    final occasionId = _getCurrentOccasionId();
    if (_isLoggedIn() && occasionId != null) {
      var userInfo = await _getFullUserInfo();
      await OfflineDataService.saveUserInfo(userInfo);
      var bundle = await DbEvents.getMyEventsAndActivities(occasionId, true);
      await OfflineDataService.saveAllActivities(bundle!.activities);
      var userInventoryBundle = await DbInventoryPools.getUserInventory();
      await OfflineDataService.saveUserInventoryBundle(userInventoryBundle);
    } else {
      await OfflineDataService.deleteUserInfo();
    }
  }

  static Future<OccasionLinkModel> getAppConfig(LinkModel link) async {
    final params = {
      "data_in": {
        "link": link.occasionLink,
        "form_link": link.formLink,
        "unit_id": link.unitId,
        "organization": AppConfig.organization,
        "platform": await PlatformHelper.getPlatform()
      }
    };
    final data = await loadAppConfigWithLegacyFallback(
      invoke: (functionName) => _supabase.rpc(functionName, params: params),
      useLegacyContract: _useLegacyAppConfig,
    );

    return OccasionLinkModel.fromJson(data);
  }
}
