import 'dart:collection';
import 'package:festapp_core/map.dart';
import 'package:festapp_core/json_values.dart';
import 'package:intl/intl.dart';
import 'occasion_time_context.dart';

const _unchanged = Object();

class EventModel {
  final OccasionTimeContext timeContext;
  final int? maxParticipants;
  final int aggregateVersion;
  final int order;
  final int? id;
  final DateTime? updatedAt;
  final bool? isHidden;
  final Map<String, dynamic>? data;
  final PlaceModel? place;
  final String? type;
  final List<EventModel> childEvents;
  final List<int>? eventRolesIds;
  final List<int>? parentEventIds;
  final List<int>? childEventIds;
  final int? currentParticipants;
  final int? currentUsersSaved;
  final String? title;
  final String? description;
  final bool? isSignedIn;
  final bool? splitForMenWomen;
  final bool? isGroupEvent;
  final bool? isMyGroupEvent;
  final bool? isInMySchedule;
  final int? occasionId;
  final bool isCancelled;
  final DateTime startTime;
  final DateTime endTime;

  String durationCompactStringForLocale(String locale) {
    final weekday = DateFormat('EEEE', locale).format(startTime);
    final shortWeekday = weekday.length <= 2
        ? weekday.toUpperCase()
        : weekday.substring(0, 2).toUpperCase();
    return "$shortWeekday ${DateFormat("d. M. HH:mm", locale).format(startTime)} - ${DateFormat.Hm(locale).format(endTime)}";
  }

  Duration duration() => startTime.isBefore(endTime)
      ? endTime.difference(startTime)
      : Duration.zero;

  /// Flags timing that deserves an editor's attention without preventing
  /// legitimate overnight events from being saved.
  bool get hasSuspiciousTiming =>
      !endTime.isAfter(startTime) ||
      startTime.year != endTime.year ||
      startTime.month != endTime.month ||
      startTime.day != endTime.day;

  bool? canSaveEventToMyProgram() {
    var canSave =
        (maxParticipants == null || maxParticipants == 0) &&
        !isGroupEvent! &&
        (childEventIds == null || childEventIds!.isEmpty);
    if (!canSave) {
      return null;
    }
    return isInMySchedule == false;
  }

  /// A capacity label exists only when the live participant count is known.
  /// Missing live data must not be presented as an authoritative zero.
  String? get participantCapacityLabel {
    final maximum = maxParticipants;
    final current = currentParticipants;
    if (maximum == null || maximum <= 0 || current == null) return null;
    return '$current/$maximum';
  }

  bool canSignIn() {
    return isEventSupportingSignIn(this) &&
        currentParticipants != null &&
        currentParticipants! < maxParticipants!;
  }

  EventModel withCurrentUserRegistration({required bool isRegistered}) {
    if (isSignedIn == isRegistered) return this;

    final participantDelta = isRegistered ? 1 : -1;
    return copyWith(
      currentParticipants: ((currentParticipants ?? 0) + participantDelta)
          .clamp(0, 1 << 31),
      isSignedIn: isRegistered,
    );
  }

  /// A generated counseling slot (get_events strips `false` jsonb values, so
  /// the flag arrives as `true` or absent). Hidden from the main timeline and
  /// offline search but still shown in "My program".
  bool get isCounselingSlot => data?['is_counseling_slot'] == true;

  /// The counseling entry point ("rozcestník") — shows the enter-counseling
  /// button under its description.
  bool get isCounselingEntry => data?['counseling_entry'] == true;

  bool isFull() =>
      currentParticipants != null &&
      maxParticipants != null &&
      currentParticipants! >= maxParticipants!;
  static bool isEventSupportingSignIn(EventModel? event) =>
      event != null &&
      event.maxParticipants != null &&
      event.maxParticipants! > 0;
  static bool isEventFull(EventModel? event) =>
      isEventSupportingSignIn(event) &&
      event!.currentParticipants != null &&
      event.currentParticipants! >= event.maxParticipants!;
  int maxParticipantsNumber() => maxParticipants ?? 0;

