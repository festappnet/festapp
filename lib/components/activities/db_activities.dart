import 'package:flutter/material.dart';
import 'package:fstapp/components/activities/activities_component_strings.dart';
import 'package:fstapp/components/activities/activity_data_helper.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/activities/activity_model.dart';
import 'package:fstapp/components/activities/activity_commands.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';

class ActivityHistoryInfo {
  final int id;
  final DateTime createdAt;
  final String historyType;
  final String? note;
  final String? userName;
  final String? userSurname;

  ActivityHistoryInfo.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        createdAt = DateTime.parse(json['created_at']),
        historyType = json['history_type'],
        note = json['note'],
        userName = json['user_name'],
        userSurname = json['user_surname'];

  String get userFullName => ("${userName ?? ''} ${userSurname ?? ''}").trim();
}

class DbActivities {
  static final _supabase = Supabase.instance.client;
  static final ActivityCommands _commands = SupabaseActivityCommands(_supabase);

  static Future<ActivityEditorSession> getEditorSession(int occasionId) async {
    final raw = await _supabase.rpc('get_activity_editor_session_v1',
        params: {'p_occasion': occasionId});
    if (raw is! Map || raw['code'] != 200) {
      throw StateError('Activity editor unavailable');
    }
    final data = (raw['editBundle'] as Map).cast<String, dynamic>();
    final bundle = EditDataBundle(
        users: ActivityDataHelper.parseUsers(data),
        events: ActivityDataHelper.parseEvents(data),
        places: ActivityDataHelper.parsePlaces(data),
        activities: ActivityDataHelper.parseActivities(data),
        assignmentPlaceLinks:
            ActivityDataHelper.parseAssignmentPlaceLinks(data),
        assignmentEventLinks:
            ActivityDataHelper.parseAssignmentEventLinks(data),
        activityAssignments: ActivityDataHelper.parseActivityAssignments(data),
        aggregateVersion: (raw['liveVersion'] as num).toInt(),
        parentHistoryId: (raw['latestPublishId'] as num?)?.toInt(),
        id: (raw['draftId'] as num?)?.toInt());
    ActivityDataHelper.linkAssignmentsToActivities(bundle);
    final draft = raw['draftData'] is Map
        ? EditDataBundle.fromJson(
            (raw['draftData'] as Map).cast<String, dynamic>())
        : null;
    if (draft != null) {
      draft.id = bundle.id;
      draft.parentHistoryId = (raw['draftParentHistoryId'] as num?)?.toInt();
      draft.aggregateVersion = bundle.aggregateVersion;
    }
    return ActivityEditorSession(
        bundle,
        AutosaveInfo(
            autosavedBundle: draft, latestPublishId: bundle.parentHistoryId));
  }

  static Future<EditDataBundle?> getForEdit(int occasionId) async =>
      (await getEditorSession(occasionId)).bundle;

  static List<Map<String, dynamic>> _buildUpdatePayload(EditDataBundle bundle) {
    List<Map<String, dynamic>> activitiesPayload = [];
    if (bundle.activities == null) return activitiesPayload;

    for (var activity in bundle.activities!) {
      List<Map<String, dynamic>> allAssignmentsPayload = [];
      if (activity.assignments != null) {
        for (var assignment in activity.assignments!) {
          List<int> assignmentPlaceIds =
              assignment.places.map((p) => p.id).whereType<int>().toList();
          List<int> assignmentEventIds =
              assignment.events.map((e) => e.id).whereType<int>().toList();

          allAssignmentsPayload.add({
            'id': assignment.id,
            'user': assignment.userInfo,
            'start_time':
                assignment.startTime?.toUtcFromOccasionTime().toIso8601String(),
            'end_time':
                assignment.endTime?.toUtcFromOccasionTime().toIso8601String(),
            'title': assignment.title,
            'description': assignment.description,
            'data': assignment.data,
            'linked_place_ids': assignmentPlaceIds,
            'linked_event_ids': assignmentEventIds,
          });
        }
      }
      activitiesPayload.add({
        'id': activity.id,
        'title': activity.title,
        'description': activity.description,
        'type': activity.type,
        'unit': activity.unit,
        'is_hidden': activity.isHidden,
        'order': activity.order,
        'data': activity.data,
        'assignments': allAssignmentsPayload,
      });
    }
    return activitiesPayload;
  }

