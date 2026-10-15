import 'package:festapp_core/program.dart';
import 'package:festapp_core/map.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/schedule/event_commands.dart';
import 'package:fstapp/components/schedule/event_presentation.dart';
import 'package:fstapp/components/map/place_grid_record.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/database_tables/tb.dart';

class EventGridRecord extends ITrinaRowModel {
  EventGridRecord(
      {required this.event,
      required this.commands,
      required this.occasionId,
      this.speakerNamesSearch});
  EventModel event;
  final EventCommands commands;
  final int occasionId;
  final String? speakerNamesSearch;
  @override
  int? get id => event.id;
  @override
  String toBasicString() => event.toBasicString();
  @override
  TrinaRow toTrinaRow(BuildContext context) =>
      toRow(event, context, speakerNamesSearch: speakerNamesSearch);
  static EventGridRecord fromPlutoJson(Map<String, dynamic> json,
          {required EventCommands commands,
          required int occasionId,
          required OccasionTimeContext timeContext}) =>
      EventGridRecord(
          event: decode(json, timeContext: timeContext),
          commands: commands,
          occasionId: occasionId);
  static const String startDateColumn = "startDate";
  static const String endDateColumn = "endDate";
  static const String parentEventColumn = "parentEvent";
  static const String speakersColumn = "speakers";
  static const String suspiciousReasonColumn = "suspicious_reason";
  static EventModel decode(Map<String, dynamic> json,
      {required OccasionTimeContext timeContext}) {
    var startTimeString =
        json[startDateColumn] + "-" + json[EventModel.startTimeColumn];
    var endTimeString =
        json[endDateColumn] + "-" + json[EventModel.endTimeColumn];

    var placeId =
        DataGridHelper.getIdFromFormatted(json[EventModel.placeColumn]);
    var dateFormat = DateFormat("yyyy-MM-dd-HH:mm");

    List<int> parseIntList(dynamic value) =>
        (value?.toString().trim().isNotEmpty ?? false)
            ? value
                .toString()
                .split(',')
                .map((e) => int.parse(e.trim()))
                .toList()
            : [];

    List<int> parentEvents = parseIntList(json[parentEventColumn]);
    List<int> eventRoles = parseIntList(json[Tb.event_roles.role]);

    final dataFromTab = Map<String, dynamic>.from(
        (json[EventModel.dataColumn] as Map?) ?? const {});
    String? headerUrl = json[Tb.events.dataHeaderImage];
    if (headerUrl != null && headerUrl.isNotEmpty) {
      dataFromTab[Tb.events.dataHeaderImage] = headerUrl;
    } else {
      dataFromTab.remove(Tb.events.dataHeaderImage);
    }

    bool resolvedIsCancelled = false;
    if (json.containsKey(Tb.events.dataIsCancelled)) {
      final val = json[Tb.events.dataIsCancelled];
      if (val is bool) {
        resolvedIsCancelled = val;
      } else if (val is String) {
        resolvedIsCancelled = val.toLowerCase() == 'true';
      }
    }
    dataFromTab[Tb.events.dataIsCancelled] = resolvedIsCancelled;

    // Rozcestník flag lives in the data jsonb; the grid cell round-trips it as
    // a "true"/"false" string (missing when the counseling column is hidden,
    // which resolves to the existing value staying untouched below).
    if (json.containsKey(FeatureConstants.counselingEntry)) {
      dataFromTab[FeatureConstants.counselingEntry] =
          json[FeatureConstants.counselingEntry]?.toString() == 'true';
    }

    return EventModel(
      timeContext: timeContext,
      startTime: dateFormat.parse(startTimeString),
      endTime: dateFormat.parse(endTimeString),
      id: json[EventModel.idColumn] == -1 ? null : json[EventModel.idColumn],
      isHidden: json[EventModel.isHiddenColumn] == "true" ? true : false,
      updatedAt: json[EventModel.updatedAtColumn] != null
          ? DateTime.parse(json[EventModel.updatedAtColumn])
          : null,
      title: json[EventModel.titleColumn],
      description: json[EventModel.descriptionColumn],
      maxParticipants: json[EventModel.maxParticipantsColumn] == 0
          ? null
          : json[EventModel.maxParticipantsColumn],
      aggregateVersion: TrinaRowVersion.read(json),
      data: dataFromTab,
      place: placeId == null
          ? null
          : PlaceModel(id: placeId, title: "", description: "", type: ""),
      type: json[Tb.events.type],
      splitForMenWomen:
          json[EventModel.splitForMenWomenColumn] == "true" ? true : false,
      parentEventIds: parentEvents,
      eventRolesIds: eventRoles,
      isSignedIn: false,
      isGroupEvent:
          json[EventModel.isGroupEventColumn] == "true" ? true : false,
      occasionId: json.containsKey(Tb.events.occasion)
          ? json[Tb.events.occasion]
          : null,
      isCancelled: resolvedIsCancelled,
    );
  }

