import 'package:fstapp/services/time_helper.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:fstapp/components/cleaning/models/cleaning_place_status.dart';
import 'package:fstapp/components/inventory/models/user_inventory_bundle.dart'; // Added for UserInventoryBundle
import 'package:festapp_core/program.dart';
import 'package:fstapp/components/speakers/speakers_bundle.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/news/news_model.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_model.dart';
import 'package:fstapp/components/map/path_group_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/saved_program_pending_state.dart';

import 'package:fstapp/components/activities/activity_model.dart';

import 'package:festapp_core/map.dart';
import '../components/occasion/occasion_model.dart';

List<int> resolveMyScheduleIds({
  required bool isV1Selected,
  required bool hasPrivateIdentity,
  required Object? privateProgram,
  required List<int> legacyIds,
}) {
  if (!isV1Selected || !hasPrivateIdentity) return List<int>.of(legacyIds);
  final privateProgramMap = privateProgram is Map ? privateProgram : null;
  return ((privateProgramMap?['saved'] as List?) ?? const [])
      .whereType<num>()
      .map((id) => id.toInt())
      .toSet()
      .toList(growable: false);
}

List<int> updateConfirmedScheduleIds(
  Iterable<int> confirmedIds,
  int eventId,
  bool saved,
) {
  final result = confirmedIds.toSet();
  saved ? result.add(eventId) : result.remove(eventId);
  return result.toList(growable: false);
}

class OfflineDataService {
  static const String myScheduleOffline = "mySchedule";
  static const String eventsOfflineStorage = "events";
  static const String informationOfflineStorage = "information";
  static const String activitiesOfflineStorage = "activities";
  static const String userInventoryBundleOffline =
      "userInventoryBundle"; // Added key for inventory
  static const String speakersOfflineStorage = "speakers";
  static const String cleaningStatusOfflineStorage = "cleaningStatus";
  static const String eventFeedbackOfflineStorage = "eventFeedback";
  static Future<void> _myScheduleWriteTail = Future<void>.value();

  static Future<void> saveMyScheduleData(List<int> offlineData) =>
      saveMyScheduleDataIfCurrent(offlineData, () => true);

  static Future<void> saveMyScheduleDataIfCurrent(
    List<int> offlineData,
    bool Function() isCurrent,
  ) {
    return _enqueueMyScheduleWrite(() async {
      if (isCurrent()) {
        await StorageHelper.set(myScheduleOffline, jsonEncode(offlineData));
      }
    });
  }

  static Future<void> clearMyScheduleData() => _enqueueMyScheduleWrite(
        () => StorageHelper.remove(myScheduleOffline),
      );