  static Future<Map<String, dynamic>?> autosaveActivities(
      int occasionId, EditDataBundle bundle) async {
    final result = await _commands.saveDraft(
        occasionId: occasionId,
        expectedVersion: bundle.aggregateVersion,
        history: bundle.toJsonEditor(),
        parentHistoryId: bundle.parentHistoryId);
    if (result.status == 'applied' || result.status == 'unchanged')
      bundle.id = result.draftId;
    return {
      'code': result.status == 'conflict'
          ? 409
          : result.status == 'rejected'
              ? 400
              : 200,
      'data': {
        'version': result.version,
        'draft_id': result.draftId,
        'latest_publish_id': result.latestPublishId
      }
    };
  }

  static Future<PublishActivitiesResult> saveActivitiesForEdit(
      BuildContext context, int occasionId, EditDataBundle bundle) async {
    final token = ClientSyncRuntime.mutationContextToken;
    final actor = _supabase.auth.currentUser?.id;
    final result = await _commands.publish(
        occasionId: occasionId,
        expectedVersion: bundle.aggregateVersion,
        activities: _buildUpdatePayload(bundle),
        history: bundle.toJsonEditor(),
        parentHistoryId: bundle.parentHistoryId);
    if (result.status == 'conflict') {
      throw StateError('Activities were changed by another editor');
    }
    if (result.status == 'rejected') {
      throw StateError('Activities publish was rejected');
    }
    if (ClientSyncRuntime.isCurrentMutationContext(token) &&
        _supabase.auth.currentUser?.id == actor &&
        result.version >= bundle.aggregateVersion) {
      bundle.aggregateVersion = result.version;
      bundle.parentHistoryId = result.historyId;
      bundle.id = null;
      if (context.mounted)
        ToastHelper.Show(
            context, ActivitiesComponentStrings.publishedSuccessfully,
            severity: ToastSeverity.Ok);
    }
    return result;
  }

  static Future<AutosaveInfo> getAutosaveAndPublishInfo(int occasionId) async =>
      (await getEditorSession(occasionId)).autosave;

  static Future<List<ActivityHistoryInfo>> listActivityHistory(
      int occasionId) async {
    final resp = await _supabase.rpc(
      'list_activity_history',
      params: {'p_occasion_id': occasionId},
    );

    final responseMap = resp as Map<String, dynamic>?;
    if (responseMap == null ||
        responseMap['code'] != 200 ||
        responseMap['data'] == null) {
      return [];
    }

    final dataList = responseMap['data'] as List;
    return dataList
        .map((item) =>
            ActivityHistoryInfo.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<EditDataBundle?> getActivityHistoryVersion(
      int occasionId, int historyId) async {
    final resp = await _supabase.rpc(
      'get_activity_history_version',
      params: {'p_history_id': historyId},
    );

    final responseMap = resp as Map<String, dynamic>?;
    if (responseMap == null ||
        responseMap['code'] != 200 ||
        responseMap['data'] == null) {
      return null;
    }

    final historyData = responseMap['data'] as Map<String, dynamic>;
    final bundleJson = historyData['activities_data'] as Map<String, dynamic>;
    final bundle = EditDataBundle.fromJson(bundleJson);
    return bundle;
  }

  static Future<void> deleteAutosave(int occasionId,
      {required int? expectedDraftId}) async {
    final result = await _commands.discardDraft(
        occasionId: occasionId, expectedDraftId: expectedDraftId);
    if (result.status == 'conflict' || result.status == 'rejected') {
      throw StateError('Draft changed in another editor');
    }
  }
}

class ActivityEditorSession {
  const ActivityEditorSession(this.bundle, this.autosave);
  final EditDataBundle bundle;
  final AutosaveInfo autosave;
}

class AutosaveInfo {
  final EditDataBundle? autosavedBundle;
  final int? latestPublishId;

  AutosaveInfo({this.autosavedBundle, this.latestPublishId});
}
