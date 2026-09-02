import 'dart:collection';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/components/activities/activity_data_helper.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/workshop_feature.dart';
import 'package:fstapp/components/activities/activity_model.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/schedule/event_commands.dart';
import 'package:fstapp/components/schedule/attendance_commands.dart';
import 'package:fstapp/components/schedule/saved_program_commands.dart';
import 'package:fstapp/components/schedule/saved_program_mutation_coordinator.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_sync_protocol.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/components/schedule/exclusive_group_model.dart';
import 'package:fstapp/components/schedule/exclusive_group_commands.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/data_extensions.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/saved_program_pending_state.dart';
import 'package:fstapp/components/offline/offline_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../map/place_model.dart';
import 'get_events_helper.dart';

class DbEvents {
  static final _supabase = Supabase.instance.client;
  static int _savedProgramScopeEpoch = 0;
  static final SavedProgramMutationCoordinator
      _savedProgramMutationCoordinator = SavedProgramMutationCoordinator(
    currentScope: _currentSavedProgramScope,
    persist: _persistSavedProgram,
  );
  static EventCommands get _commands => SupabaseEventCommands(_supabase);
  static AttendanceCommands get _attendanceCommands =>
      SupabaseAttendanceCommands(_supabase);
  static SavedProgramCommands get _savedProgramCommands =>
      SupabaseSavedProgramCommands(
          _supabase, RightsService.currentOccasionId()!);
  static SavedProgramCommands get _legacySavedProgramCommands =>
      LegacySavedProgramCommands(
        _supabase,
        RightsService.currentOccasionId()!,
      );
  static ExclusiveGroupCommands get _exclusiveGroupCommands =>
      SupabaseExclusiveGroupCommands(_supabase);

  static String _currentSavedProgramScope() {
    final userId =
        AuthService.isLoggedIn() ? AuthService.currentUserId() : 'anonymous';
    return '$_savedProgramScopeEpoch|$userId|${RightsService.currentOccasionId()}|${ClientSyncRuntime.mutationContextToken}';
  }

  static void invalidateSavedProgramMutationScope() {
    _savedProgramScopeEpoch++;
    savedProgramPendingState.clearAll();
  }

  static Future<HashSet<EventModel>> loadAllMySchedule() async {
    var dataEventUsersSaved = await _supabase
        .from(Tb.events.table)
        .select("${Tb.events.id},"
            "${Tb.events.title},"
            "${Tb.events.start_time},"
            "${Tb.events.end_time},"
            "${Tb.places.table}(${Tb.places.id}, ${Tb.places.title}),"
            "${Tb.events.type},"
            "${Tb.events.max_participants},"
            "${Tb.events.is_group_event},"
            "${Tb.event_users_saved.table}!inner(*)")
        .eq("${Tb.event_users_saved.table}.${Tb.event_users_saved.user}",
            AuthService.currentUserId())
        .eq(Tb.events.is_hidden, false)
        .eq(Tb.events.occasion, RightsService.currentOccasionId()!)
        .order(Tb.events.start_time, ascending: true)
        .order(Tb.events.max_participants, ascending: false);

    var remoteEvents = List<EventModel>.from(
        dataEventUsersSaved.map((x) => EventModel.fromJson(x)));
    for (var element in remoteEvents) {
      element.isInMySchedule = true;
    }
    var toReturn = EventModel.CreateEventModelSet();
    toReturn.addAll(remoteEvents);
    return toReturn;
  }

  static Future<HashSet<EventModel>> loadAllMyScheduleOffline() async {
    var events = await OfflineDataService.getMyScheduleData();
    var localData = await _supabase
        .from(Tb.events.table)
        .select("${Tb.events.id},"
            "${Tb.events.title},"
            "${Tb.events.start_time},"
            "${Tb.events.end_time},"
            "${Tb.places.table}(${Tb.places.id}, ${Tb.places.title}),"
            "${Tb.events.type},"
            "${Tb.events.max_participants},"
            "${Tb.events.is_group_event}")
        .inFilter(Tb.events.id, events)
        .eq(Tb.events.is_hidden, false)
        .eq(Tb.events.occasion, RightsService.currentOccasionId()!)
        .order(Tb.events.start_time, ascending: true)
        .order(Tb.events.max_participants, ascending: false);
    var localEvents =
        List<EventModel>.from(localData.map((x) => EventModel.fromJson(x)));
    for (var element in localEvents) {
      element.isInMySchedule = true;
    }
    var toReturn = EventModel.CreateEventModelSet();
    toReturn.addAll(localEvents);
    return toReturn;
  }

  static Future<List<EventModel>> getAllEventsForDatagrid() async {
    final occasionId = RightsService.currentOccasionId();
    if (occasionId == null) {
      return [];
    }

    final data = await _supabase.rpc(
      'get_all_events_for_datagrid',
      params: {'p_occasion_id': occasionId},
    );

    return List<EventModel>.from(
        data.map((x) => EventModel.fromJson(x as Map<String, dynamic>)));
  }

