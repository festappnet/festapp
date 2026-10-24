import 'package:festapp_core/program.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

extension EventPresentation on EventModel {
  String startTimeString() => DateFormat.jm().format(startTime);
  String durationTimeString() =>
      "${DateFormat.jm().format(startTime)} - ${DateFormat.jm().format(endTime)}";
  String durationString(BuildContext context) =>
      "${DateFormat.MMMEd(context.locale.toString()).add_jm().format(startTime)} - ${DateFormat.jm().format(endTime)}";
  String durationCompactString(BuildContext context) =>
      durationCompactStringForLocale(context.locale.toString());

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
