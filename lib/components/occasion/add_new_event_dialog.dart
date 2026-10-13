import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:fstapp/data_services/synchro_service.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/mouse_detector.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/components/occasion/occasion_home_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

import '../map/place_model.dart';
import '../map/place_picker_field.dart';

class AddNewEventDialog {
  static Future<void> showAddEventDialog(
      BuildContext context, List<TimeBlockGroup> timelineItems,
      [TimeBlockItem? parentEvent]) async {
    final formKey = GlobalKey<FormState>();
    String? title;
    DateTime? startDate;
    DateTime? endDate;
    int? placeId;
    List<PlaceModel>? places;
    final eventDayRangeTolerance = 7;
    DateTime? minDate;
    DateTime? maxDate;
    bool isFormValid = false;
    bool hasTitleBeenEdited = false;

    minDate = SynchroService.globalSettingsModel!.eventStartTime!
        .add(Duration(days: -eventDayRangeTolerance));
    maxDate = SynchroService.globalSettingsModel!.eventEndTime!
        .add(Duration(days: eventDayRangeTolerance));

    // Determine default values
    final lastEventGroup = timelineItems.isNotEmpty ? timelineItems.last : null;
    final lastEvent = lastEventGroup?.events
        .sorted((a, b) => a.startTime.compareTo(b.startTime))
        .lastOrNull;

    final defaultStartTime = parentEvent?.startTime ??
        lastEvent?.endTime ??
        SynchroService.globalSettingsModel!.eventStartTime!;
    final defaultEndTime =
        parentEvent?.endTime ?? defaultStartTime.add(Duration(hours: 1));
    final defaultPlaceId = lastEvent?.timeBlockPlace?.id;

    // Initialize defaults
    startDate = defaultStartTime;
    endDate = defaultEndTime;
    placeId = defaultPlaceId;

    // Load places
    places = await DbPlaces.getAllPlaces();

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return MouseDetector(
          builder: (context, mouseIsConnected) {
            return StatefulBuilder(
              builder: (context, setState) {
                void validateForm() {
                  isFormValid = title != null &&
                      title!.trim().isNotEmpty &&
                      startDate != null &&
                      endDate != null &&
                      !endDate!.isBefore(startDate!);
                }

                return AlertDialog(
                  title: Text(OccasionHomeStrings.addToSchedule),
                  content: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title field with validation
                        TextFormField(
                          initialValue: title,
                          decoration: InputDecoration(
                            labelText: CommonStrings.title,
                            labelStyle: TextStyle(
                              color: (hasTitleBeenEdited &&
                                      (title == null || title!.trim().isEmpty))
                                  ? ThemeConfig.redColor(context)
                                  : null,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              title = value;
                              if (!hasTitleBeenEdited) {
                                hasTitleBeenEdited = true;
                              }
                              validateForm();
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        TimeDateRangePicker(
                          start: startDate,
                          end: endDate,
                          onStartChanged: (dateTime) {
                            setState(() {
                              startDate = dateTime;
                              validateForm();
                            });
                          },
                          onEndChanged: (dateTime) {
                            setState(() {
                              endDate = dateTime;
                              validateForm();
                            });
                          },
                          minDate: minDate!,
                          maxDate: maxDate!,
                        ),
                        const SizedBox(height: 16),
                        // Place selection
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
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(CommonStrings.storno),
                    ),
                    ElevatedButton(
                      onPressed: isFormValid
                          ? () async {
                              if (formKey.currentState!.validate()) {
                                formKey.currentState!.save();
                                final newEvent = EventModel(
                                  title: title,
                                  place: places?.firstWhereOrNull(
                                      (place) => place.id == placeId),
                                  startTime: startDate!,
                                  endTime: endDate!,
                                  isHidden: false,
                                  splitForMenWomen: false,
                                  isSignedIn: false,
                                  isGroupEvent: false,
                                  parentEventIds: parentEvent != null
                                      ? [parentEvent.id]
                                      : null,
                                );
                                await DbEvents.updateEvent(newEvent);
                                Navigator.of(context).pop();
                              }
                            }
                          : null,
                      child: Text(CommonStrings.add),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