  static Future<EventModel> getEvent(int eventId,
      [bool withParent = false]) async {
    // with parents or children
    var withParentSelect = withParent
        ? "${Tb.event_groups.table}!${Tb.event_groups.table}_${Tb.event_groups.event_child}_fkey(${Tb.event_groups.event_parent})"
        : "${Tb.event_groups.table}!${Tb.event_groups.table}_${Tb.event_groups.event_parent}_fkey(${Tb.event_groups.event_child})";
    late EventModel event;
    if (ClientSyncRuntime.isV1Selected && RightsService.canSeeAdmin()) {
      final response = await _supabase.rpc('get_event_editor_v1', params: {
        'p_occasion': RightsService.currentOccasionId()!,
        'p_event': eventId,
      });
      final body = (response as Map).cast<String, dynamic>();
      final data = (body['data'] as Map).cast<String, dynamic>();
      event = EventModel.fromCommandJson(
        (data['event'] as Map).cast<String, dynamic>(),
        (data['version'] as num).toInt(),
      );
      final placeId = event.place?.id;
      if (placeId != null) {
        for (final place in await OfflineDataService.getAllPlaces()) {
          if (place.id == placeId) {
            event.place = place;
            break;
          }
        }
      }
      event.occasionId = RightsService.currentOccasionId();
    } else {
      var data = await _supabase
          .from(Tb.events.table)
          .select(
              "${Tb.events.id},${Tb.events.updated_at},${Tb.events.occasion},${Tb.events.title},${Tb.events.description},${Tb.events.start_time},${Tb.events.end_time},${Tb.events.max_participants},${Tb.events.split_for_men_women},${Tb.events.is_group_event},${Tb.events.is_hidden},${Tb.events.type},${Tb.events.data},${Tb.places.table}(${Tb.places.id}, ${Tb.places.title}),$withParentSelect")
          .eq(Tb.events.id, eventId)
          .single();
      event = EventModel.fromJson(data);
    }

    if (AuthService.isLoggedIn()) {
      event.isInMySchedule = await isEventSaved(event.id!);
      event.isSignedIn = await DbEvents.isCurrentUserSignedToEvent(event.id!);
    } else {
      event.isInMySchedule = await OfflineDataService.isEventSaved(event.id!);
    }

    if (event.childEventIds != null) {
      var childEventsData = await _supabase
          .from(Tb.events.table)
          .select("${Tb.events.id},"
              "${Tb.events.title},"
              "${Tb.events.start_time},"
              "${Tb.events.end_time},"
              "${Tb.events.max_participants},"
              "${Tb.events.data},"
              "${Tb.places.table}(${Tb.places.id}, ${Tb.places.title}),"
              "${Tb.event_users.table}(count)")
          .inFilter(Tb.events.id, event.childEventIds!)
          .eq(Tb.events.is_hidden, false);

      event.childEvents = List<EventModel>.from(
          childEventsData.map((x) => EventModel.fromJson(x))).sortEvents();

      if (AuthService.isLoggedIn()) {
        await loadIsCurrentUserSignedIn(event.childEvents);
      }
    }
    if ((event.isGroupEvent ?? false) && RightsService.hasGroup()) {
      event.isMyGroupEvent = true;
    }

    return event;
  }

  static Future<void> loadIsCurrentUserSignedIn(List<EventModel> events) async {
    List<dynamic> currentUserStatePerEventData = await _supabase
        .from(Tb.events.table)
        .select("${Tb.events.id}, ${Tb.event_users.table}!inner(count)")
        .eq("${Tb.event_users.table}.${Tb.event_users.user}",
            AuthService.currentUserId())
        .inFilter(Tb.events.id, events.map((e) => e.id).toList());

    Set<int> userSignedInEvents = currentUserStatePerEventData
        .where((c) => c[Tb.event_users.table][0]["count"] > 0)
        .map((c) => c["id"] as int)
        .toSet();
    for (var e in events) {
      e.isSignedIn = userSignedInEvents.contains(e.id!) ? true : false;
    }
  }

  static Future<List<UserInfoModel>> getParticipantsPerEvent(
      int eventId) async {
    final response = await _supabase.rpc(
      'get_event_participants_for_edit',
      params: {'p_event': eventId},
    );
    final result = (response as Map).cast<String, dynamic>();
    if (result['code'] != 200) return [];
    return List<UserInfoModel>.from(
      (result['data'] as List).map((item) =>
          UserInfoModel.fromJson((item as Map).cast<String, dynamic>())),
    );
  }

  static Future<int> getParticipantsPerEventCount(int eventId) async {
    var result = await _supabase
        .from(Tb.event_users.table)
        .select()
        .eq(Tb.event_users.event, eventId)
        .count();
    return result.count;
  }