  EventModel({
    required this.timeContext,
    this.maxParticipants,
    this.aggregateVersion = 0,
    this.order = 0,
    this.id,
    this.updatedAt,
    this.isHidden = false,
    Map<String, dynamic>? data,
    this.place,
    this.type,
    List<EventModel>? childEvents,
    List<int>? eventRolesIds,
    List<int>? parentEventIds,
    List<int>? childEventIds,
    this.currentParticipants,
    this.currentUsersSaved,
    this.title,
    this.description,
    this.isSignedIn = false,
    this.splitForMenWomen = false,
    this.isGroupEvent = false,
    this.isMyGroupEvent = false,
    this.isInMySchedule,
    this.occasionId,
    this.isCancelled = false,
    required this.startTime,
    required this.endTime,
  }) : data = data == null
           ? null
           : freezeJsonValue(data) as Map<String, dynamic>,
       childEvents = List.unmodifiable(childEvents ?? const []),
       eventRolesIds = eventRolesIds == null
           ? null
           : List.unmodifiable(eventRolesIds),
       parentEventIds = parentEventIds == null
           ? null
           : List.unmodifiable(parentEventIds),
       childEventIds = childEventIds == null
           ? null
           : List.unmodifiable(childEventIds);

  factory EventModel.fromJson(
    Map<String, dynamic> json, {
    required OccasionTimeContext timeContext,
  }) {
    var eventGroups =
        json.containsKey(eventGroupsTable) && json[eventGroupsTable] != null
        ? json[eventGroupsTable]
        : null;
    List<int>? childEventsIds;
    List<int>? parentEventsIds;

    if (eventGroups != null) {
      for (var e in eventGroups) {
        if (e.containsKey(eventChildColumn)) {
          childEventsIds = childEventsIds ?? [];
          childEventsIds.add(e[eventChildColumn]);
        }
        if (e.containsKey(eventParentColumn)) {
          parentEventsIds = parentEventsIds ?? [];
          parentEventsIds.add(e[eventParentColumn]);
        }
      }
    }

    if (json.containsKey(childEventsList)) {
      childEventsIds = childEventsIds ?? [];
      List<dynamic> toAdd = json[childEventsList] ?? [];
      childEventsIds.addAll(
        toAdd.map((e) {
          return e as int;
        }),
      );
    }

    List<int>? eventRoles;
    if (json.containsKey('event_roles')) {
      eventRoles = [];
      List<dynamic> toAdd = json['event_roles'] ?? [];
      eventRoles.addAll(
        toAdd.map((e) {
          return e['role'] as int;
        }),
      );
    }

    Map<String, dynamic>? eventData = json.containsKey(dataColumn)
        ? (json[dataColumn] as Map?)?.cast<String, dynamic>()
        : null;
    bool cancelled = false;
    if (eventData != null && eventData.containsKey('is_cancelled')) {
      cancelled = eventData['is_cancelled'] == true;
    }

    return EventModel(
      timeContext: timeContext,
      startTime: json.containsKey(startTimeColumn)
          ? timeContext.toOccasionTime(DateTime.parse(json[startTimeColumn]))
          : DateTime.fromMicrosecondsSinceEpoch(0),
      endTime: json.containsKey(endTimeColumn)
          ? timeContext.toOccasionTime(DateTime.parse(json[endTimeColumn]))
          : DateTime.fromMicrosecondsSinceEpoch(0),
      id: json[idColumn],
      isHidden: json.containsKey(isHiddenColumn) ? json[isHiddenColumn] : false,
      updatedAt: json[updatedAtColumn] != null
          ? DateTime.parse(json[updatedAtColumn])
          : null,
      title: json.containsKey(titleColumn) ? json[titleColumn] : null,
      description: json.containsKey(descriptionColumn)
          ? json[descriptionColumn]
          : null,
      maxParticipants: json.containsKey(maxParticipantsColumn)
          ? json[maxParticipantsColumn]
          : null,
      aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ?? 0,
      order: (json['order'] as num?)?.toInt() ?? 0,
      data: eventData,
      place: (json.containsKey(placesTable) && json[placesTable] != null)
          ? PlaceModel.fromJson(json[placesTable])
          : json[placeColumn] != null
          ? PlaceModel(
              id: json[placeColumn],
              title: null,
              description: null,
              type: null,
            )
          : null,
      type: json['type'],
      splitForMenWomen: json.containsKey(splitForMenWomenColumn)
          ? json[splitForMenWomenColumn]
          : false,
      isSignedIn: json.containsKey(isSignedInColumn)
          ? json[isSignedInColumn]
          : false,
      isGroupEvent: json.containsKey(isGroupEventColumn)
          ? json[isGroupEventColumn]
          : false,
      isInMySchedule: json.containsKey(isEventInMyProgramColumn)
          ? json[isEventInMyProgramColumn]
          : false,
      childEventIds: childEventsIds,
      parentEventIds: parentEventsIds,
      eventRolesIds: eventRoles,
      currentParticipants: json.containsKey(eventUsersTable)
          ? json[eventUsersTable][0]["count"]
          : json.containsKey(currentParticipantsColumn)
          ? json[currentParticipantsColumn]
          : null,
      currentUsersSaved: json['event_users_saved'] != null
          ? json['event_users_saved'][0]["count"]
          : null,
      occasionId: json.containsKey('occasion') ? json['occasion'] : null,
      isCancelled: cancelled, // Added
    );
  }

