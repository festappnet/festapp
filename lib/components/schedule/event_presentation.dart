import 'package:festapp_core/program.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

extension EventPresentation on EventModel {
  String startTimeString() => DateFormat.Hm().format(startTime);
  String durationTimeString() =>
      "${DateFormat.Hm().format(startTime)} - ${DateFormat.Hm().format(endTime)}";
  String durationString(BuildContext context) =>
      "${DateFormat("EEEE, MMM d, HH:mm", context.locale.languageCode).format(startTime)} - ${DateFormat.Hm().format(endTime)}";
  String durationCompactString(BuildContext context) =>
      durationCompactStringForLocale(context.locale.languageCode);

  String displayLabel() {
    String titleStr = title ?? "";
    if (isCancelled) {
      titleStr += " (${CommonStrings.cancelled})";
    }
    final capacity = participantCapacityLabel;
    return capacity == null ? titleStr : "$titleStr ($capacity)";
  }

  String toBasicString() =>
      "$title${isCancelled ? ' (${CommonStrings.cancelled})' : ''}";
}