  static Future<bool> isCurrentUserSignedToEvent(int eventId) async {
    var result = await _supabase
        .from(Tb.event_users.table)
        .select()
        .eq(Tb.event_users.event, eventId)
        .eq(Tb.event_users.user, AuthService.currentUserId())
        .count();
    return result.count > 0;
  }

  static Future<bool> signInToEvent(BuildContext context, int eventId,
      [UserInfoModel? participant]) async {
    var userId = participant?.id ?? AuthService.currentUserId();

    dynamic result;
    try {
      if (ClientSyncRuntime.isV1Selected) {
        final response = await _attendanceCommands.setAttendance(
          eventId: eventId,
          participantId: userId,
          action: AttendanceAction.signIn,
        );
        result = {
          'code': response.code,
          if (response.eventsRegistrationStart != null)
            'events_registration_start': response.eventsRegistrationStart,
        };
      } else {
        result = await _supabase
            .rpc("sign_user_to_event", params: {"ev": eventId, "usr": userId});
      }
    } catch (e) {
      // Offline: say so readably and behave like the non-200 branches
      // (toast + return); other errors keep today's behavior.
      if (ExceptionHandler.isNetworkError(e)) {
        if (context.mounted) {
          ToastHelper.Show(context, OfflineStrings.writeRequiresConnection,
              severity: ToastSeverity.NotOk);
        }
        return false;
      }
      rethrow;
    }

    switch (result["code"]) {
      case 200:
        {
          if (participant == null) {
            var trPrefix = RightsService.currentUser()?.getGenderPrefix();
            ToastHelper.Show(
                context, ScheduleStrings.youHaveBeenSignedIn(trPrefix));
          } else {
            var trPrefix = participant.getGenderPrefix();
            ToastHelper.Show(
                context,
                ScheduleStrings.userHasBeenSignedIn(trPrefix,
                    user: participant.toString()));
          }
          return true;
        }
      case 100:
        ToastHelper.Show(context,
            "${ScheduleStrings.cannotSignIn} ${ScheduleStrings.eventOver}",
            severity: ToastSeverity.NotOk);
        return false;
      case 101:
        ToastHelper.Show(context,
            "${ScheduleStrings.cannotSignIn} ${ScheduleStrings.eventFull}",
            severity: ToastSeverity.NotOk);
        return false;
      case 102:
        {
          if (participant == null) {
            var trPrefix = RightsService.currentUser()?.getGenderPrefix();
            var message = ScheduleStrings.alreadySignedInSameType(trPrefix);
            ToastHelper.Show(
                context, "${ScheduleStrings.cannotSignIn} $message",
                severity: ToastSeverity.NotOk);
          } else {
            var trPrefix = participant.getGenderPrefix();
            var message = ScheduleStrings.userAlreadySignedInSameType(trPrefix,
                user: participant.toString());
            ToastHelper.Show(
                context, "${ScheduleStrings.cannotSignIn} $message",
                severity: ToastSeverity.NotOk);
          }
          return false;
        }
      case 103:
        {
          if (participant == null) {
            var trPrefix = RightsService.currentUser()?.getGenderPrefix();
            var message = ScheduleStrings.alreadySignedIn(trPrefix);
            ToastHelper.Show(
                context, "${ScheduleStrings.cannotSignIn} $message",
                severity: ToastSeverity.NotOk);
          } else {
            var trPrefix = participant.getGenderPrefix();
            var message = ScheduleStrings.userAlreadySignedIn(trPrefix,
                user: participant.toString());
            ToastHelper.Show(
                context, "${ScheduleStrings.cannotSignIn} $message",
                severity: ToastSeverity.NotOk);
          }
          return false;
        }
      case 107:
        {
          if (participant == null) {
            var trPrefix = RightsService.currentUser()?.getGenderPrefix();
            var message = ScheduleStrings.alreadySignedInSameTime(trPrefix);
            ToastHelper.Show(
                context, "${ScheduleStrings.cannotSignIn} $message",
                severity: ToastSeverity.NotOk);
          } else {
            var trPrefix = participant.getGenderPrefix();
            ToastHelper.Show(
                context,
                ScheduleStrings.userAlreadySignedInSameTime(trPrefix,
                    user: participant.toString()));
          }
          return false;
        }
      case 104:
        {
          String answerWhy = ScheduleStrings.tooSoon;
          if (result["events_registration_start"] != null) {
            var start = DateTime.parse(result["events_registration_start"])
                .toOccasionTime();
            var datePart =
                DateFormat.MMMMEEEEd(context.locale.languageCode).format(start);
            var timePart =
                DateFormat.Hm(context.locale.languageCode).format(start);
            String startString = "$datePart $timePart";
            answerWhy = ScheduleStrings.signInFrom(time: startString);
          }

          var workshopsFeature =
              FeatureService.getFeatureDetails(FeatureConstants.workshops)
                  as WorkshopsFeature;
          var message = workshopsFeature.registrationNotOpenMessage;
          if (message != null && message.isNotEmpty) {
            answerWhy = workshopsFeature.registrationNotOpenMessage!;
            ToastHelper.Show(context, answerWhy, severity: ToastSeverity.NotOk);
            return false;
          }

          ToastHelper.Show(
              context, "${ScheduleStrings.cannotSignIn} $answerWhy",
              severity: ToastSeverity.NotOk);
          return false;
        }
      case 105:
        ToastHelper.Show(context,
            "${ScheduleStrings.cannotSignIn} ${ScheduleStrings.maxMenReached}",
            severity: ToastSeverity.NotOk);
        return false;
      case 106:
        ToastHelper.Show(context,
            "${ScheduleStrings.cannotSignIn} ${ScheduleStrings.maxWomenReached}",
            severity: ToastSeverity.NotOk);
        return false;
      case 109:
        ToastHelper.Show(context, SpeakersStrings.bookingLimitReached,
            severity: ToastSeverity.NotOk);
        return false;
      //403, 108, 109
      default:
        ToastHelper.Show(context, ScheduleStrings.cannotSignIn,
            severity: ToastSeverity.NotOk);
        return false;
    }
  }

