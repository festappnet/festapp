import 'package:fstapp/services/time_helper.dart';
import 'package:festapp_core/program.dart';

import 'package:festapp_core/map.dart';

/// Model for linking parent and child events
class EventGroupModel {
  final int eventParent;
  final int eventChild;

  EventGroupModel({required this.eventParent, required this.eventChild});

  factory EventGroupModel.fromJson(Map<String, dynamic> json) =>
      EventGroupModel(
        eventParent: json['event_parent'] as int,
        eventChild: json['event_child'] as int,
      );
}

/// Model for event-role association
class EventRoleModel {
  final int eventId;
  final int roleId;

  EventRoleModel({required this.eventId, required this.roleId});

  factory EventRoleModel.fromJson(Map<String, dynamic> json) => EventRoleModel(
        eventId: json['event'] as int,
        roleId: json['role'] as int,
      );
}

/// Model for counting users signed in per event
class EventUserCount {
  final int eventId;
  final int count;

  EventUserCount({required this.eventId, required this.count});

  factory EventUserCount.fromJson(Map<String, dynamic> json) => EventUserCount(
        eventId: json['event'] as int,
        count: json['count'] as int,
      );
}

/// Model for counting users who saved the event
class EventUserSavedCount {
  final int eventId;
  final int count;

  EventUserSavedCount({required this.eventId, required this.count});

  factory EventUserSavedCount.fromJson(Map<String, dynamic> json) =>
      EventUserSavedCount(
        eventId: json['event'] as int,
        count: json['count'] as int,
      );
}

/// Helper to parse JSON returned by `get_events`
class GetEventsHelper {
  static List<EventModel> parseEvents(Map<String, dynamic> json) {
    final data = json['events'] as List<dynamic>?;
    if (data == null) return [];
    return data
        .cast<Map<String, dynamic>>()
        .map((e) => EventModel.fromJson(e, timeContext: TimeHelper.eventTime))
        .toList();
  }

  static List<PlaceModel> parsePlaces(Map<String, dynamic> json) {
    final data = json['places'] as List<dynamic>?;
    if (data == null) return [];
    return data
        .cast<Map<String, dynamic>>()
        .map((p) => PlaceModel.fromJson(p))
        .toList();
  }

  static List<EventGroupModel> parseEventGroups(Map<String, dynamic> json) {
    final data = json['event_groups'] as List<dynamic>?;
    if (data == null) return [];
    return data
        .cast<Map<String, dynamic>>()
        .map((g) => EventGroupModel.fromJson(g))
        .toList();
  }

  static List<EventRoleModel> parseEventRoles(Map<String, dynamic> json) {
    final data = json['event_roles'] as List<dynamic>?;
    if (data == null) return [];
    return data
        .cast<Map<String, dynamic>>()
        .map((r) => EventRoleModel.fromJson(r))
        .toList();
  }

  static List<EventUserCount> parseEventUsers(Map<String, dynamic> json) {
    final data = json['event_users'] as List<dynamic>?;
    if (data == null) return [];
    return data
        .cast<Map<String, dynamic>>()
        .map((u) => EventUserCount.fromJson(u))
        .toList();
  }

  static List<EventUserSavedCount> parseEventUsersSaved(
      Map<String, dynamic> json) {
    final data = json['event_users_saved'] as List<dynamic>?;
    if (data == null) return [];
    return data
        .cast<Map<String, dynamic>>()
        .map((s) => EventUserSavedCount.fromJson(s))
        .toList();
  }
}
