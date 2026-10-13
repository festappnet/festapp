import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/components/map/place_picker_field.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/data_services/synchro_service.dart';
import 'package:fstapp/widgets/mouse_detector.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';

/// Result of the counseling-slot dialog: the picked time range, place and
/// capacity. The caller persists it (create via [DbSpeakers.createCounselingSlots],
/// edit via [DbEvents.updateEvent]). Times are occasion-local wall-clock, same
/// convention as [AddNewEventDialog].
typedef CounselingSlotResult = ({
  DateTime start,
  DateTime end,
  int? placeId,
  int capacity,
});

/// Quick single-slot editor, mirroring the "Add to schedule" dialog
/// ([AddNewEventDialog]). One slot at a time — no bulk generator.
class CounselingSlotDialog {
  /// Shows the dialog and returns the picked values, or null if cancelled.
  /// Pass the `initial*` values to edit an existing slot.
  static Future<CounselingSlotResult?> show(
    BuildContext context, {
    required List<PlaceModel> places,
    DateTime? initialStart,
    DateTime? initialEnd,
    int? initialPlaceId,
    int initialCapacity = 1,
  }) async {
    const eventDayRangeTolerance = 7;
    final minDate = SynchroService.globalSettingsModel!.eventStartTime!
        .add(const Duration(days: -eventDayRangeTolerance));
    final maxDate = SynchroService.globalSettingsModel!.eventEndTime!
        .add(const Duration(days: eventDayRangeTolerance));

    // A new slot defaults to the occasion start + a typical 20-minute length.
    DateTime startDate = initialStart ??
        SynchroService.globalSettingsModel!.eventStartTime!;
    DateTime endDate =
        initialEnd ?? startDate.add(const Duration(minutes: 20));
    int? placeId = initialPlaceId;
    final capacityController =
        TextEditingController(text: '$initialCapacity');
    final isEditing = initialStart != null;

    final result = await showDialog<CounselingSlotResult>(
      context: context,
      builder: (BuildContext context) {
        return MouseDetector(
          builder: (context, mouseIsConnected) {
            return StatefulBuilder(
              builder: (context, setState) {
                final capacity =
                    int.tryParse(capacityController.text.trim()) ?? 0;
                final isValid = !endDate.isBefore(startDate) &&
                    endDate.difference(startDate).inMinutes >= 5 &&
                    capacity >= 1;

                return AlertDialog(
                  title: Text(isEditing
                      ? SpeakersStrings.editSlot
                      : SpeakersStrings.addSlot),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TimeDateRangePicker(
                          start: startDate,
                          end: endDate,
                          minDate: minDate,
                          maxDate: maxDate,
                          onStartChanged: (dateTime) {
                            if (dateTime == null) return;
                            setState(() {
                              startDate = dateTime;
                              // Keep the range valid: nudge the end along when
                              // the start crosses it.
                              if (!endDate.isAfter(startDate)) {
                                endDate =
                                    startDate.add(const Duration(minutes: 20));
                              }
                            });
                          },
                          onEndChanged: (dateTime) {
                            if (dateTime == null) return;
                            setState(() => endDate = dateTime);
                          },
                        ),
                        const SizedBox(height: 16),
                        PlacePickerField(
                          places: places,
                          selectedPlaceId: placeId,
                          labelText: SpeakersStrings.slotPlace,
                          placeholder: "---",
                          onChanged: (id) => setState(() => placeId = id),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: capacityController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: InputDecoration(
                            labelText: SpeakersStrings.slotCapacity,
                          ),
                          onChanged: (_) => setState(() {}),
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
                      onPressed: isValid
                          ? () => Navigator.of(context).pop((
                                start: startDate,
                                end: endDate,
                                placeId: placeId,
                                capacity: capacity,
                              ))
                          : null,
                      child: Text(isEditing
                          ? CommonStrings.save
                          : CommonStrings.add),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    capacityController.dispose();
    return result;
  }
}