  static Future<bool> isEventSaved(int id) async {
    if (ClientSyncRuntime.isV1Selected) {
      final privateProgram = await ClientSyncRuntime.readPrivate(
          ClientSyncComponent.privateProgram);
      return privateProgram is Map &&
          ((privateProgram['saved'] as List?) ?? const []).contains(id);
    }
    var data = await _supabase
        .from(Tb.event_users_saved.table)
        .select()
        .eq(Tb.event_users_saved.event, id)
        .eq(Tb.event_users_saved.user, AuthService.currentUserId())
        .maybeSingle();
    return data != null;
  }

  static Future<void> removeFromMySchedule(BuildContext context, int id,
      {bool showSuccessToast = true}) async {
    await setSavedProgram(
      context,
      id,
      false,
      showSuccessToast: showSuccessToast,
    );
  }

  static Future<bool> addToMySchedule(BuildContext context, int id,
      {bool showSuccessToast = true}) async {
    if (!AppConfig.isOwnProgramSupportedWithoutSignIn &&
        !AuthService.isLoggedIn()) {
      ToastHelper.Show(context, ScheduleStrings.signInBeforeAddingToMySchedule);
      return false;
    }
    final result = await setSavedProgram(
      context,
      id,
      true,
      showSuccessToast: showSuccessToast,
    );
    return result.wasApplied;
  }

  static Future<SavedProgramMutationResult> setSavedProgram(
    BuildContext context,
    int id,
    bool saved, {
    bool showSuccessToast = true,
  }) async {
    if (saved &&
        !AppConfig.isOwnProgramSupportedWithoutSignIn &&
        !AuthService.isLoggedIn()) {
      ToastHelper.Show(context, ScheduleStrings.signInBeforeAddingToMySchedule);
      return const SavedProgramMutationResult(
        SavedProgramMutationOutcome.rejected,
      );
    }
    final scope = _currentSavedProgramScope();
    final owner = savedProgramPendingState.createOwner();
    savedProgramPendingState.set(id, owner, saved);
    late final SavedProgramMutationResult result;
    try {
      result = await _savedProgramMutationCoordinator.enqueue(
        scope: scope,
        eventId: id,
        saved: saved,
      );
    } finally {
      savedProgramPendingState.clear(id, owner);
    }

    if (result.error != null && context.mounted) {
      await ExceptionHandler.handle(context, error: result.error!);
    }
    if (result.wasApplied && showSuccessToast && context.mounted) {
      ToastHelper.Show(
        context,
        saved
            ? ScheduleStrings.addedToMySchedule
            : ScheduleStrings.removedFromMySchedule,
      );
    }
    return result;
  }

  static Future<bool> _persistSavedProgram(
      String scope, int id, bool saved) async {
    if (_currentSavedProgramScope() != scope) return false;
    if (AuthService.isLoggedIn()) {
      if (ClientSyncRuntime.isV1Selected) {
        await _savedProgramCommands.update(
          [id],
          saved ? SavedProgramMode.join : SavedProgramMode.remove,
        );
      } else {
        final savedIds = await _legacySavedProgramCommands.update(
          [id],
          saved ? SavedProgramMode.join : SavedProgramMode.remove,
        );
        if (_currentSavedProgramScope() != scope) return false;
        await OfflineDataService.saveMyScheduleDataIfCurrent(
          savedIds,
          () => _currentSavedProgramScope() == scope,
        );
      }
    } else if (saved) {
      await OfflineDataService.addToMySchedule(
        id,
        isCurrent: () => _currentSavedProgramScope() == scope,
      );
    } else {
      await OfflineDataService.removeFromMySchedule(
        id,
        isCurrent: () => _currentSavedProgramScope() == scope,
      );
    }
    return _currentSavedProgramScope() == scope;
  }