  /// Decodes the closed DTO returned by canonical event commands/editor reads.
  factory EventModel.fromCommandJson(
    Map<String, dynamic> json,
    int aggregateVersion, {
    required OccasionTimeContext timeContext,
  }) {
    return EventModel.fromJson({
      ...json,
      'start_time': json['startTime'],
      'end_time': json['endTime'],
      'max_participants': json['maxParticipants'],
      'description': json['description'],
      'place': json['placeId'],
      'split_for_men_women': json['splitForMenWomen'],
      'is_group_event': json['isGroupEvent'],
      'is_hidden': json['isHidden'],
      'event_groups': [
        for (final id in (json['parentEventIds'] as List?) ?? const [])
          {'event_parent': id},
        for (final id in (json['childEventIds'] as List?) ?? const [])
          {'event_child': id},
      ],
      'event_roles': [
        for (final id in (json['eventRoleIds'] as List?) ?? const [])
          {'role': id},
      ],
      'aggregate_version': aggregateVersion,
    }, timeContext: timeContext);
  }

  static const String startTimeColumn = "start_time";
  static const String endTimeColumn = "end_time";
  static const String idColumn = "id";
  static const String titleColumn = "title";
  static const String descriptionColumn = "description";
  static const String childEventsList = "childEvents";
  static const String updatedAtColumn = "updated_at";
  static const String isHiddenColumn = "is_hidden";
  static const String dataColumn = "data";

  static const String maxParticipantsColumn = "max_participants";
  static const String placeColumn = "place";
  static const String placesTable = "places";
  static const String eventTable = "events";
  static const String eventsLastUpdate = "lastUpdate";
  static const String eventUsersTable = "event_users";

  static const String eventUsersSavedTable = "event_users_saved";
  static const String eventUsersSavedEventColumn = "event";
  static const String eventUsersSavedUserColumn = "user";

  static const String eventGroupsTable = "event_groups";
  static const String eventChildColumn = "event_child";
  static const String eventParentColumn = "event_parent";

  static const String splitForMenWomenColumn = "split_for_men_women";
  static const String isGroupEventColumn = "is_group_event";

  static const String currentParticipantsColumn = "currentParticipants";
  static const String aggregateVersionColumn = 'aggregate_version';
  static const String isSignedInColumn = "isSignedIn";
  static const String isEventInMyProgramColumn = "isEventInMyProgram";

  Map<String, dynamic> toUpsertMap() {
    Map<String, dynamic> eventDataMap = Map.from(data ?? {});
    eventDataMap['is_cancelled'] = isCancelled;

    final Map<String, dynamic> upsertObj = {
      'start_time': timeContext.toUtc(startTime).toIso8601String(),
      'end_time': timeContext.toUtc(endTime).toIso8601String(),
      'title': title,
      'max_participants': maxParticipants,
      'place': place?.id,
      'split_for_men_women': splitForMenWomen,
      'is_group_event': isGroupEvent,
      'is_hidden': isHidden,
      'type': type,
      'data': eventDataMap,
    };
    return upsertObj;
  }

  Map<String, dynamic> toJson() {
    final eventData = <String, dynamic>{...?data};
    eventData['is_cancelled'] = isCancelled;

    return {
      idColumn: id,
      updatedAtColumn: updatedAt?.toIso8601String(),
      startTimeColumn: timeContext.toUtc(startTime).toIso8601String(),
      endTimeColumn: timeContext.toUtc(endTime).toIso8601String(),
      isHiddenColumn: isHidden,
      titleColumn: title,
      descriptionColumn: description,
      maxParticipantsColumn: maxParticipants,
      currentParticipantsColumn: currentParticipants,
      isSignedInColumn: isSignedIn,
      isEventInMyProgramColumn: isInMySchedule,
      isGroupEventColumn: isGroupEvent,
      placesTable: place?.toJson(),
      'type': type,
      childEventsList: childEventIds,
      'occasion': occasionId,
      dataColumn: eventData,
    };
  }

