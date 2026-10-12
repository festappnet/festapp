import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/features/schedule_feature.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/schedule/suspicious_event_detector.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/images/db_images.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/images/image_compression_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/images/image_area.dart';
import 'package:fstapp/components/speakers/admin/event_speakers_cell.dart';
import 'package:fstapp/components/speakers/admin/speaker_editor_dialog.dart';
import 'package:fstapp/components/speakers/db_speakers.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speaker_topic_model.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:trina_grid/trina_grid.dart';

import '../map/place_model.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class ScheduleContent extends StatefulWidget {
  final bool suspiciousOnly;

  const ScheduleContent({super.key, this.suspiciousOnly = false});

  @override
  ScheduleContentState createState() => ScheduleContentState();
}

class ScheduleContentState extends State<ScheduleContent> {
  OccasionModel? occasionModel;
  List<String> places = [];

  // New state variables for event types
  ScheduleFeature? _scheduleFeature;
  List<EventType> _definedEventTypes = [];
  final List<String> _eventTypeSelectOptions = [];
  static const String _noTypeSelectValue =
      ""; // Represents "No Type", saved as empty string

  bool _isLoading = true; // Unified loading state

  // Loaded once for the occasion; `_eventSpeakerIds` maps event id -> attached
  // speaker ids so each grid cell can render its current selection without a
  // per-row fetch.
  final List<SpeakerModel> _allSpeakers = [];
  List<SpeakerTopicModel> _allTopics = [];
  final Map<int, List<int>> _eventSpeakerIds = {};
  final Map<int, ({EventModel event, List<SuspiciousEventReason> reasons})>
      _suspiciousEventDetails = {};

  SingleDataGridController<EventModel>? controller;

