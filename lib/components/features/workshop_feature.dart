import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/services/time_helper.dart';

import 'feature.dart';
import 'feature_constants.dart';

/// Feature for a workshop registration start time.
class WorkshopsFeature extends Feature {
  static const String metaStartTime = 'start_time';
  static const String metaWorkshops = 'workshops';
  static const String metaRegistrationNotOpenMessage =
      'registration_not_open_message';

  DateTime? startTime;
  String? registrationNotOpenMessage;

  WorkshopsFeature({
    super.code = metaWorkshops,
    super.isEnabled = true,
    super.title,
    super.description,
    this.startTime,
    this.registrationNotOpenMessage,
  });

  factory WorkshopsFeature.fromJson(Map<String, dynamic> json) {
    DateTime? parsed;
    if (json[metaStartTime] != null) {
      parsed =
          DateTime.parse(json[metaStartTime] as String).toUtcFromOccasionTime();
    }
    return WorkshopsFeature(
      code: json[FeatureConstants.metaCode] as String? ?? metaWorkshops,
      isEnabled: json[FeatureConstants.metaIsEnabled] as bool? ?? true,
      startTime: parsed,
      registrationNotOpenMessage:
          json[metaRegistrationNotOpenMessage] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
    };
    if (startTime != null) {
      data[metaStartTime] = startTime!.toIso8601String();
    }
    if (registrationNotOpenMessage != null) {
      data[metaRegistrationNotOpenMessage] = registrationNotOpenMessage;
    }
    return data;
  }

  /// Builds the form field for this feature in FeatureForm.
  @override
  Widget buildFormField(BuildContext context) {
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