  static HashSet<EventModel> CreateEventModelSet() {
    return HashSet<EventModel>(
      equals: (a, b) => a.id == b.id,
      hashCode: (a) => a.id.hashCode,
    );
  }

  EventModel copyWith({
    Object? timeContext = _unchanged,
    Object? maxParticipants = _unchanged,
    Object? aggregateVersion = _unchanged,
    Object? order = _unchanged,
    Object? id = _unchanged,
    Object? updatedAt = _unchanged,
    Object? isHidden = _unchanged,
    Object? data = _unchanged,
    Object? place = _unchanged,
    Object? type = _unchanged,
    Object? childEvents = _unchanged,
    Object? eventRolesIds = _unchanged,
    Object? parentEventIds = _unchanged,
    Object? childEventIds = _unchanged,
    Object? currentParticipants = _unchanged,
    Object? currentUsersSaved = _unchanged,
    Object? title = _unchanged,
    Object? description = _unchanged,
    Object? isSignedIn = _unchanged,
    Object? splitForMenWomen = _unchanged,
    Object? isGroupEvent = _unchanged,
    Object? isMyGroupEvent = _unchanged,
    Object? isInMySchedule = _unchanged,
    Object? occasionId = _unchanged,
    Object? isCancelled = _unchanged,
    Object? startTime = _unchanged,
    Object? endTime = _unchanged,
  }) => EventModel(
    timeContext: identical(timeContext, _unchanged)
        ? this.timeContext
        : timeContext as OccasionTimeContext,
    maxParticipants: identical(maxParticipants, _unchanged)
        ? this.maxParticipants
        : maxParticipants as int?,
    aggregateVersion: identical(aggregateVersion, _unchanged)
        ? this.aggregateVersion
        : aggregateVersion as int,
    order: identical(order, _unchanged) ? this.order : order as int,
    id: identical(id, _unchanged) ? this.id : id as int?,
    updatedAt: identical(updatedAt, _unchanged)
        ? this.updatedAt
        : updatedAt as DateTime?,
    isHidden: identical(isHidden, _unchanged)
        ? this.isHidden
        : isHidden as bool?,
    data: identical(data, _unchanged)
        ? this.data
        : (data as Map?)?.cast<String, dynamic>(),
    place: identical(place, _unchanged) ? this.place : place as PlaceModel?,
    type: identical(type, _unchanged) ? this.type : type as String?,
    childEvents: identical(childEvents, _unchanged)
        ? this.childEvents
        : childEvents as List<EventModel>,
    eventRolesIds: identical(eventRolesIds, _unchanged)
        ? this.eventRolesIds
        : eventRolesIds as List<int>?,
    parentEventIds: identical(parentEventIds, _unchanged)
        ? this.parentEventIds
        : parentEventIds as List<int>?,
    childEventIds: identical(childEventIds, _unchanged)
        ? this.childEventIds
        : childEventIds as List<int>?,
    currentParticipants: identical(currentParticipants, _unchanged)
        ? this.currentParticipants
        : currentParticipants as int?,
    currentUsersSaved: identical(currentUsersSaved, _unchanged)
        ? this.currentUsersSaved
        : currentUsersSaved as int?,
    title: identical(title, _unchanged) ? this.title : title as String?,
    description: identical(description, _unchanged)
        ? this.description
        : description as String?,
    isSignedIn: identical(isSignedIn, _unchanged)
        ? this.isSignedIn
        : isSignedIn as bool?,
    splitForMenWomen: identical(splitForMenWomen, _unchanged)
        ? this.splitForMenWomen
        : splitForMenWomen as bool?,
    isGroupEvent: identical(isGroupEvent, _unchanged)
        ? this.isGroupEvent
        : isGroupEvent as bool?,
    isMyGroupEvent: identical(isMyGroupEvent, _unchanged)
        ? this.isMyGroupEvent
        : isMyGroupEvent as bool?,
    isInMySchedule: identical(isInMySchedule, _unchanged)
        ? this.isInMySchedule
        : isInMySchedule as bool?,
    occasionId: identical(occasionId, _unchanged)
        ? this.occasionId
        : occasionId as int?,
    isCancelled: identical(isCancelled, _unchanged)
        ? this.isCancelled
        : isCancelled as bool,
    startTime: identical(startTime, _unchanged)
        ? this.startTime
        : startTime as DateTime,
    endTime: identical(endTime, _unchanged)
        ? this.endTime
        : endTime as DateTime,
  );
}
