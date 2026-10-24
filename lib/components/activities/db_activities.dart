import 'package:flutter/material.dart';
import 'package:fstapp/components/activities/activities_component_strings.dart';
import 'package:fstapp/components/activities/activity_data_helper.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/activities/activity_model.dart';
import 'package:fstapp/components/activities/activity_commands.dart';

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
  static ActivityCommands get _commands => SupabaseActivityCommands(_supabase);

  static Future<EditDataBundle?> getForEdit(int occasionId) async {
    final resp = await _supabase.rpc(
      'get_activities_for_edit',
      params: {'p_occasion': occasionId},
    );

    if (resp == null) {
      return null;
    }

    final Map<String, dynamic>? responseMap = resp as Map<String, dynamic>?;
    if (responseMap == null ||
        responseMap['code'] != 200 ||
        responseMap['data'] == null) {
      return null;
    }

    final data = responseMap['data'] as Map<String, dynamic>;

    final bundle = EditDataBundle(
      users: ActivityDataHelper.parseUsers(data),
      events: ActivityDataHelper.parseEvents(data),
      places: ActivityDataHelper.parsePlaces(data),
      activities: ActivityDataHelper.parseActivities(data),
      assignmentPlaceLinks: ActivityDataHelper.parseAssignmentPlaceLinks(data),
      assignmentEventLinks: ActivityDataHelper.parseAssignmentEventLinks(data),
      activityAssignments: ActivityDataHelper.parseActivityAssignments(data),
      aggregateVersion: (data['aggregate_version'] as num?)?.toInt() ?? 0,
    );

    ActivityDataHelper.linkAssignmentsToActivities(bundle);
    return bundle;
  }

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
    final historyPayload = bundle.toJsonEditor();
    if ((historyPayload['activities'] as List?)?.isEmpty ?? true) return null;

    try {
      final response = await _supabase.rpc(
        'save_activity_history',
        params: {
          'p_occasion_id': occasionId,
          'p_activities_data': historyPayload,
          'p_history_type': 'AUTOSAVE',
          'p_parent_history_id': bundle.parentHistoryId,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      return {'code': 500, 'message': 'An unexpected error occurred.'};
    }
  }

  static Future<void> saveActivitiesForEdit(
      BuildContext context, int occasionId, EditDataBundle bundle) async {
    final historyPayload = bundle.toJsonEditor();
    if (bundle.autosaveHistoryId != null && bundle.autosaveCreatedAt != null) {
      historyPayload['_consume_autosave'] = {
        'id': bundle.autosaveHistoryId,
        'created_at': bundle.autosaveCreatedAt!.toUtc().toIso8601String(),
      };
    }
    final updatePayload = _buildUpdatePayload(bundle);

    final result = await _commands.publish(
      occasionId: occasionId,
      expectedVersion: bundle.aggregateVersion,
      activities: updatePayload,
      history: historyPayload,
      parentHistoryId: bundle.parentHistoryId,
    );
    if (result.status == 'conflict') {
      throw StateError('Activities were changed by another editor');
    }
    if (result.status == 'rejected') {
      throw StateError('Activities publish was rejected');
    }
    bundle.aggregateVersion = result.version;
    bundle.parentHistoryId = result.historyId ?? bundle.parentHistoryId;
    if (context.mounted) {
      ToastHelper.Show(
          context, ActivitiesComponentStrings.publishedSuccessfully,
          severity: ToastSeverity.Ok);
    }
    return;
  }

  static Future<AutosaveInfo> getAutosaveAndPublishInfo(int occasionId) async {
    final resp = await _supabase.rpc(
      'get_latest_autosave', // This now calls the combined SQL function
      params: {'p_occasion_id': occasionId},
    );

    final responseMap = resp as Map<String, dynamic>?;
    if (responseMap == null ||
        responseMap['code'] != 200 ||
        responseMap['data'] == null) {
      return AutosaveInfo(); // Return empty object on failure
    }

    final data = responseMap['data'] as Map<String, dynamic>;
    final latestPublishId = data['latest_publish_id'] as int?;
    final autosaveData = data['autosave'] as Map<String, dynamic>?;

    EditDataBundle? bundle;
    if (autosaveData != null) {
      final bundleJson =
          autosaveData['activities_data'] as Map<String, dynamic>;
      bundle = EditDataBundle.fromJson(bundleJson)
        ..autosaveHistoryId = (autosaveData['id'] as num).toInt()
        ..autosaveCreatedAt =
            DateTime.parse(autosaveData['created_at'] as String);
    }

    return AutosaveInfo(
        autosavedBundle: bundle, latestPublishId: latestPublishId);
  }

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

  static Future<void> deleteAutosave(int occasionId) async {
    try {
      await _supabase.rpc(
        'delete_autosave_history',
        params: {'p_occasion_id': occasionId},
      );
    } catch (e) {
      // It's okay to fail silently here, as the main publish operation succeeded.
      // We just log the error for debugging.
      // Could not delete autosave history
    }
  }
}

class AutosaveInfo {
  final EditDataBundle? autosavedBundle;
  final int? latestPublishId;

  AutosaveInfo({this.autosavedBundle, this.latestPublishId});
}
