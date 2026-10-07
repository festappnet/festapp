import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:uuid/uuid.dart';

class ActivityPlaceModel {
  final int? id;
  final String? title;

  ActivityPlaceModel({this.id, this.title});

  factory ActivityPlaceModel.fromJson(Map<String, dynamic> json) {
    return ActivityPlaceModel(
      id: json[Tb.places.id] as int?,
      title: json[Tb.places.title] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      Tb.places.id: id,
    };
  }
}

class ActivityEventModel {
  final int? id;
  final String? title;
  final DateTime startTime;
  final DateTime endTime;
  final ActivityPlaceModel? place;

  ActivityEventModel(
      {this.id,
      this.title,
      required this.startTime,
      required this.endTime,
      this.place});

  factory ActivityEventModel.fromJson(Map<String, dynamic> json) {
    return ActivityEventModel(
        id: json[Tb.events.id] as int?,
        title: json[Tb.events.title] as String?,
        startTime: (json[Tb.events.start_time] != null
            ? DateTime.parse(json[Tb.events.start_time] as String)
                .toOccasionTime()
            : DateTime.fromMicrosecondsSinceEpoch(0)),
        endTime: (json[Tb.events.end_time] != null
            ? DateTime.parse(json[Tb.events.end_time] as String)
                .toOccasionTime()
            : DateTime.fromMicrosecondsSinceEpoch(0)),
        place: json[Tb.places.table] != null
            ? ActivityPlaceModel.fromJson(json[Tb.places.table])
            : null);
  }

  Map<String, dynamic> toJson() {
    return {
      Tb.events.id: id,
    };
  }
}

class ActivityUserInfoModel {
  final String? id;
  final String? name;
  final String? surname;

  ActivityUserInfoModel({this.id, this.name, this.surname});

  factory ActivityUserInfoModel.fromJson(Map<String, dynamic> json) {
    return ActivityUserInfoModel(
      id: json[Tb.user_info.id] as String?,
      name: json[Tb.user_info.name] as String?,
      surname: json[Tb.user_info.surname] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      Tb.user_info.id: id,
    };
  }

  String toFullNameString() {
    return "${name ?? ""} ${surname ?? ""}".trim();
  }