  static Future<void> synchronizeMySchedule({bool join = false}) async {
    if (!AuthService.isLoggedIn() || !AppConfig.isOwnProgramSupported) {
      return;
    }
    if (ClientSyncRuntime.isV1Selected && !join) {
      return;
    }
    final scope = _currentSavedProgramScope();
    if (join) {
      final mergeVersion = savedProgramPendingState.mutationVersion;
      final localEventIds = await OfflineDataService.getLocalMyScheduleData();
      if (_currentSavedProgramScope() != scope ||
          savedProgramPendingState.mutationVersion != mergeVersion) {
        return;
      }
      for (final eventId in localEventIds.toSet()) {
        if (_currentSavedProgramScope() != scope ||
            savedProgramPendingState.mutationVersion != mergeVersion) {
          return;
        }
        final result = await _savedProgramMutationCoordinator.enqueue(
          scope: scope,
          eventId: eventId,
          saved: true,
        );
        if (result.error != null) throw result.error!;
        if (result.outcome == SavedProgramMutationOutcome.scopeChanged) return;
        if (!result.wasApplied &&
            result.outcome != SavedProgramMutationOutcome.superseded) {
          throw StateError('Saved-program merge was rejected');
        }
      }
      return;
    }

    final mutationVersion = savedProgramPendingState.mutationVersion;
    final remoteEvents = await loadAllMySchedule();
    final eventIdsToSynchronize =
        remoteEvents.map((event) => event.id!).toList();

    if (_currentSavedProgramScope() == scope &&
        savedProgramPendingState.mutationVersion == mutationVersion) {
      await OfflineDataService.saveMyScheduleDataIfCurrent(
        eventIdsToSynchronize,
        () =>
            _currentSavedProgramScope() == scope &&
            savedProgramPendingState.mutationVersion == mutationVersion,
      );
    }
  }

  static Future<EventModel> updateEvent(EventModel event) async {
    if (ClientSyncRuntime.isV1Selected) {
      event.occasionId ??= RightsService.currentOccasionId();
      final result = await _commands.save(event);
      if (result.status == EventCommandStatus.conflict) {
        throw StateError('Event was changed by another editor');
      }
      if (result.status == EventCommandStatus.rejected ||
          result.event == null) {
        throw StateError('Event save was rejected');
      }
      return result.event!;
    }
    var upsertObj = event.toUpsertMap();

    if (event.description != null) {
      upsertObj.addAll({Tb.events.description: event.description});
    }
    dynamic eventData;
    if (event.id != null) {
      upsertObj.addAll({Tb.events.id: event.id});
      eventData = await _supabase
          .from(Tb.events.table)
          .update(upsertObj)
          .eq(Tb.events.id, event.id!)
          .select()
          .single();
    } else {
      upsertObj
          .addAll({Tb.events.occasion: RightsService.currentOccasionId()!});
      eventData = await _supabase
          .from(Tb.events.table)
          .insert(upsertObj)
          .select()
          .single();
    }
    var updatedEvent = EventModel.fromJson(eventData);

    await removeEventFromEventGroups(updatedEvent);
    if (event.parentEventIds?.isNotEmpty ?? false) {
      var insert = [];
      for (var eParent in event.parentEventIds!) {
        insert.add({
          Tb.event_groups.event_child: updatedEvent.id,
          Tb.event_groups.event_parent: eParent
        });
      }
      await _supabase.from(Tb.event_groups.table).insert(insert);
    }
    return updatedEvent;
  }

  static Future<void> updateEventFromDataGrid(EventModel event) async {
    var updatedEvent = await updateEvent(event);

    if (ClientSyncRuntime.isV1Selected) return;

    var insertRoles = [];
    for (var eParent in event.eventRolesIds!) {
      insertRoles.add({
        Tb.event_roles.event: updatedEvent.id,
        Tb.event_roles.role: eParent
      });
    }

    await _supabase
        .from(Tb.event_roles.table)
        .delete()
        .eq(Tb.event_roles.event, updatedEvent.id!);

    await _supabase.from(Tb.event_roles.table).insert(insertRoles);
  }

  static Future<void> removeEventFromSaved(EventModel updatedEvent) async {
    await _supabase
        .from(Tb.event_users_saved.table)
        .delete()
        .eq(Tb.event_users_saved.event, updatedEvent.id!);
  }

  static Future<void> removeEventFromEventGroups(
      EventModel updatedEvent) async {
    await _supabase
        .from(Tb.event_groups.table)
        .delete()
        .eq(Tb.event_groups.event_child, updatedEvent.id!);
  }