  /// Refreshes a review list only when doing so cannot discard local edits.
  Future<void> reloadIfClean() async {
    final currentController = controller;
    if (currentController == null ||
        currentController.updatedRows.isNotEmpty ||
        currentController.deletedRows.isNotEmpty ||
        currentController.newRows.isNotEmpty) {
      return;
    }
    await currentController.reloadData();
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      occasionModel =
          await DbUsers.getOccasion(RightsService.currentOccasionId()!);

      var placesRaws = await DbPlaces.getMapPlaces();
      var placesStrings =
          placesRaws.map((p) => p.toPlutoSelectString()).toList();
      placesStrings.add(PlaceModel.WithoutValue);
      // Ensure places list is updated on the state
      if (mounted) {
        setState(() {
          places.clear();
          places.addAll(placesStrings);
        });
      }

      _scheduleFeature =
          FeatureService.getFeatureDetails(ScheduleFeature.metaSchedule)
              as ScheduleFeature?;
      _definedEventTypes = _scheduleFeature?.eventTypes ?? [];

      _eventTypeSelectOptions.clear();
      _eventTypeSelectOptions.add(_noTypeSelectValue); // Value for "No Type"
      for (var et in _definedEventTypes) {
        _eventTypeSelectOptions.add(et.code);
      }

      await _loadSpeakers();
    } catch (e) {
      AppLogger.error("Error loading initial data for ScheduleContent: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        if (!_isLoading) {
          initController();
        }
      }
    }
  }

  /// Loads all speakers + the topic catalog for the occasion and rebuilds the
  /// event -> speaker-ids map. `_allSpeakers` is mutated in place elsewhere so
  /// inline-created speakers stay visible to every open cell.
  Future<void> _loadSpeakers() async {
    final data = await ExceptionHandler.guard(
      context,
      futureFunction: () =>
          DbSpeakers.getSpeakersForEdit(RightsService.currentOccasionId()!),
    );
    if (data == null) return;
    _allSpeakers
      ..clear()
      ..addAll(data.speakers);
    _allTopics = data.topics;
    _eventSpeakerIds.clear();
    for (final s in data.speakers) {
      if (s.id == null) continue;
      for (final e in s.events) {
        (_eventSpeakerIds[e.id] ??= []).add(s.id!);
      }
    }
  }

  /// Opens the speaker editor to create a new speaker, appends it to the shared
  /// `_allSpeakers` list and returns its id so the picker can pre-select it.
  /// Mirrors event_edit_page._addSpeaker (RPC lives in SpeakerEditorDialog).
  Future<int?> _addSpeaker() async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) =>
          SpeakerEditorDialog(speaker: SpeakerModel(), topics: _allTopics),
    );
    if (result is! SpeakerModel) return null;

    final data = await ExceptionHandler.guard(
      context,
      futureFunction: () =>
          DbSpeakers.getSpeakersForEdit(RightsService.currentOccasionId()!),
    );
    if (data != null) {
      _allSpeakers
        ..clear()
        ..addAll(data.speakers);
      _allTopics = data.topics;
    }
    return result.id;
  }

  /// Persists the speaker selection for one event and keeps the local map in
  /// sync so re-opening the cell shows the saved set.
  Future<int?> _saveEventSpeakers(
      int eventId, int expectedVersion, List<int> speakerIds) async {
    final version = await ExceptionHandler.guard(
      context,
      futureFunction: () =>
          DbSpeakers.setEventSpeakers(eventId, speakerIds, expectedVersion),
    );
    if (version == null) return null;
    _eventSpeakerIds[eventId] = List.of(speakerIds);
    // Keep the column's searchable value current so filtering reflects the
    // inline edit without a full grid reload.
    final row = controller?.stateManager.rows.firstWhereOrNull(
        (r) => r.cells[EventModel.idColumn]?.value == eventId);
    row?.cells[EventModel.speakersColumn]?.value =
        _speakerNamesFor(speakerIds) ?? '';
    row?.cells[EventModel.aggregateVersionColumn]?.value = version;
    if (mounted) {
      ToastHelper.Show(context, CommonStrings.saved);
    }
    return version;
  }

  /// Joins the given speakers' names into a searchable string (or null when
  /// none), used to populate the "Přednášející" column's filterable cell value.
  String? _speakerNamesFor(Iterable<int> speakerIds) {
    final names = speakerIds
        .map((id) => _allSpeakers.firstWhereOrNull((s) => s.id == id)?.title)
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();
    return names.isEmpty ? null : names.join(', ');
  }

  /// Loads the grid's events and stamps each with its attached speakers' names
  /// so the "Přednášející" column's text filter can match by speaker. Speaker
  /// data is already loaded into `_allSpeakers` / `_eventSpeakerIds` before the
  /// grid mounts.
  Future<List<EventModel>> _loadEventsForGrid() async {
    var events = await DbEvents.getAllEventsForDatagrid();
    if (widget.suspiciousOnly) {
      final analysis = SuspiciousEventDetector.analyze(
        events,
        occasionStart: occasionModel?.startTime,
        occasionEnd: occasionModel?.endTime,
      );
      _suspiciousEventDetails
        ..clear()
        ..addEntries(
            analysis.entries.where((entry) => entry.key.id != null).map(
                  (entry) => MapEntry(
                    entry.key.id!,
                    (event: entry.key, reasons: entry.value),
                  ),
                ));
      events = analysis.keys.toList();
    }
    for (final e in events) {
      final ids = e.id == null ? null : _eventSpeakerIds[e.id];
      e.speakerNamesSearch =
          (ids == null || ids.isEmpty) ? null : _speakerNamesFor(ids);
    }
    return events;
  }

  String _formatDateTime(DateTime value) => DateFormat(
        'd. M. yyyy HH:mm',
        context.locale.languageCode,
      ).format(value);

  String _formatRange(DateTime start, DateTime end) =>
      '${_formatDateTime(start)} – ${_formatDateTime(end)}';

  String _suspiciousReasonLabel(SuspiciousEventReason reason) {
    return switch (reason) {
      SuspiciousEventReason.invalidTiming =>
        ScheduleStrings.suspiciousReasonInvalidTiming,
      SuspiciousEventReason.multiDay =>
        ScheduleStrings.suspiciousReasonMultiDay,
      SuspiciousEventReason.outsideOccasion =>
        ScheduleStrings.suspiciousReasonOutsideOccasion,
      SuspiciousEventReason.exactDuplicate =>
        ScheduleStrings.suspiciousReasonExactDuplicate,
    };
  }

  ({Color background, Color foreground, IconData icon, int priority})
      _suspiciousReasonStyle(
    BuildContext context,
    SuspiciousEventReason reason,
  ) {
    final colors = Theme.of(context).colorScheme;
    return switch (reason) {
      SuspiciousEventReason.invalidTiming => (
          background: colors.errorContainer,
          foreground: colors.onErrorContainer,
          icon: Icons.error_outline_rounded,
          priority: 4,
        ),
      SuspiciousEventReason.outsideOccasion => (
          background: colors.tertiaryContainer,
          foreground: colors.onTertiaryContainer,
          icon: Icons.event_busy_outlined,
          priority: 3,
        ),
      SuspiciousEventReason.exactDuplicate => (
          background: colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
          icon: Icons.content_copy_rounded,
          priority: 2,
        ),
      SuspiciousEventReason.multiDay => (
          background: colors.secondaryContainer,
          foreground: colors.onSecondaryContainer,
          icon: Icons.date_range_outlined,
          priority: 1,
        ),
    };
  }

  String _suspiciousReasonDetail(
    EventModel event,
    SuspiciousEventReason reason,
  ) {
    return switch (reason) {
      SuspiciousEventReason.invalidTiming =>
        ScheduleStrings.suspiciousReasonInvalidTimingDetail(
          start: _formatDateTime(event.startTime),
          end: _formatDateTime(event.endTime),
        ),
      SuspiciousEventReason.multiDay =>
        ScheduleStrings.suspiciousReasonMultiDayDetail(
          start: _formatDateTime(event.startTime),
          end: _formatDateTime(event.endTime),
        ),
      SuspiciousEventReason.outsideOccasion =>
        ScheduleStrings.suspiciousReasonOutsideOccasionDetail(
          eventRange: _formatRange(event.startTime, event.endTime),
          occasionRange:
              occasionModel?.startTime != null && occasionModel?.endTime != null
                  ? _formatRange(
                      occasionModel!.startTime!,
                      occasionModel!.endTime!,
                    )
                  : '—',
        ),
      SuspiciousEventReason.exactDuplicate =>
        ScheduleStrings.suspiciousReasonExactDuplicateDetail(
          title: event.title ?? '',
          time: _formatRange(event.startTime, event.endTime),
          place: event.place?.title ?? FeaturesStrings.none,
        ),
    };
  }

  void _showSuspiciousReasonDialog(
    EventModel event,
    List<SuspiciousEventReason> reasons,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ScheduleStrings.suspiciousReason),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title ?? CommonStrings.event,
                style: Theme.of(dialogContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ...reasons.map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _suspiciousReasonStyle(dialogContext, reason).icon,
                        size: 20,
                        color: _suspiciousReasonStyle(dialogContext, reason)
                            .foreground,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _suspiciousReasonLabel(reason),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(_suspiciousReasonDetail(event, reason)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(CommonStrings.close),
          ),
        ],
      ),
    );
  }

  Widget _suspiciousReasonRenderer(TrinaColumnRendererContext rendererContext) {
    final eventId =
        rendererContext.row.cells[EventModel.idColumn]?.value as int?;
    final details = eventId == null ? null : _suspiciousEventDetails[eventId];
    if (details == null || details.reasons.isEmpty) {
      return const SizedBox.shrink();
    }

    final dominantReason = details.reasons.reduce((current, candidate) =>
        _suspiciousReasonStyle(context, candidate).priority >
                _suspiciousReasonStyle(context, current).priority
            ? candidate
            : current);
    final dominantStyle = _suspiciousReasonStyle(context, dominantReason);
    final firstLabel = _suspiciousReasonLabel(dominantReason);
    final extraCount = details.reasons.length - 1;
    final chipLabel =
        extraCount == 0 ? firstLabel : '$firstLabel  +$extraCount';

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Tooltip(
          showDuration: const Duration(seconds: 15),
          preferBelow: true,
          verticalOffset: 28,
          padding: EdgeInsets.zero,
          decoration: const BoxDecoration(color: Colors.transparent),
          richMessage: WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 340),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: details.reasons.mapIndexed((index, reason) {
                    final style = _suspiciousReasonStyle(context, reason);
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == details.reasons.length - 1 ? 0 : 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: style.background,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Icon(
                              style.icon,
                              size: 16,
                              color: style.foreground,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _suspiciousReasonLabel(reason),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _suspiciousReasonDetail(
                                    details.event,
                                    reason,
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        height: 1.35,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          child: ActionChip(
            avatar: Icon(
              dominantStyle.icon,
              size: 16,
              color: dominantStyle.foreground,
            ),
            label: Text(
              chipLabel,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dominantStyle.foreground,
                fontSize: 11,
              ),
            ),
            backgroundColor: dominantStyle.background,
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onPressed: () => _showSuspiciousReasonDialog(
              details.event,
              details.reasons,
            ),
          ),
        ),
      ),
    );
  }

  void initController() {
    if (controller != null || !mounted) return;

    controller = SingleDataGridController<EventModel>(
      context: context,
      loadData: _loadEventsForGrid,
      fromPlutoJson: EventModel.fromPlutoJson,
      firstColumnType: DataGridFirstColumn.deleteAndDuplicate,
      idColumn: Tb.events.id,
      columns: [
        if (widget.suspiciousOnly)
          TrinaColumn(
            title: ScheduleStrings.suspiciousReason,
            field: EventModel.suspiciousReasonColumn,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 210,
            renderer: _suspiciousReasonRenderer,
          ),
        TrinaColumn(
          title: CommonStrings.id,
          field: Tb.events.id,
          type: TrinaColumnType.number(defaultValue: -1),
          readOnly: true,
          width: 60,
          renderer: (rendererContext) =>
              DataGridHelper.idRenderer(rendererContext),
        ),
        TrinaColumn(
          title: CommonStrings.hide,
          field: Tb.events.is_hidden,
          type: TrinaColumnType.text(),
          applyFormatterInEditing: true,
          enableEditingMode: false,
          width: 60,
          renderer: (rendererContext) => DataGridHelper.checkBoxRenderer(
              rendererContext, Tb.events.is_hidden),
        ),
        TrinaColumn(
          title: ScheduleStrings.interest,
          field: Tb.event_users.table,
          readOnly: true,
          type: TrinaColumnType.number(negative: false, defaultValue: 0),
          width: 80,
        ),
        TrinaColumn(
          title: CommonStrings.cancelled,
          field: Tb.events.dataIsCancelled,
          type: TrinaColumnType.text(),
          applyFormatterInEditing: true,
          enableEditingMode: false,
          width: 85,
          renderer: (rendererContext) => DataGridHelper.checkBoxRenderer(
              rendererContext, Tb.events.dataIsCancelled),
        ),
        if (() {
          final t =
              (FeatureService.getFeatureDetails(ScheduleFeature.metaSchedule)
                      as ScheduleFeature?)
                  ?.scheduleType;
          return t == ScheduleFeature.scheduleTypeAdvanced ||
              t == ScheduleFeature.scheduleTypeLight;
        }())
          TrinaColumn(
            title: ScheduleStrings.introImage,
            field: Tb.events.dataHeaderImage,
            type: TrinaColumnType.text(defaultValue: null),
            width: 140,
            applyFormatterInEditing: true,
            renderer: (ctx) {
              final String? imageUrl = ctx.cell.value as String?;

              return GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      insetPadding: const EdgeInsets.symmetric(
                        horizontal: 40.0,
                        vertical: 24.0,
                      ),
                      title: Text(ScheduleStrings.introImage),
                      content: SizedBox(
                        width: 200.0,
                        height: 250.0,
                        child: ImageArea(
                          imageUrl: imageUrl,
                          onFileSelected: (file) async {
                            final bytes = await file.readAsBytes();
                            final compressed =
                                await ImageCompressionHelper.compress(
                                    bytes, 200);
                            final publicUrl = await DbImages.uploadImage(
                              compressed,
                              RightsService.currentOccasionId(),
                              null,
                            );
                            ctx.stateManager.changeCellValue(
                                ctx.cell, publicUrl,
                                force: true);
                            ToastHelper.Show(
                                context, ScheduleStrings.imageUploaded);
                            return publicUrl;
                          },
                          onRemove: () async {
                            if (imageUrl != null && imageUrl.isNotEmpty) {
                              await DbImages.removeImage(imageUrl);
                              ctx.stateManager
                                  .changeCellValue(ctx.cell, "", force: true);
                              ToastHelper.Show(
                                  context, ScheduleStrings.imageRemoved);
                            }
                          },
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(CommonStrings.close),
                        ),
                      ],
                    ),
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? Tooltip(
                          showDuration: const Duration(seconds: 0),
                          preferBelow: false,
                          padding: EdgeInsets.zero,
                          verticalOffset: 52,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                          ),
                          richMessage: WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                color: ThemeConfig.whiteColor(context),
                              ),
                              child: CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  width: 120,
                                  fit: BoxFit.contain),
                            ),
                          ),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.fitWidth,
                            placeholder: (context, url) => SizedBox(
                                width: 50,
                                height: 50,
                                child: Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.0))),
                            errorWidget: (context, url, error) =>
                                Icon(Icons.broken_image, size: 24),
                          ),
                        )
                      : Icon(Icons.image,
                          size: 24, color: Colors.grey.shade600),
                ),
              );
            },
          ),
        TrinaColumn(
          title: CommonStrings.title,
          field: EventModel.titleColumn,
          type: TrinaColumnType.text(),
          width: 250,
        ),
        TrinaColumn(
          title: SpeakersStrings.lecturers,
          field: EventModel.speakersColumn,
          type: TrinaColumnType.text(),
          readOnly: true,
          enableEditingMode: false,
          // The cell value carries the attached speakers' names (see
          // EventModel.speakerNamesSearch) so the default column filter can
          // search by speaker — like the place/title columns. Leaving
          // enableFilterMenuItem at its default keeps that filter field enabled.
          enableSorting: false,
          width: 180,
          renderer: (rendererContext) {
            final eventId =
                rendererContext.row.cells[EventModel.idColumn]?.value as int?;
            final aggregateVersion = (rendererContext
                        .row
                        .cells[EventModel.aggregateVersionColumn]
                        ?.value as num?)
                    ?.toInt() ??
                0;
            return EventSpeakersCell(
              // Trina reuses cell widgets across rows on scroll — key by event
              // id so the correct selection binds after a scroll/rebuild.
              key: ValueKey('event-speakers-$eventId'),
              eventId: eventId,
              aggregateVersion: aggregateVersion,
              allSpeakers: _allSpeakers,
              initialSelectedIds: eventId == null
                  ? const []
                  : (_eventSpeakerIds[eventId] ?? const []),
              onSave: _saveEventSpeakers,
              onAddSpeaker: _addSpeaker,
            );
          },
        ),
        TrinaColumn(
          title: CommonStrings.startDate,
          field: EventModel.startDateColumn,
          type: TrinaColumnType.date(defaultValue: occasionModel?.startTime),
          width: 110,
        ),
        TrinaColumn(
          title: CommonStrings.start,
          field: EventModel.startTimeColumn,
          type: TrinaColumnType.time(),
          width: 80,
        ),
        TrinaColumn(
          title: CommonStrings.endDate,
          field: EventModel.endDateColumn,
          type: TrinaColumnType.date(defaultValue: occasionModel?.startTime),
          width: 110,
        ),
        TrinaColumn(
          title: CommonStrings.end,
          field: EventModel.endTimeColumn,
          type: TrinaColumnType.time(),
          width: 80,
        ),
        TrinaColumn(
          title: CommonStrings.max,
          field: EventModel.maxParticipantsColumn,
          type: TrinaColumnType.number(negative: false, defaultValue: null),
          width: 70,
        ),
        TrinaColumn(
          title: CommonStrings.place,
          field: EventModel.placeColumn,
          type: TrinaColumnType.select(places,
              itemToString: DataGridHelper.getValueFromFormatted),
          applyFormatterInEditing: true,
          formatter: DataGridHelper.getValueFromFormatted,
          width: 140,
        ),
        TrinaColumn(
          width: 150,
          title: CommonStrings.content,
          field: Tb.events.description,
          type: TrinaColumnType.text(),
          renderer: (rendererContext) {
            return DataGridHelper.buildHtmlEditorButton(
              context: context,
              occasionId: RightsService.currentOccasionId(),
              field: Tb.events.description,
              rendererContext: rendererContext,
              title: rendererContext.row.cells[Tb.events.title]!.value,
              loadContent: () async {
                var eventId = rendererContext.row.cells[Tb.events.id]!.value;
                if (eventId != null) {
                  var fullEvent = await DbEvents.getEvent(eventId);
                  return fullEvent.description;
                }
                return null;
              },
            );
          },
        ),
        TrinaColumn(
          title: CommonStrings.type,
          field: Tb.events.type,
          // Field in EventModel storing the type code
          type: TrinaColumnType.select(_eventTypeSelectOptions),
          // Dropdown with loaded type codes
          width: 150,
          // Adjust width as needed
          textAlign: TrinaColumnTextAlign.center,
          // Center the chip in the cell
          renderer: (rendererContext) {
            final String? typeCode = rendererContext.cell.value as String?;

            if (typeCode == null || typeCode == _noTypeSelectValue) {
              return Center(
                  child: Text(
                FeaturesStrings.noType,
                style:
                    TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                overflow: TextOverflow.ellipsis,
              ));
            }

            final eventType = _definedEventTypes
                .firstWhereOrNull((et) => et.code == typeCode);

            if (eventType != null) {
              Color backgroundColor = eventType.getColor();
              // Determine contrasting text color for readability
              Color textColor =
                  ThemeConfig.eventTypeToColorNegative(context, eventType.code);
              String displayTitle = eventType.title;

              return Padding(
                // Add padding around the chip to prevent touching cell borders
                padding:
                    const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
                child: Chip(
                  label: Text(
                    displayTitle,
                    style: TextStyle(color: textColor, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                  backgroundColor: backgroundColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8.0, vertical: 0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  // Makes chip smaller
                  side: BorderSide.none, // Remove chip border if desired
                ),
              );
            } else {
              // Fallback: Type code exists but doesn't match any defined event type
              return Center(
                  child: Text(
                typeCode,
                style: TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ));
            }
          },
        ),
        TrinaColumn(
          title: ScheduleStrings.splitMenWomen,
          field: EventModel.splitForMenWomenColumn,
          type: TrinaColumnType.text(),
          applyFormatterInEditing: true,
          enableEditingMode: false,
          width: 100,
          renderer: (rendererContext) => DataGridHelper.checkBoxRenderer(
              rendererContext, EventModel.splitForMenWomenColumn),
        ),
        TrinaColumn(
          title: ScheduleStrings.group,
          field: EventModel.isGroupEventColumn,
          type: TrinaColumnType.text(),
          applyFormatterInEditing: true,
          enableEditingMode: false,
          width: 100,
          renderer: (rendererContext) => DataGridHelper.checkBoxRenderer(
              rendererContext, EventModel.isGroupEventColumn),
        ),
        if (FeatureService.isCounselingEnabled())
          TrinaColumn(
            title: SpeakersStrings.counselingEntryColumn,
            field: FeatureConstants.counselingEntry,
            type: TrinaColumnType.text(),
            applyFormatterInEditing: true,
            enableEditingMode: false,
            width: 100,
            renderer: (rendererContext) => DataGridHelper.checkBoxRenderer(
                rendererContext, FeatureConstants.counselingEntry),
          ),
        TrinaColumn(
          title: ScheduleStrings.showInsideEvent,
          field: EventModel.parentEventColumn,
          type: TrinaColumnType.text(),
          width: 300,
        ),
        TrinaColumn(
          title: ScheduleStrings.roles,
          field: Tb.event_roles.role,
          type: TrinaColumnType.text(),
          width: 100,
        ),
      ],
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller == null) {
      // This can happen if initController is called before _loadInitialData completes or if an error occurs
      return Center(child: Text(ScheduleStrings.initializing));
    }
    final grid = SingleTableDataGrid<EventModel>(controller!);
    if (!widget.suspiciousOnly) return grid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color:
              Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.45),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ScheduleStrings.suspiciousEventsDescription,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: grid),
      ],
    );
  }
}