  static Future<void> _enqueueMyScheduleWrite(
    Future<void> Function() write,
  ) {
    final completer = Completer<void>();
    _myScheduleWriteTail = _myScheduleWriteTail.then((_) async {
      try {
        await write();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static Future<List<int>> getMyScheduleData() async {
    return savedProgramPendingState.apply(await _getConfirmedMyScheduleData());
  }

  static Future<List<int>> getLocalMyScheduleData() async {
    final eventData = await StorageHelper.get(myScheduleOffline);
    if (eventData == null) return const [];
    return (json.decode(eventData) as List<dynamic>)
        .whereType<num>()
        .map((id) => id.toInt())
        .toList(growable: false);
  }

  static Future<List<int>> _getConfirmedMyScheduleData() async {
    final localIds = await getLocalMyScheduleData();
    if (ClientSyncRuntime.isV1Selected &&
        ClientSyncRuntime.hasPrivateIdentity) {
      final privateProgram = await ClientSyncRuntime.readPrivate(
        ClientSyncComponent.privateProgram,
      );
      return resolveMyScheduleIds(
        isV1Selected: true,
        hasPrivateIdentity: true,
        privateProgram: privateProgram,
        legacyIds: localIds,
      );
    }
    return resolveMyScheduleIds(
      isV1Selected: ClientSyncRuntime.isV1Selected,
      hasPrivateIdentity: false,
      privateProgram: null,
      legacyIds: localIds,
    );
  }

  static Future<void> addToMySchedule(
    int id, {
    bool Function()? isCurrent,
  }) async {
    final confirmed = await _getConfirmedMyScheduleData();
    await saveMyScheduleDataIfCurrent(
      updateConfirmedScheduleIds(confirmed, id, true),
      isCurrent ?? () => true,
    );
  }

  static Future<void> addAllToMySchedule(List<int> ids) async {
    var offlineData = await _getConfirmedMyScheduleData();
    for (var id in ids) {
      if (!offlineData.contains(id)) {
        // Avoid duplicates
        offlineData.add(id);
      }
    }
    await saveMyScheduleData(offlineData);
  }

  static Future<void> removeFromMySchedule(
    int id, {
    bool Function()? isCurrent,
  }) async {
    final confirmed = await _getConfirmedMyScheduleData();
    await saveMyScheduleDataIfCurrent(
      updateConfirmedScheduleIds(confirmed, id, false),
      isCurrent ?? () => true,
    );
  }

  static Future<bool> isEventSaved(int id) async {
    return (await getMyScheduleData()).contains(id);
  }

  static Future<List<EventModel>> updateEventsWithMySchedule(
      Iterable<EventModel> events) async {
    final ids = await getMyScheduleData();
    return events
        .map((event) => event.copyWith(isInMySchedule: ids.contains(event.id!)))
        .toList();
  }

  static Future<List<EventModel>> updateEventsWithGroupName(
      Iterable<EventModel> events) async {
    final me = await getUserInfo();
    final group = me?.eventUserGroup;
    return events
        .map((event) => group != null && (event.isGroupEvent ?? false)
            ? event.copyWith(title: group.title, isMyGroupEvent: true)
            : event)
        .toList();
  }

  static Future<void> saveAllOccasions(List<OccasionModel> toSave) =>
      saveAllOffline(OccasionModel.occasionsOffline, toSave);

  static Future<List<OccasionModel>> getAllOccasions() =>
      getAllOffline(OccasionModel.occasionsOffline, OccasionModel.fromJson);

  static Future<void> saveAllMessages(List<NewsModel> toSave) =>
      saveAllOffline(NewsModel.newsOffline, toSave);

  static Future<List<NewsModel>> getAllMessages() =>
      ClientSyncRuntime.isV1Selected
          ? ClientSyncProjection.news()
          : getAllOffline(NewsModel.newsOffline, NewsModel.fromJson);

  static Future<void> saveAllPlaces(List<PlaceModel> toSave) =>
      saveAllOffline(PlaceModel.placesOffline, toSave);

  static Future<void> saveAllPathGroups(List<PathGroupsModel> toSave) =>
      saveAllOffline(PathGroupsModel.pathsOffline, toSave);

  static Future<void> saveAllIcons(List<IconModel> toSave) =>
      saveAllOffline(IconModel.iconsOffline, toSave);

  static Future<void> saveAllPlaceTypes(List<PlaceTypeModel> toSave) =>
      saveAllOffline(PlaceTypeModel.placeTypesOffline, toSave);

  static Future<List<PlaceModel>> getAllPlaces() =>
      ClientSyncRuntime.isV1Selected
          ? ClientSyncProjection.places()
          : getAllOffline(PlaceModel.placesOffline, PlaceModel.fromJson);

  static Future<List<PathGroupsModel>> getAllPathGroups() => ClientSyncRuntime
          .isV1Selected
      ? ClientSyncProjection.paths()
      : getAllOffline(PathGroupsModel.pathsOffline, PathGroupsModel.fromJson);

  static Future<List<IconModel>> getAllIcons() => ClientSyncRuntime.isV1Selected
      ? ClientSyncProjection.icons()
      : getAllOffline(IconModel.iconsOffline, IconModel.fromJson);

  static Future<List<PlaceTypeModel>> getAllPlaceTypes() =>
      ClientSyncRuntime.isV1Selected
          ? ClientSyncProjection.placeTypes()
          : getAllOffline(
              PlaceTypeModel.placeTypesOffline, PlaceTypeModel.fromJson);

  /// Timestamp of the last completed refreshOfflineData run — one stamp for
  /// the whole bundle, shown by the offline banner.
  static const String lastSyncedAtOffline = "lastSyncedAt";

  static Future<void> saveLastSyncedAt(DateTime time) async {
    final normalized = time.toUtc();
    final stored = await StorageHelper.get(lastSyncedAtOffline);
    final previous = stored == null ? null : DateTime.tryParse(stored)?.toUtc();
    if (previous != null && previous.isAfter(normalized)) return;
    await StorageHelper.set(lastSyncedAtOffline, normalized.toIso8601String());
  }

  static Future<DateTime?> getLastSyncedAt() async {
    final raw = await StorageHelper.get(lastSyncedAtOffline);
    return resolveOfflineBannerTimestamp(
      legacyTimestamp: raw == null ? null : DateTime.tryParse(raw),
      clientSyncTimestamp: ClientSyncRuntime.latestLastSuccess,
    )?.toLocal();
  }

  /// Last place-type filter selected on the map, restored on the next visit.
  static const String selectedPlaceTypeOffline = "selectedPlaceType";

  static Future<void> saveSelectedPlaceType(String code) =>
      StorageHelper.set(selectedPlaceTypeOffline, code);

  static Future<String?> getSelectedPlaceType() =>
      StorageHelper.get(selectedPlaceTypeOffline);

  static Future<void> saveInfoDescription(InformationModel toSave) =>
      saveOffline(toSave.id!.toString(), toSave, informationOfflineStorage);

  static Future<InformationModel?> getInfoDescription(String id) =>
      getOffline(id, InformationModel.fromJson, informationOfflineStorage);

  static Future<void> saveUserInfo(UserInfoModel toSave) =>
      saveOffline(UserInfoModel.userInfoOffline, toSave);

  static Future<void> deleteUserInfo() =>
      deleteOffline(UserInfoModel.userInfoOffline);

  static Future<UserInfoModel?> getUserInfo() => ClientSyncRuntime.isV1Selected
      ? ClientSyncProjection.userInfo()
      : getOffline(UserInfoModel.userInfoOffline, UserInfoModel.fromJson);

  static Future<void> saveGlobalSettings(OccasionSettingsModel toSave) =>
      saveOffline(OccasionSettingsModel.globalSettingsOffline, toSave);

  static Future<OccasionSettingsModel?> getGlobalSettings() =>
      ClientSyncRuntime.isV1Selected
          ? ClientSyncProjection.occasionSettings()
          : getOffline(OccasionSettingsModel.globalSettingsOffline,
              OccasionSettingsModel.fromJson);

  static Future<void> saveAllEvents(List<EventModel> toSave) =>
      saveAllOffline(eventsOfflineStorage, toSave);

  static Future<List<EventModel>> getAllEvents() =>
      ClientSyncRuntime.isV1Selected
          ? ClientSyncProjection.events()
          : getAllOffline(
              eventsOfflineStorage,
              (json) =>
                  EventModel.fromJson(json, timeContext: TimeHelper.eventTime));

  static Future<void> saveSpeakers(SpeakersBundle toSave) =>
      saveOffline(speakersOfflineStorage, toSave);

  static Future<SpeakersBundle?> getSpeakers() => ClientSyncRuntime.isV1Selected
      ? ClientSyncProjection.speakers()
      : getOffline(speakersOfflineStorage, SpeakersBundle.fromJson);

  /// Caches the public per-toilet cleaning statuses together with the time
  /// they were fetched. Public data only — not part of [clearUserData].
  static Future<void> saveCleaningStatus(
          List<CleaningPlaceStatus> places, DateTime fetchedAt) =>
      saveOffline(cleaningStatusOfflineStorage, {
        "places": places.map((p) => p.toJson()).toList(),
        "fetchedAt": fetchedAt.toUtc().toIso8601String(),
      });

  /// The cached cleaning statuses with their fetch time, or null when the
  /// cache is empty or unreadable.
  static Future<({List<CleaningPlaceStatus> places, DateTime fetchedAt})?>
      getCleaningStatus() async {
    if (ClientSyncRuntime.isV1Selected) {
      return (
        places: await ClientSyncProjection.cleaningStatus(),
        fetchedAt: ClientSyncRuntime.lastSuccess(SyncFreshnessClass.live) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    final json = await getOffline<Map<String, dynamic>>(
        cleaningStatusOfflineStorage, (j) => j);
    if (json == null) return null;
    final fetchedAt = DateTime.tryParse(json["fetchedAt"]?.toString() ?? "");
    if (fetchedAt == null) return null;
    final places = ((json["places"] as List?) ?? const [])
        .map((e) =>
            CleaningPlaceStatus.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return (places: places, fetchedAt: fetchedAt.toLocal());
  }

  static Future<void> saveAllInfo(List<InformationModel> toSave) =>
      saveAllOffline(InformationModel.informationOffline, toSave);

  static Future<List<InformationModel>> getAllInfo() =>
      ClientSyncRuntime.isV1Selected
          ? ClientSyncProjection.information()
          : getAllOffline(
              InformationModel.informationOffline, InformationModel.fromJson);

  static Future<void> saveAllActivities(List<ActivityModel> toSave) =>
      saveAllOffline(activitiesOfflineStorage, toSave);

  static Future<List<ActivityModel>> getAllActivities() =>
      ClientSyncRuntime.isV1Selected
          ? ClientSyncProjection.activities()
          : getAllOffline(activitiesOfflineStorage, ActivityModel.fromJson);

  /// Caches "my feedback" for one event (one `{eventId: feedbackJson}` object
  /// for all events) so the widget can show the submitted state offline.
  /// Per-user data — cleared by [clearUserData]. A null [json] removes the
  /// event's entry (feedback deleted).
  static Future<void> saveMyEventFeedback(
      int eventId, Map<String, dynamic>? json) async {
    final all = await getOffline<Map<String, dynamic>>(
            eventFeedbackOfflineStorage, (j) => j) ??
        <String, dynamic>{};
    if (json == null) {
      all.remove(eventId.toString());
    } else {
      all[eventId.toString()] = json;
    }
    await saveOffline(eventFeedbackOfflineStorage, all);
  }

  /// The cached "my feedback" json for an event, or null when none is cached.
  static Future<Map<String, dynamic>?> getMyEventFeedback(int eventId) async {
    final all = await getOffline<Map<String, dynamic>>(
        eventFeedbackOfflineStorage, (j) => j);
    final entry = all?[eventId.toString()];
    return entry is Map ? entry.cast<String, dynamic>() : null;
  }

  /// **Saves the entire `UserInventoryBundle` to offline storage.**
  static Future<void> saveUserInventoryBundle(UserInventoryBundle toSave) =>
      saveOffline(userInventoryBundleOffline, toSave);

  /// **Retrieves the `UserInventoryBundle` from offline storage.**
  static Future<UserInventoryBundle?> getUserInventoryBundle() =>
      ClientSyncRuntime.isV1Selected
          ? ClientSyncProjection.userInventory()
          : getOffline(
              userInventoryBundleOffline, UserInventoryBundle.fromJson);

  /// **Deletes the `UserInventoryBundle` from offline storage.**
  static Future<void> deleteUserInventoryBundle() =>
      deleteOffline(userInventoryBundleOffline);

  /// **Clears all user-specific data from offline storage.**
  static Future<void> clearUserData() async {
    await deleteOffline(UserInfoModel.userInfoOffline);
    await clearMyScheduleData();
    await deleteOffline(activitiesOfflineStorage);
    await deleteOffline(userInventoryBundleOffline);
    await deleteOffline(eventFeedbackOfflineStorage);
    savedProgramPendingState.clearAll();
  }

  static Future<void> saveAllOffline<T>(
      String offlineTable, List<T> toSave) async {
    var encoded =
        jsonEncode(toSave.map((item) => (item as dynamic).toJson()).toList());
    await StorageHelper.set(offlineTable, encoded);
  }

  static Future<void> deleteOffline<T>(String id, [String? storage]) async {
    await StorageHelper.remove(id, storage);
  }

  static Future<void> saveOffline<T>(String id, T toSave,
      [String? storage]) async {
    // The toJson method of T will be called automatically by jsonEncode
    var encoded = jsonEncode(toSave);
    await StorageHelper.set(id, encoded, storage);
  }

  static Future<T?> getOffline<T>(
      String id, T Function(Map<String, dynamic>) fromJson,
      [String? storage]) async {
    try {
      var data = await StorageHelper.get(id, storage);
      if (data == null) {
        return null;
      }
      var js = json.decode(data) as Map<String, dynamic>; // Ensure it's a Map
      return fromJson(js);
    } catch (e) {
      //catch incompatibility fails
      // Error in getOffline
      return null;
    }
  }

  static Future<List<T>> getAllOffline<T>(
      String offlineTable, T Function(Map<String, dynamic>) fromJson) async {
    List<T> toReturn = [];
    try {
      var data = await StorageHelper.get(offlineTable);
      if (data == null) {
        return toReturn;
      }
      var offlineData =
          json.decode(data) as List<dynamic>; // Ensure it's a List
      toReturn.addAll(List<T>.from(
          offlineData.map((o) => fromJson(o as Map<String, dynamic>))));
    } catch (e) {
      //catch incompatibility fails
      // Error in getAllOffline
    }
    return toReturn;
  }
}

DateTime? resolveOfflineBannerTimestamp({
  required DateTime? legacyTimestamp,
  required DateTime? clientSyncTimestamp,
}) {
  if (legacyTimestamp == null) return clientSyncTimestamp;
  if (clientSyncTimestamp == null) return legacyTimestamp;
  return clientSyncTimestamp.isAfter(legacyTimestamp)
      ? clientSyncTimestamp
      : legacyTimestamp;
}