  String getInitials() {
    final String fullName = toFullNameString();
    if (fullName.isEmpty) return '';
    return fullName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .take(2)
        .join();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityUserInfoModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

var _uuid = Uuid();

class ActivityModel {
  final String id;
  DateTime? createdAt;
  DateTime? updatedAt;
  String? title;
  String? description;
  String? type;
  int? occasion;
  int? unit;
  bool? isHidden;
  int? order;
  Map<String, dynamic>? data;
  List<ActivityAssignmentModel>? assignments;

  ActivityModel({
    String? id,
    this.createdAt,
    this.updatedAt,
    this.title,
    this.description,
    this.type,
    this.occasion,
    this.unit,
    this.isHidden,
    this.order,
    this.data,
    this.assignments,
  }) : id = id ?? _uuid.v4();

  factory ActivityModel.fromJson(Map<String, dynamic> j) {
    return ActivityModel(
      id: j[Tb.activities.id] as String,
      createdAt: j[Tb.activities.created_at] != null
          ? DateTime.parse(j[Tb.activities.created_at] as String)
          : null,
      updatedAt: j[Tb.activities.updated_at] != null
          ? DateTime.parse(j[Tb.activities.updated_at] as String)
          : null,
      title: j[Tb.activities.title] as String?,
      description: j[Tb.activities.description] as String?,
      type: j[Tb.activities.type] as String?,
      occasion: j[Tb.activities.occasion] as int?,
      unit: j[Tb.activities.unit] as int?,
      isHidden: j[Tb.activities.is_hidden] as bool?,
      order: j[Tb.activities.order] as int?,
      data: (j[Tb.activities.data] as Map?)?.cast<String, dynamic>(),
      assignments: (j[Tb.activity_assignments.table] as List<dynamic>?)
              ?.map((a) =>
                  ActivityAssignmentModel.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [], // Populate from JSON, default to empty list
    );
  }

  Map<String, dynamic> toJson() {
    return {
      Tb.activities.id: id,
      Tb.activities.created_at: createdAt?.toIso8601String(),
      Tb.activities.updated_at: updatedAt?.toIso8601String(),
      Tb.activities.title: title,
      Tb.activities.description: description,
      Tb.activities.type: type,
      Tb.activities.occasion: occasion,
      Tb.activities.unit: unit,
      Tb.activities.is_hidden: isHidden,
      Tb.activities.order: order,
      Tb.activities.data: data,
      Tb.activity_assignments.table:
          assignments?.map((e) => e.toJson()).toList(),
    };
  }

  Map<String, dynamic> toJsonEditor() {
    return {
      Tb.activities.id: id,
      Tb.activities.created_at: createdAt?.toIso8601String(),
      Tb.activities.updated_at: updatedAt?.toIso8601String(),
      Tb.activities.title: title,
      Tb.activities.description: description,
      Tb.activities.type: type,
      Tb.activities.occasion: occasion,
      Tb.activities.unit: unit,
      Tb.activities.is_hidden: isHidden,
      Tb.activities.order: order,
      Tb.activities.data: data,
    };
  }
}

class AssignmentPlaceLinkModel {
  String? assignmentId;
  int? placeId;

  AssignmentPlaceLinkModel({this.assignmentId, this.placeId});

  factory AssignmentPlaceLinkModel.fromJson(Map<String, dynamic> j) {
    return AssignmentPlaceLinkModel(
      assignmentId: j[Tb.activity_assignment_places.assignment_id] as String?,
      placeId: j[Tb.activity_assignment_places.place_id] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      Tb.activity_assignment_places.assignment_id: assignmentId,
      Tb.activity_assignment_places.place_id: placeId,
    };
  }
}

class AssignmentEventLinkModel {
  String? assignmentId;
  int? eventId;

  AssignmentEventLinkModel({this.assignmentId, this.eventId});

  factory AssignmentEventLinkModel.fromJson(Map<String, dynamic> j) {
    return AssignmentEventLinkModel(
      assignmentId: j[Tb.activity_assignment_events.assignment_id] as String?,
      eventId: j[Tb.activity_assignment_events.event_id] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      Tb.activity_assignment_events.assignment_id: assignmentId,
      Tb.activity_assignment_events.event_id: eventId,
    };
  }
}

class ActivityAssignmentModel {
  final String id;
  String? activityId;
  ActivityUserInfoModel? user;
  String? userInfo;
  DateTime? startTime;
  DateTime? endTime;
  String? title;
  String? description;
  Map<String, dynamic>? data;
  List<ActivityPlaceModel> places;
  List<ActivityEventModel> events;

  ActivityAssignmentModel({
    String? id,
    this.activityId,
    this.userInfo,
    this.startTime,
    this.endTime,
    this.title,
    this.description,
    this.data,
    required this.user,
    List<ActivityPlaceModel>? places,
    List<ActivityEventModel>? events,
  })  : id = id ?? _uuid.v4(),
        places = places ?? [],
        events = events ?? [];

  factory ActivityAssignmentModel.fromJson(Map<String, dynamic> j) {
    String? parsedId = j[Tb.activity_assignments.id] as String?;
    return ActivityAssignmentModel(
      id: parsedId ?? _uuid.v4(),
      activityId: j[Tb.activity_assignments.activity_id] as String?,
      userInfo: j[Tb.activity_assignments.user] as String?,
      startTime: j[Tb.activity_assignments.start_time] != null
          ? DateTime.parse(j[Tb.activity_assignments.start_time] as String)
              .toOccasionTime()
          : null,
      endTime: j[Tb.activity_assignments.end_time] != null
          ? DateTime.parse(j[Tb.activity_assignments.end_time] as String)
              .toOccasionTime()
          : null,
      title: j[Tb.activity_assignments.title] as String?,
      description: j[Tb.activity_assignments.description] as String?,
      data: (j[Tb.activity_assignments.data] as Map?)?.cast<String, dynamic>(),
      places: (j[Tb.activity_assignment_places.table] as List<dynamic>?)
              ?.map(
                  (p) => ActivityPlaceModel.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      events: (j[Tb.activity_assignment_events.table] as List<dynamic>?)
              ?.map(
                  (e) => ActivityEventModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      user: j[Tb.user_info.table] != null
          ? ActivityUserInfoModel.fromJson(
              j[Tb.user_info.table] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      Tb.activity_assignments.id: id,
      Tb.activity_assignments.activity_id: activityId,
      Tb.activity_assignments.user: userInfo,
      Tb.activity_assignments.start_time:
          startTime?.toUtcFromOccasionTime().toIso8601String(),
      Tb.activity_assignments.end_time:
          endTime?.toUtcFromOccasionTime().toIso8601String(),
      Tb.activity_assignments.title: title,
      Tb.activity_assignments.description: description,
      Tb.activity_assignments.data: data,
      Tb.activity_assignment_places.table:
          places.map((e) => e.toJson()).toList(),
      Tb.activity_assignment_events.table:
          events.map((e) => e.toJson()).toList(),
      Tb.user_info.table: user?.toJson(),
    };
  }

  Map<String, dynamic> toJsonEditor() {
    return {
      Tb.activity_assignments.id: id,
      Tb.activity_assignments.activity_id: activityId,
      Tb.activity_assignments.user: userInfo,
      Tb.activity_assignments.start_time:
          startTime?.toUtcFromOccasionTime().toIso8601String(),
      Tb.activity_assignments.end_time:
          endTime?.toUtcFromOccasionTime().toIso8601String(),
      Tb.activity_assignments.title: title,
      Tb.activity_assignments.description: description,
      Tb.activity_assignments.data: data,
      Tb.user_info.table: user?.toJson(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityAssignmentModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class EditDataBundle {
  int? id;
  int? parentHistoryId;
  int aggregateVersion;

  List<ActivityEventModel>? events;
  List<ActivityPlaceModel>? places;
  List<ActivityModel>? activities;
  List<ActivityUserInfoModel>? users;
  List<AssignmentPlaceLinkModel>? assignmentPlaceLinks;
  List<AssignmentEventLinkModel>? assignmentEventLinks;
  List<ActivityAssignmentModel>? activityAssignments;

  EditDataBundle({
    this.events,
    this.places,
    this.activities,
    this.users,
    this.assignmentPlaceLinks,
    this.assignmentEventLinks,
    this.activityAssignments,
    this.id,
    this.parentHistoryId,
    this.aggregateVersion = 0,
  });

  void retainSessionFrom(EditDataBundle current) {
    aggregateVersion = current.aggregateVersion;
    parentHistoryId = current.parentHistoryId;
    id = current.id;
  }

  factory EditDataBundle.fromJson(Map<String, dynamic> j) {
    return EditDataBundle(
      id: j['id'] as int?,
      parentHistoryId: j['parent_history_id'] as int?,
      aggregateVersion: (j['aggregate_version'] as num?)?.toInt() ?? 0,
      events: (j['events'] as List<dynamic>?)
          ?.map((e) => ActivityEventModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      places: (j['places'] as List<dynamic>?)
          ?.map((p) => ActivityPlaceModel.fromJson(p as Map<String, dynamic>))
          .toList(),
      activities: (j[Tb.activities.table] as List<dynamic>?)
          ?.map((a) => ActivityModel.fromJson(a as Map<String, dynamic>))
          .toList(),
      users: (j[Tb.user_info.table] as List<dynamic>?)
          ?.map(
              (u) => ActivityUserInfoModel.fromJson(u as Map<String, dynamic>))
          .toList(),
      assignmentPlaceLinks: (j['assignmentPlaceLinks'] as List<dynamic>?)
          ?.map((l) =>
              AssignmentPlaceLinkModel.fromJson(l as Map<String, dynamic>))
          .toList(),
      assignmentEventLinks: (j['assignmentEventLinks'] as List<dynamic>?)
          ?.map((l) =>
              AssignmentEventLinkModel.fromJson(l as Map<String, dynamic>))
          .toList(),
      activityAssignments: (j[Tb.activity_assignments.table] as List<dynamic>?)
          ?.map((a) =>
              ActivityAssignmentModel.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  factory EditDataBundle.fromJsonHistory(Map<String, dynamic> j) {
    return EditDataBundle(
      id: j['id'] as int?,
      parentHistoryId: j['parent_history_id'] as int?,
      aggregateVersion: (j['aggregate_version'] as num?)?.toInt() ?? 0,
      activities: (j[Tb.activities.table] as List<dynamic>?)
          ?.map((a) => ActivityModel.fromJson(a as Map<String, dynamic>))
          .toList(),
      activityAssignments: (j[Tb.activity_assignments.table] as List<dynamic>?)
          ?.map((a) =>
              ActivityAssignmentModel.fromJson(a as Map<String, dynamic>))
          .toList(),
      assignmentPlaceLinks: (j['assignmentPlaceLinks'] as List<dynamic>?)
          ?.map((l) =>
              AssignmentPlaceLinkModel.fromJson(l as Map<String, dynamic>))
          .toList(),
      assignmentEventLinks: (j['assignmentEventLinks'] as List<dynamic>?)
          ?.map((l) =>
              AssignmentEventLinkModel.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJsonHistory() {
    return {
      'id': id,
      'parent_history_id': parentHistoryId,
      Tb.activities.table: activities?.map((a) => a.toJsonEditor()).toList(),
      Tb.activity_assignments.table:
          activityAssignments?.map((a) => a.toJson()).toList(),
      'assignmentPlaceLinks':
          assignmentPlaceLinks?.map((l) => l.toJson()).toList(),
      'assignmentEventLinks':
          assignmentEventLinks?.map((l) => l.toJson()).toList(),
    };
  }

  Map<String, dynamic> toJsonEditor() {
    // First, get a flat list of all assignments from within all activities.
    final allAssignments =
        activities?.expand((activity) => activity.assignments ?? []).toList() ??
            [];

    // Create the list of place-to-assignment links.
    final placeLinks = allAssignments
        .expand((assignment) =>
            // For each assignment, create a link model for each of its places.
            assignment.places.map((place) => AssignmentPlaceLinkModel(
                  assignmentId: assignment.id,
                  placeId: place.id,
                )))
        .toList();

    // Create the list of event-to-assignment links.
    final eventLinks = allAssignments
        .expand((assignment) =>
            // For each assignment, create a link model for each of its events.
            assignment.events.map((event) => AssignmentEventLinkModel(
                  assignmentId: assignment.id,
                  eventId: event.id,
                )))
        .toList();

    return {
      // Canonical history times use the same UTC instants as the live graph.
      'schemaVersion': 1,
      'timeBasis': 'UTC',
      'id': id,
      'parent_history_id': parentHistoryId,

      Tb.activities.table: activities?.map((a) => a.toJson()).toList(),
      Tb.activity_assignments.table: [
        for (final activity in activities ?? <ActivityModel>[])
          for (final assignment
              in activity.assignments ?? <ActivityAssignmentModel>[])
            {...assignment.toJson(), 'activity_id': activity.id}
      ],
      'assignmentPlaceLinks': placeLinks.map((l) => l.toJson()).toList(),
      'assignmentEventLinks': eventLinks.map((l) => l.toJson()).toList(),
    };
  }
}
