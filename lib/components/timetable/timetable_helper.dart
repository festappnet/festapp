import 'package:flutter/material.dart';
import 'package:fstapp/theme_config.dart';
import 'package:intl/intl.dart';

import 'timetable_controller.dart';

class TimetableHelper {
  static Widget showTime(
      BuildContext context, DateTime now, TimetableController controller) {
    return SizedBox(
      width: 100,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
            color: ThemeConfig.timetableTimeSplitColor(context),
            borderRadius: BorderRadius.circular(5.0),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            DateFormat.jm().format(now),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