  static TrinaRow toRow(EventModel event, BuildContext context,
      {String? speakerNamesSearch}) {
    return TrinaRow(cells: {
      EventModel.dataColumn: TrinaCell(value: event.data),
      EventModel.idColumn: TrinaCell(value: event.id),
      EventModel.aggregateVersionColumn:
          TrinaRowVersion.cell(event.aggregateVersion),
      EventModel.isHiddenColumn: TrinaCell(value: event.isHidden.toString()),
      EventModel.titleColumn: TrinaCell(value: event.title),
      EventModel.descriptionColumn: TrinaCell(value: event.description),
      startDateColumn:
          TrinaCell(value: DateFormat('yyyy-MM-dd').format(event.startTime)),
      EventModel.startTimeColumn:
          TrinaCell(value: DateFormat('HH:mm').format(event.startTime)),
      endDateColumn:
          TrinaCell(value: DateFormat('yyyy-MM-dd').format(event.endTime)),
      EventModel.endTimeColumn:
          TrinaCell(value: DateFormat('HH:mm').format(event.endTime)),
      EventModel.maxParticipantsColumn: TrinaCell(value: event.maxParticipants),
      EventModel.placeColumn: TrinaCell(
          value: event.place == null
              ? PlaceModel.WithoutValue
              : event.place!.toPlutoSelectString()),
      Tb.events.type: TrinaCell(value: event.type ?? ""),
      EventModel.splitForMenWomenColumn:
          TrinaCell(value: event.splitForMenWomen.toString()),
      EventModel.isGroupEventColumn:
          TrinaCell(value: event.isGroupEvent.toString()),
      parentEventColumn: TrinaCell(
          value:
              event.parentEventIds?.map((e) => e.toString()).join(",") ?? ""),
      Tb.event_roles.role: TrinaCell(
          value: event.eventRolesIds?.map((e) => e.toString()).join(",") ?? ""),
      Tb.event_users.table: TrinaCell(
          value: (event.maxParticipants ?? 0) > 0
              ? event.currentParticipants ?? 0
              : event.currentUsersSaved ?? 0),
      Tb.events.dataHeaderImage:
          TrinaCell(value: event.data?[Tb.events.dataHeaderImage]),
      Tb.events.dataIsCancelled: TrinaCell(value: event.isCancelled.toString()),
      FeatureConstants.counselingEntry:
          TrinaCell(value: event.isCounselingEntry.toString()),
      speakersColumn: TrinaCell(value: speakerNamesSearch ?? ''),
      suspiciousReasonColumn: TrinaCell(value: ''),
    });
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    final result = await commands
        .save(event.copyWith(occasionId: event.occasionId ?? occasionId));
    if (result.status == EventCommandStatus.conflict)
      throw StateError('Event was changed by another editor');
    if (result.status == EventCommandStatus.rejected || result.event == null)
      throw StateError('Event save was rejected');
    event = result.event!;
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {
    final result = await commands
        .delete(event.copyWith(occasionId: event.occasionId ?? occasionId));
    if (result.status == EventCommandStatus.conflict)
      throw StateError('Event was changed by another editor');
    if (result.status == EventCommandStatus.rejected)
      throw StateError('Event deletion was rejected');
  }
}
