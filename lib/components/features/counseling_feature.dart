import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/services/time_helper.dart';

import 'feature.dart';
import 'feature_constants.dart';

/// Counseling feature configuration (plan 2026-07-10, decision R4).
///
/// The feature toggle itself is the "enable counseling" switch — there is no
/// separate `counseling_enabled` flag anymore. Speakers are core and never
/// gated; only the counseling flow depends on this feature.
///
/// Config (occasions.features "counseling" element):
///   counseling_event_type    — event type code used for generated slots
///   registration_start_time  — own booking window for counseling slots
///   max_active_bookings      — max future counseling reservations per user
///                              (default 1, 0 = unlimited)
class CounselingFeature extends Feature {
  String counselingEventType;
  DateTime? registrationStartTime;
  int maxActiveBookings;

  CounselingFeature({
    super.code = FeatureConstants.counseling,
    super.isEnabled = false,
    super.title,
    super.description,
    this.counselingEventType = FeatureConstants.counselingDefaultEventType,
    this.registrationStartTime,
    this.maxActiveBookings = 1,
  });

  factory CounselingFeature.fromJson(Map<String, dynamic> json) {
    DateTime? parsed;
    final rawStart = json[FeatureConstants.counselingRegistrationStartTime];
    if (rawStart != null) {
      parsed = DateTime.parse(rawStart as String).toUtcFromOccasionTime();
    }
    final rawType = json[FeatureConstants.counselingEventType] as String?;
    return CounselingFeature(
      code: json[FeatureConstants.metaCode] as String? ??
          FeatureConstants.counseling,
      isEnabled: json[FeatureConstants.metaIsEnabled] as bool? ?? false,
      counselingEventType: (rawType != null && rawType.isNotEmpty)
          ? rawType
          : FeatureConstants.counselingDefaultEventType,
      registrationStartTime: parsed,
      maxActiveBookings:
          (json[FeatureConstants.counselingMaxActiveBookings] as num?)
                  ?.toInt() ??
              1,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
      FeatureConstants.counselingEventType: counselingEventType,
      FeatureConstants.counselingMaxActiveBookings: maxActiveBookings,
    };
    if (registrationStartTime != null) {
      data[FeatureConstants.counselingRegistrationStartTime] =
          registrationStartTime!.toIso8601String();
    }
    return data;
  }

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
