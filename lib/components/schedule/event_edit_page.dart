import 'dart:async';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/event_feedback/event_feedback_strings.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/features/schedule_feature.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:fstapp/components/speakers/admin/speaker_editor_dialog.dart';
import 'package:fstapp/components/speakers/admin/speaker_picker_field.dart';
import 'package:fstapp/components/speakers/db_speakers.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speaker_topic_model.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/data_services/synchro_service.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/mouse_detector.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';
import '../map/place_model.dart';
import '../map/place_picker_field.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

@RoutePage()
class EventEditPage extends StatefulWidget {
  static const ROUTE = "eventEdit";
  int? id;

  EventEditPage({super.key, @pathParam this.id});

  @override
  _EventEditPageState createState() => _EventEditPageState();
}

class _EventEditPageState extends State<EventEditPage> {
  final _htmlSave = HtmlSaveCoordinator();
  @override
  Widget build(BuildContext context) => HtmlEditingScope(
      coordinator: _htmlSave, child: _buildHtmlParent(context));
  @override
  void dispose() {
    _htmlSave.dispose();
    super.dispose();
  }

  final eventDayRangeTolerance = 7;
  final _formKey = GlobalKey<FormState>();
  EventModel? originalEvent;
  List<PlaceModel>? places;
  List<EventType> _definedEventTypes = []; // For storing defined event types

  // Editable fields
  bool? isHidden;
  String? title, type, content, showInsideEvent;
  DateTime? startDate, endDate;
  int? maxParticipants, placeId;
  bool? splitForMenWomen, isGroupEvent;
  bool? isCancelled;
  bool feedbackEnabled = false;
  bool counselingEntry = false;
  bool isFormValid = true;
  final _snapshot = EditorSnapshot();
  Object get _draft => [
        isHidden,
        title,
        type,
        content,
        showInsideEvent,
        startDate?.toIso8601String(),
        endDate?.toIso8601String(),
        maxParticipants,
        placeId,
        splitForMenWomen,
        isGroupEvent,
        isCancelled,
        feedbackEnabled,
        counselingEntry,
        (_selectedSpeakerIds.toList()..sort())
      ];
  bool get _hasChanges => _snapshot.differs(_draft) || _htmlSave.hasActiveDraft;
  void _draftChanged() => scheduleMicrotask(() {
        if (!mounted) return;
        _formKey.currentState?.save();
        setState(() {});
      });

  // Speakers attached to this event. Speakers are core (no feature gate); the
  // picker shows for any saved event (decision R6).
  List<SpeakerModel>? _allSpeakers;
  List<SpeakerTopicModel>? _allTopics;
  final Set<int> _selectedSpeakerIds = {};

