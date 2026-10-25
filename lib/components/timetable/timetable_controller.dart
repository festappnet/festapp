import 'package:material_ui/material_ui.dart';

class TimetableController {
  void Function()? autoSetPosition;
  void Function()? rebuild;
  void Function()? reset;
  void Function(int)? onItemTap;
  bool isTimeHorizontal = false;
  double pixelsInHour() => isTimeHorizontal == true ? 200 : 100;
  double minimalPadding() => 1.5;
  double verticalAxisTitleHeight() => 40;
  double horizontalAxisSpaceHeight() => isTimeHorizontal == true ? 30 : 60;
  double verticalAxisSpace() => isTimeHorizontal == true ? 0 : 60;
  double itemStaticDimension() => isTimeHorizontal == true ? 56 : 112;
  int minimalDurationMinutes() => isTimeHorizontal == true ? 25 : 15;

  TimetableController({this.onItemTap});

  //support max 1 day skipping
  double timeRangeLength(DateTime startTime, DateTime endTime) {
    var range = DateTimeRange(start: startTime, end: endTime);
    return range.duration.inMinutes / 60.0 * pixelsInHour();
  }
}