  static Future<void> deleteEvent(EventModel data) async {
    if (ClientSyncRuntime.isV1Selected) {
      data.occasionId ??= RightsService.currentOccasionId();
      final result = await _commands.delete(data);
      if (result.status == EventCommandStatus.conflict) {
        throw StateError('Event was changed by another editor');
      }
      if (result.status == EventCommandStatus.rejected) {
        throw StateError('Event deletion was rejected');
      }
      return;
    }
    // Editor-guarded server-side delete that unbinds sign-ups and other child
    // rows (event_users, event_users_saved, exclusive/roles/groups) atomically,
    // so events with attendees — including counseling slots — delete cleanly.
    final res =
        await _supabase.rpc('delete_event', params: {'p_event': data.id});
    final code = (res is Map && res['code'] != null)
        ? (res['code'] as num).toInt()
        : null;
    if (code != 200) {
      throw Exception('delete_event failed with code $code');
    }
  }

  /// Lightweight id/title/time list of all occasion events (hidden included),
  /// for pickers like the exclusivity editor. Editor-guarded server-side.
  static Future<List<EventModel>> getAllEventsBasic() async {
    final res = await _supabase.rpc('get_events_catalog',
        params: {'p_occasion': RightsService.currentOccasionId()!});
    if (res['code'] != 200) {
      throw Exception('get_events_catalog failed with code ${res['code']}');
    }
    return List<EventModel>.from((res['data'] as List)
        .map((x) => EventModel.fromJson((x as Map).cast<String, dynamic>())));
  }

  static Future<List<ExclusiveGroupModel>> getAllExclusiveGroups() async {
    if (ClientSyncRuntime.isV1Selected) {
      return _exclusiveGroupCommands.list(RightsService.currentOccasionId()!);
    }
    var data = await _supabase
        .from(Tb.exclusive_groups.table)
        .select("${Tb.exclusive_groups.id}, "
            "${Tb.exclusive_groups.title}, "
            "${Tb.exclusive_events.table}(${Tb.exclusive_events.event})")
        .eq(Tb.exclusive_groups.occasion, RightsService.currentOccasionId()!);
    return List<ExclusiveGroupModel>.from(
        data.map((x) => ExclusiveGroupModel.fromJson(x)));
  }

  static Future<void> updateExclusiveGroup(ExclusiveGroupModel model) async {
    if (ClientSyncRuntime.isV1Selected) {
      final saved = await _exclusiveGroupCommands.save(
        RightsService.currentOccasionId()!,
        model,
      );
      model
        ..id = saved.id
        ..title = saved.title
        ..events = saved.events
        ..aggregateVersion = saved.aggregateVersion;
      return;
    }
    Map<String, dynamic> upsertObj = {
      Tb.exclusive_groups.title: model.title,
    };

    dynamic eventData;
    if (model.id != null) {
      upsertObj.addAll({Tb.exclusive_groups.id: model.id.toString()});
      eventData = await _supabase
          .from(Tb.exclusive_groups.table)
          .update(upsertObj)
          .eq(Tb.exclusive_groups.id, model.id!)
          .select()
          .single();
    } else {
      upsertObj.addAll(
          {Tb.exclusive_groups.occasion: RightsService.currentOccasionId()!});
      eventData = await _supabase
          .from(Tb.exclusive_groups.table)
          .insert(upsertObj)
          .select()
          .single();
    }
    var updated = ExclusiveGroupModel.fromJson(eventData);

    await _supabase
        .from(Tb.exclusive_events.table)
        .delete()
        .eq(Tb.exclusive_events.group, updated.id!);

    var insert = [];
    for (var e in model.events!) {
      insert.add({
        Tb.exclusive_events.group: updated.id,
        Tb.exclusive_events.event: e
      });
    }
    await _supabase.from(Tb.exclusive_events.table).insert(insert).select();
  }

  static Future<void> deleteExclusiveGroup(ExclusiveGroupModel data) async {
    if (ClientSyncRuntime.isV1Selected) {
      await _exclusiveGroupCommands.delete(
        RightsService.currentOccasionId()!,
        data,
      );
      return;
    }
    await _supabase
        .from(Tb.exclusive_events.table)
        .delete()
        .eq(Tb.exclusive_events.group, data.id!);
    await _supabase
        .from(Tb.exclusive_groups.table)
        .delete()
        .eq(Tb.exclusive_groups.id, data.id!);
  }

