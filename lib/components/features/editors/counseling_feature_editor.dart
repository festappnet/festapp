import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/services/time_helper.dart';
import '../counseling_feature.dart';

extension CounselingFeatureSettingsEditor on CounselingFeature {
  Widget buildSettingsEditor(BuildContext context) {
    return StatefulBuilder(
      builder: (ctx, updateLocal) {
        void setLocalState(VoidCallback change) {
          updateLocal(change);
          EditorDraftScope.changed(ctx);
        }

        final locale = context.locale.toString();
        final dateFmt = DateFormat.yMd(locale).add_jm();
        final displayStart = registrationStartTime != null
            ? dateFmt.format(registrationStartTime!.toOccasionTime())
            : '';

        final startController = TextEditingController(text: displayStart);
        final maxController =
            TextEditingController(text: maxActiveBookings.toString());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The slot event type is fixed — generated slots rely on this
            // exact value.
            TextFormField(
              initialValue: counselingEventType,
              readOnly: true,
              enabled: false,
              decoration: InputDecoration(
                labelText: SpeakersStrings.counselingEventType,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: maxController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: SpeakersStrings.maxActiveBookings,
              ),
              onSaved: (val) {
                maxActiveBookings = int.tryParse(val?.trim() ?? '') ?? 1;
                if (maxActiveBookings < 0) maxActiveBookings = 0;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: startController,
              decoration: InputDecoration(
                labelText: SpeakersStrings.registrationStartTime,
                hintText: FeaturesStrings.selectStartTime,
              ),
              readOnly: true,
              onTap: () async {
                final now = DateTime.now();
                final initial = registrationStartTime?.toOccasionTime() ?? now;
                final date = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  locale: context.locale,
                );
                if (date == null) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(initial),
                );
                if (time == null) return;
                final selectedLocal = DateTime(
                    date.year, date.month, date.day, time.hour, time.minute);
                setLocalState(() {
                  registrationStartTime = selectedLocal.toUtcFromOccasionTime();
                  startController.text = dateFmt.format(selectedLocal);
                });
              },
              onSaved: (val) {
                if (val != null && val.isNotEmpty) {
                  final parsedLocal = dateFmt.parse(val);
                  registrationStartTime = parsedLocal.toUtcFromOccasionTime();
                }
              },
            ),
          ],
        );
      },
    );
  }
}
