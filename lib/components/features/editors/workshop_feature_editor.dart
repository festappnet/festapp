import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/services/time_helper.dart';
import '../workshop_feature.dart';

extension WorkshopsFeatureSettingsEditor on WorkshopsFeature {
  Widget buildSettingsEditor(BuildContext context) {
    return StatefulBuilder(
      builder: (ctx, updateLocal) {
        void setLocalState(VoidCallback change) {
          updateLocal(change);
          EditorDraftScope.changed(ctx);
        }

        final locale = context.locale.toString();
        final dateFmt = DateFormat.yMd(locale).add_jm();
        final displayStartTime = startTime != null
            ? dateFmt.format(startTime!.toOccasionTime())
            : '';

        final startTimeController =
            TextEditingController(text: displayStartTime);
        final messageController =
            TextEditingController(text: registrationNotOpenMessage ?? '');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: startTimeController,
              decoration: InputDecoration(
                labelText: FeaturesStrings.registrationStartTime,
                hintText: FeaturesStrings.selectStartTime,
              ),
              readOnly: true,
              onTap: () async {
                final now = DateTime.now();
                final initial = startTime?.toOccasionTime() ?? now;
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
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
                setLocalState(() {
                  startTime = selectedLocal.toUtcFromOccasionTime();
                  startTimeController.text = dateFmt.format(selectedLocal);
                });
              },
              onSaved: (val) {
                if (val != null && val.isNotEmpty) {
                  final parsedLocal = dateFmt.parse(val);
                  startTime = parsedLocal.toUtcFromOccasionTime();
                }
              },
            ),
            SizedBox(height: 16.0),
            TextFormField(
              controller: messageController,
              decoration: InputDecoration(
                labelText: FeaturesStrings.earlyRegistrationMessage,
                hintText: FeaturesStrings.earlyRegistrationMessageHint,
              ),
              onSaved: (val) {
                registrationNotOpenMessage =
                    val != null && val.isNotEmpty ? val : null;
              },
            ),
          ],
        );
      },
    );
  }
}