  static Future<void> signOutFromEvent(BuildContext? context, int eventId,
      [UserInfoModel? participant]) async {
    AuthService.ensureUserIsLoggedIn();
    var userId = participant?.id ?? AuthService.currentUserId();

    dynamic result;
    try {
      if (ClientSyncRuntime.isV1Selected) {
        final response = await _attendanceCommands.setAttendance(
          eventId: eventId,
          participantId: userId,
          action: AttendanceAction.signOut,
        );
        result = {'code': response.code};
      } else {
        result = await _supabase.rpc("sign_user_out_of_event",
            params: {"ev": eventId, "usr": userId});
      }
    } catch (e) {
      // Offline: say so readably and behave like the non-200 branches
      // (toast + return); other errors keep today's behavior.
      if (ExceptionHandler.isNetworkError(e)) {
        if (context != null && context.mounted) {
          ToastHelper.Show(context, OfflineStrings.writeRequiresConnection,
              severity: ToastSeverity.NotOk);
        }
        return;
      }
      rethrow;
    }
    switch (result["code"]) {
      case 200:
        if (participant == null) {
          var trPrefix = RightsService.currentUser()?.getGenderPrefix();
          if (context != null) {
            ToastHelper.Show(
                context, ScheduleStrings.youHaveBeenSignedOut(trPrefix));
          }
          return;
        } else {
          var trPrefix = participant.getGenderPrefix();
          if (context != null) {
            ToastHelper.Show(
                context,
                ScheduleStrings.userHasBeenSignedOut(trPrefix,
                    user: participant.toString()));
          }
        }
        return;
      case 201:
        if (context != null) {
          ToastHelper.Show(context, ScheduleStrings.cannotSignOutPastEvent,
              severity: ToastSeverity.NotOk);
        }
        return;
    }
  }

  static Future<bool> hasEventAllowedRole(int eventId) async {
    var data =
        await _supabase.rpc("get_is_event_allowed", params: {"ev": eventId});
    return data;
  }

  static Future<List<EventModel>> getAllEvents(
      int occasionId, bool includeDescription) async {
    final response = await _supabase.rpc(
      'get_events',
      params: {
        'p_occasion': occasionId,
        'p_include_description': includeDescription,
      },
    );

    if (response['code'] != 200) return [];

    final json = response['data'] as Map<String, dynamic>;

    // root‐level arrays
    final eventsJson = (json['events'] as List).cast<Map<String, dynamic>>();
    final placesList = GetEventsHelper.parsePlaces(json);
    final groupsList = GetEventsHelper.parseEventGroups(json);
    final rolesList = GetEventsHelper.parseEventRoles(json);
    final usersCountList = GetEventsHelper.parseEventUsers(json);
    final usersSavedList = GetEventsHelper.parseEventUsersSaved(json);

    // build lookup maps
    final placeById = {for (var p in placesList) p.id!: p};
    final groupsByParent = <int, List<EventGroupModel>>{};
    final parentsByChild = <int, List<EventGroupModel>>{};
    for (var g in groupsList) {
      groupsByParent.putIfAbsent(g.eventParent, () => []).add(g);
      parentsByChild.putIfAbsent(g.eventChild, () => []).add(g);
    }
    final rolesByEvent = <int, List<int>>{};
    for (var r in rolesList) {
      rolesByEvent.putIfAbsent(r.eventId, () => []).add(r.roleId);
    }
    final usersByEvent = {for (var u in usersCountList) u.eventId: u.count};
    final savedByEvent = {for (var s in usersSavedList) s.eventId: s.count};

    // instantiate and populate each EventModel
    final events = <EventModel>[];
    for (var eJson in eventsJson) {
      final ev = EventModel.fromJson(eJson);
      // override place with full model if available
      if (ev.place?.id != null) {
        ev.place = placeById[ev.place!.id];
      }
      // assign child/parent IDs
      ev.childEventIds =
          groupsByParent[ev.id!]?.map((g) => g.eventChild).toList();
      ev.parentEventIds =
          parentsByChild[ev.id!]?.map((g) => g.eventParent).toList();
      // assign roles and counts
      ev.eventRolesIds = rolesByEvent[ev.id!];
      ev.currentParticipants = usersByEvent[ev.id!];
      ev.currentUsersSaved = savedByEvent[ev.id!];
      events.add(ev);
    }

    for (var e in events) {
      var children = events
          .where((ev) => ev.parentEventIds?.contains(e.id) ?? false)
          .toList();
      e.childEvents = children;
    }

    // sort by start time, for example
    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    return events;
  }

  // In YourServiceClass or relevant class containing getMyEventsAndActivities