  DateTime? minDate;
  DateTime? maxDate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.id == null && context.routeData.hasPendingChildren) {
      widget.id = context.routeData.pendingChildren[0].params.getInt("id");
    }
    loadEventData();
  }

  Future<void> loadEventData() async {
    minDate = SynchroService.globalSettingsModel!.eventStartTime!
        .add(Duration(days: -eventDayRangeTolerance));
    maxDate = SynchroService.globalSettingsModel!.eventEndTime!
        .add(Duration(days: eventDayRangeTolerance));

    if (widget.id != null) {
      originalEvent = await DbEvents.getEvent(widget.id!, true);
    }

    places = await DbPlaces.getAllPlaces();

    // Fetch ScheduleFeature and its event types
    final scheduleFeatureInstance =
        FeatureService.getFeatureDetails(ScheduleFeature.metaSchedule)
            as ScheduleFeature?;
    if (scheduleFeatureInstance != null) {
      _definedEventTypes = scheduleFeatureInstance.eventTypes;
    }

    if (originalEvent != null) {
      isHidden = originalEvent!.isHidden;
      title = originalEvent!.title;
      startDate = originalEvent!.startTime;
      endDate = originalEvent!.endTime;
      maxParticipants = originalEvent!.maxParticipants;
      splitForMenWomen = originalEvent!.splitForMenWomen;
      isGroupEvent = originalEvent!.isGroupEvent;
      placeId = originalEvent!.place?.id;
      type = originalEvent!.type; // This will be the code or null
      content = originalEvent!.description;
      showInsideEvent =
          originalEvent!.parentEventIds?.map((e) => e.toString()).join(",") ??
              "";
      isCancelled = originalEvent!.isCancelled; // Load isCancelled status
      feedbackEnabled =
          originalEvent!.data?[FeatureConstants.feedbackEnabled]?.toString() ==
              'true';
      counselingEntry =
          originalEvent!.data?[FeatureConstants.counselingEntry]?.toString() ==
              'true';
    }

    // Load speakers + the set currently attached to this event. Speakers are
    // core (no feature gate) and the load needs only the occasion, so it runs
    // for every event; the current selection is matched by event id (R6a).
    final speakerData = await ExceptionHandler.guard(
      context,
      futureFunction: () =>
          DbSpeakers.getSpeakersForEdit(RightsService.currentOccasionId()!),
    );
    if (speakerData != null) {
      _allSpeakers = speakerData.speakers;
      _allTopics = speakerData.topics;
      _selectedSpeakerIds
        ..clear()
        ..addAll(speakerData.speakers
            .where(
                (s) => s.events.any((e) => e.id == widget.id) && s.id != null)
            .map((s) => s.id!));
    }

    _snapshot.accept(_draft);
    validateForm();
    if (mounted) {
      setState(() {});
    }
  }

  void validateForm() {
    setState(() {
      isFormValid = title != null &&
          title!.trim().isNotEmpty &&
          startDate != null &&
          endDate != null &&
          !endDate!.isBefore(startDate!);
    });
  }

  Future<void> deleteEvent() async {
    final confirmation = await DialogHelper.showConfirmationDialog(
      context,
      CommonStrings.confirmRemoval,
      ScheduleStrings.deleteEventConfirm,
    );
    if (confirmation) {
      await originalEvent!.deleteMethod(context);
      ToastHelper.Show(
          context, "${CommonStrings.deleted}: ${originalEvent!.title!}");
      RouterService.popTwo(context);
    }
  }

  Future<void> saveChanges() async {
    await ExceptionHandler.guardVoid(context,
        futureFunction: () =>
            _htmlSave.save(() => _performHtmlSave(), context: context));
  }

  Future<void> _performHtmlSave() async {
    if (isFormValid && _formKey.currentState!.validate()) {
      _formKey.currentState!
          .save(); // This will call onSaved for all fields, including the new dropdown if it has one

      if (originalEvent != null) {
        content = await _htmlSave.prepare(
            content ?? '', HtmlMediaOwner.occasion(originalEvent!.occasionId));
        originalEvent!
          ..isHidden = isHidden!
          ..title = title!
          ..startTime = startDate!
          ..endTime = endDate!
          ..maxParticipants = maxParticipants == 0 ? null : maxParticipants
          ..splitForMenWomen = splitForMenWomen!
          ..isGroupEvent = isGroupEvent!
          ..place = places!.firstWhereOrNull((p) => p.id == placeId)
          ..type =
              type // 'type' state variable is already updated by Dropdown's onChanged
          ..description = content
          ..isCancelled = isCancelled!
          ..parentEventIds =
              showInsideEvent != null && showInsideEvent!.isNotEmpty
                  ? showInsideEvent!
                      .split(",")
                      .map((e) => int.parse(e.trim()))
                      .toList()
                  : [];
        originalEvent!.data = {
          ...?originalEvent!.data,
          FeatureConstants.feedbackEnabled: feedbackEnabled,
          if (FeatureService.isCounselingEnabled())
            FeatureConstants.counselingEntry: counselingEntry,
        };

        // updateEvent returns an EventModel carrying the id even after an
        // insert, so speaker attachment never relies on widget.id (decision R6a).
        final updatedEvent = await DbEvents.updateEvent(originalEvent!);
        _htmlSave.markSaved();

        if (updatedEvent.id != null) {
          final speakerVersion = await ExceptionHandler.guard(
            context,
            futureFunction: () => DbSpeakers.setEventSpeakers(
              updatedEvent.id!,
              _selectedSpeakerIds.toList(),
              updatedEvent.aggregateVersion,
            ),
          );
          if (speakerVersion != null) {
            updatedEvent.aggregateVersion = speakerVersion;
          }
        }

        ToastHelper.Show(
            context, "${CommonStrings.saved}: ${originalEvent!.title!}");
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> cancelEdit() async {
    if (_hasChanges && !await confirmDiscardChanges(context)) return;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Opens the speaker editor to create a new speaker, reloads the list, and
  /// returns the newly created speaker's id so the picker can pre-select it.
  /// RPC lives here, not in [SpeakerPickerField] (decision R6).
  Future<int?> _addSpeaker() async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => SpeakerEditorDialog(
          speaker: SpeakerModel(), topics: _allTopics ?? []),
    );
    // _save pops the freshly saved SpeakerModel (decision R6b); a bool from the
    // close button or null means nothing was created.
    if (result is! SpeakerModel) return null;

    // Reload so the picker's list includes the new speaker.
    final data = await ExceptionHandler.guard(
      context,
      futureFunction: () =>
          DbSpeakers.getSpeakersForEdit(RightsService.currentOccasionId()!),
    );
    if (data != null) {
      setState(() {
        _allSpeakers = data.speakers;
        _allTopics = data.topics;
      });
    }
    return result.id;
  }

  Widget _buildHtmlParent(BuildContext context) {
    return MouseDetector(
      builder: (context, mouseIsConnected) {
        return Scaffold(
          appBar: AppBar(
            title: Text(CommonStrings.edit),
            actions: [
              if (widget.id != null)
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: CommonStrings.delete,
                  onPressed: deleteEvent,
                ),
            ],
          ),
          body: (originalEvent == null && widget.id != null) ||
                  places == null // Updated loading condition
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        onChanged: _draftChanged,
                        child: ListView(
                          children: [
                            SwitchListTile(
                              title: Text(CommonStrings.hide),
                              value: isHidden ?? false,
                              onChanged: (value) =>
                                  setState(() => isHidden = value),
                            ),
                            SwitchListTile(
                              title: Text(CommonStrings.cancelled),
                              value: isCancelled ?? false,
                              onChanged: (value) =>
                                  setState(() => isCancelled = value),
                              activeThumbColor: ThemeConfig.redColor(context),
                            ),
                            if (FeatureService.isFeatureEnabled(
                                FeatureConstants.eventFeedback))
                              SwitchListTile(
                                title: Text(
                                    EventFeedbackStrings.enableEventFeedback),
                                value: feedbackEnabled,
                                onChanged: (value) =>
                                    setState(() => feedbackEnabled = value),
                              ),
                            if (FeatureService.isCounselingEnabled())
                              SwitchListTile(
                                title:
                                    Text(SpeakersStrings.counselingEntryToggle),
                                value: counselingEntry,
                                onChanged: (value) =>
                                    setState(() => counselingEntry = value),
                              ),
                            TextFormField(
                              initialValue: title,
                              decoration: InputDecoration(
                                labelText: CommonStrings.title,
                                labelStyle: TextStyle(
                                  color:
                                      (title == null || title!.trim().isEmpty)
                                          ? ThemeConfig.redColor(context)
                                          : null,
                                ),
                              ),
                              validator: FormBuilderValidators.required(
                                errorText: FormBuilderLocalizations.of(context)
                                    .requiredErrorText,
                              ),
                              onChanged: (value) {
                                title = value;
                                validateForm();
                              },
                              onSaved: (value) => title = value,
                            ),
                            const SizedBox(height: 16),
                            TimeDateRangePicker(
                              start: startDate,
                              end: endDate,
                              onStartChanged: (newStart) {
                                setState(() {
                                  startDate = newStart;
                                  if (newStart != null &&
                                      endDate != null &&
                                      newStart.isAfter(endDate!)) {
                                    endDate = DateTime(
                                      newStart.year,
                                      newStart.month,
                                      newStart.day,
                                      endDate!.hour,
                                      endDate!.minute,
                                    );
                                  }
                                  validateForm();
                                });
                              },
                              onEndChanged: (newEnd) {
                                setState(() {
                                  endDate = newEnd;
                                  if (newEnd != null &&
                                      startDate != null &&
                                      newEnd.isBefore(startDate!)) {
                                    startDate = DateTime(
                                      newEnd.year,
                                      newEnd.month,
                                      newEnd.day,
                                      startDate!.hour,
                                      startDate!.minute,
                                    );
                                  }
                                  validateForm();
                                });
                              },
                              minDate: minDate!,
                              maxDate: maxDate!,
                            ),
                            const SizedBox(height: 16),
                            PlacePickerField(
                              places: places ?? [],
                              selectedPlaceId: placeId,
                              labelText: CommonStrings.place,
                              placeholder: "---",
                              onChanged: (id) {
                                setState(() {
                                  placeId = id;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              initialValue: maxParticipants != null &&
                                      maxParticipants! > 0
                                  ? maxParticipants.toString()
                                  : "",
                              decoration: InputDecoration(
                                labelText: ScheduleStrings.maxParticipants,
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value != null && value.trim().isNotEmpty) {
                                  final parsedValue =
                                      int.tryParse(value.trim());
                                  if (parsedValue == null || parsedValue < 0) {
                                    return FormBuilderLocalizations.of(context)
                                        .positiveNumberErrorText;
                                  }
                                }
                                return null;
                              },
                              onSaved: (value) {
                                maxParticipants =
                                    (value == null || value.trim().isEmpty)
                                        ? 0
                                        : int.tryParse(value.trim());
                              },
                            ),
                            // Speakers are core: the picker shows whenever the
                            // speaker list has loaded — no feature gate and no
                            // widget.id condition (decision R6).
                            if (_allSpeakers != null) ...[
                              const SizedBox(height: 16),
                              SpeakerPickerField(
                                allSpeakers: _allSpeakers!,
                                selectedIds: _selectedSpeakerIds.toList(),
                                onChanged: (ids) => setState(() {
                                  _selectedSpeakerIds
                                    ..clear()
                                    ..addAll(ids);
                                }),
                                onAddSpeaker: _addSpeaker,
                              ),
                            ],
                            const SizedBox(height: 16),
                            Text(
                              CommonStrings.content,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            EditableHtmlField(
                                html: content,
                                coordinator: _htmlSave,
                                owner: HtmlMediaOwner.occasion(
                                    originalEvent!.occasionId),
                                onChanged: (html) =>
                                    setState(() => content = html)),
                            const SizedBox(height: 16),
                            ExpansionTile(
                              title: Text(
                                CommonStrings.advancedSettings,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              children: [
                                SwitchListTile(
                                  title: Text(ScheduleStrings.group),
                                  value: isGroupEvent ?? false,
                                  onChanged: (value) =>
                                      setState(() => isGroupEvent = value),
                                ),
                                SwitchListTile(
                                  title: Text(ScheduleStrings.splitMenWomen),
                                  value: splitForMenWomen ?? false,
                                  onChanged: (value) =>
                                      setState(() => splitForMenWomen = value),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                      vertical:
                                          8.0), // Add padding to align with TextFormFields
                                  child: Builder(builder: (context) {
                                    // Dedupe items by value: tolerate two EventTypes
                                    // sharing the same code without tripping the
                                    // DropdownButton "exactly one item" assert.
                                    final seenValues = <String?>{};
                                    final typeItems =
                                        <DropdownMenuItem<String?>>[
                                      DropdownMenuItem<String?>(
                                        value: "",
                                        child: Text(FeaturesStrings.noType),
                                      ),
                                    ];
                                    seenValues.add("");
                                    for (final eventType
                                        in _definedEventTypes) {
                                      if (seenValues.add(eventType.code)) {
                                        typeItems.add(DropdownMenuItem<String?>(
                                          value: eventType.code,
                                          child: Text(eventType.title),
                                        ));
                                      }
                                    }
                                    // Resolve current value against known codes.
                                    // Legacy events may store the title instead
                                    // of the code — try to recover that case.
                                    String? resolvedType;
                                    if (type == null || type!.isEmpty) {
                                      resolvedType = "";
                                    } else if (seenValues.contains(type)) {
                                      resolvedType = type;
                                    } else {
                                      final byTitle =
                                          _definedEventTypes.firstWhereOrNull(
                                              (e) => e.title == type);
                                      resolvedType = byTitle?.code;
                                    }
                                    return DropdownButtonFormField<String?>(
                                      initialValue: resolvedType,
                                      decoration: InputDecoration(
                                        labelText: CommonStrings.type,
                                        border: const OutlineInputBorder(),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10.0,
                                                vertical: 15.0),
                                      ),
                                      items: typeItems,
                                      onChanged: (String? newValue) {
                                        setState(() {
                                          type = newValue;
                                        });
                                      },
                                    );
                                  }),
                                ),
                                TextFormField(
                                  initialValue: showInsideEvent,
                                  decoration: InputDecoration(
                                      labelText:
                                          ScheduleStrings.showInsideEvent),
                                  onSaved: (value) => showInsideEvent = value,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          bottomNavigationBar: AnimatedBuilder(
            animation: _htmlSave,
            builder: (context, _) => Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: cancelEdit,
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    child: Text(CommonStrings.back),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: isFormValid && _hasChanges ? saveChanges : null,
                    child: Text(CommonStrings.save),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