  static Future<MyEventsBundle?> getMyEventsAndActivities(
      int occasionId, bool includeDescription) async {
    final response = await _supabase.rpc(
      'get_my_events_and_activities', // Calling the updated SQL function
      params: {
        'p_occasion': occasionId,
        'p_include_description': includeDescription,
      },
    );

    if (response == null) {
      AppLogger.error('Failed to load my events bundle. Response was null.');
      return null;
    }

    if (response is! Map || response['code'] != 200) {
      final code = response is Map ? response['code'] : 'N/A';
      final message =
          response is Map ? response['message'] : response.toString();
      AppLogger.error(
          'Failed to load my events bundle. Code: $code, Message: $message');
      return null;
    }

    final data = response['data'] as Map<String, dynamic>;

    // ---- EVENT PROCESSING (Main events) ----
    List<EventModel> events = GetEventsHelper.parseEvents(data);
    final List<PlaceModel> placesListForEvents =
        GetEventsHelper.parsePlaces(data);
    final List<EventUserCount> usersCountList =
        GetEventsHelper.parseEventUsers(data);
    final List<EventUserSavedCount> usersSavedList =
        GetEventsHelper.parseEventUsersSaved(data);
    final List<EventGroupModel> groupsList =
        GetEventsHelper.parseEventGroups(data);

    // build lookup maps
    final placeById = {for (var p in placesListForEvents) p.id!: p};
    final groupsByParent = <int, List<EventGroupModel>>{};
    final parentsByChild = <int, List<EventGroupModel>>{};
    for (var g in groupsList) {
      groupsByParent.putIfAbsent(g.eventParent, () => []).add(g);
      parentsByChild.putIfAbsent(g.eventChild, () => []).add(g);
    }

    final usersByEvent = {for (var u in usersCountList) u.eventId: u.count};
    final savedByEvent = {for (var s in usersSavedList) s.eventId: s.count};

    for (var ev in events) {
      if (ev.place?.id != null) {
        ev.place = placeById[ev.place!.id];
      }

      ev.childEventIds =
          groupsByParent[ev.id!]?.map((g) => g.eventChild).toList();
      ev.parentEventIds =
          parentsByChild[ev.id!]?.map((g) => g.eventParent).toList();

      for (var e in events) {
        var children = events
            .where((ev) => ev.parentEventIds?.contains(e.id) ?? false)
            .toList();
        e.childEvents = children;
      }

      ev.currentParticipants = usersByEvent[ev.id!];
      ev.currentUsersSaved = savedByEvent[ev.id!];
    }

    events = events.sortEvents();

    // ---- ACTIVITY PROCESSING ----
    final List<ActivityEventModel> activityRelatedEvents =
        ActivityDataHelper.parseEvents(data);
    final List<ActivityPlaceModel> activityRelatedPlaces =
        ActivityDataHelper.parsePlaces(data);
    final List<ActivityModel> activitiesList =
        ActivityDataHelper.parseActivities(data);
    final List<ActivityAssignmentModel> assignmentsList =
        ActivityDataHelper.parseActivityAssignments(data);
    final List<ActivityUserInfoModel> usersList =
        ActivityDataHelper.parseUsers(data);
    final userMapById = {
      for (var u in usersList)
        if (u.id != null) u.id!: u
    };

    final linkEventList = (data['assignment_events'] as List<dynamic>?)
            ?.map((item) =>
                AssignmentEventLinkModel.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [];
    final linkPlaceList = (data['assignment_places'] as List<dynamic>?)
            ?.map((item) =>
                AssignmentPlaceLinkModel.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [];

    final activityEventByIdMap = {
      for (var e in activityRelatedEvents)
        if (e.id != null) e.id!: e
    };
    final activityPlaceByIdMap = {
      for (var p in activityRelatedPlaces)
        if (p.id != null) p.id!: p
    };

    final eventsByAssignmentId = <String, List<int>>{};
    for (var link in linkEventList) {
      if (link.assignmentId != null && link.eventId != null) {
        eventsByAssignmentId
            .putIfAbsent(link.assignmentId!, () => [])
            .add(link.eventId!);
      }
    }
    final placesByAssignmentId = <String, List<int>>{};
    for (var link in linkPlaceList) {
      if (link.assignmentId != null && link.placeId != null) {
        placesByAssignmentId
            .putIfAbsent(link.assignmentId!, () => [])
            .add(link.placeId!);
      }
    }

    for (var assignment in assignmentsList) {
      final eventIdsForCurrentAssignment =
          eventsByAssignmentId[assignment.id] ?? [];
      assignment.events = eventIdsForCurrentAssignment
          .map((id) => activityEventByIdMap[id])
          .whereType<ActivityEventModel>()
          .toList();

      final placeIdsForCurrentAssignment =
          placesByAssignmentId[assignment.id] ?? [];
      assignment.places = placeIdsForCurrentAssignment
          .map((id) => activityPlaceByIdMap[id])
          .whereType<ActivityPlaceModel>()
          .toList();

      if (assignment.userInfo != null &&
          userMapById.containsKey(assignment.userInfo)) {
        assignment.user = userMapById[assignment.userInfo!];
      }
    }

    // MODIFIED: The key of this map is changed from int to String to support UUIDs.
    final assignmentsByActivityId = <String, List<ActivityAssignmentModel>>{};
    for (var asg in assignmentsList) {
      final activityId = asg.activityId;
      if (activityId != null) {
        assignmentsByActivityId.putIfAbsent(activityId, () => []).add(asg);
      }
    }
    for (var activity in activitiesList) {
      activity.assignments = assignmentsByActivityId[activity.id] ?? [];
    }

    return MyEventsBundle(
      events: events,
      activities: activitiesList,
    );
  }
}

class MyEventsBundle {
  final List<EventModel> events;
  final List<ActivityModel> activities;

  MyEventsBundle({
    required this.events,
    required this.activities,
  });
}
