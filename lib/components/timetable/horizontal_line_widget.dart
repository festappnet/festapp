import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/theme_config.dart';

import 'timetable_controller.dart';
import 'timetable_helper.dart';

class HorizontalLineWidget extends StatelessWidget {
  final DateTime startTime;
  final DateTime endTime;
  final int hourCount;
  final List<String>? basicStrings;
  final TimetableController controller;

  const HorizontalLineWidget(
      {super.key,
      required this.startTime,
      required this.endTime,
      required this.hourCount,
      required this.controller,
      this.basicStrings});

  @override
  Widget build(BuildContext context) {
    var now = TimeHelper.now();
    return Stack(
      children: [
        ...(basicStrings == null ? timeList(context) : basicList(context)),
        if (controller.isTimeHorizontal &&
            now.isAfter(startTime) &&
            now.isBefore(endTime))
          Padding(
            padding: EdgeInsets.fromLTRB(
                TimeHelper.differenceInHours(startTime, now) *
                        controller.pixelsInHour() -
                    50,
                controller.horizontalAxisSpaceHeight() + 6,
                0,
                0),
            child: TimetableHelper.showTime(context, now, controller),
          )
      ],
    );
  }

  List<Widget> basicList(BuildContext context) {
    final spacing = controller.verticalAxisSpace();
    // 1) Build a blank “slot” that’s exactly as tall as your real rows,
    //    painted with the same background + its own border on the right:
    final placeholder = Container(
      decoration: BoxDecoration(
        color: ThemeConfig.timetableHorizontalLineColor(context),
        border: Border(
          right: BorderSide(
            color: ThemeConfig.darkColor(context),
            width: 0.25,
          ),
        ),
      ),
      height: controller.horizontalAxisSpaceHeight(),
      width: spacing,
    );

    // 2) Now generate all your real columns exactly as before:
    final columns = List<Widget>.generate(basicStrings!.length, (i) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          spacing + i * controller.itemStaticDimension(),
          0,
          0,
          0,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: ThemeConfig.timetableHorizontalLineColor(context),
            // same thin left‐border for every real column after the first:
            border: i > 0
                ? Border(
                    left: BorderSide(
                      color: ThemeConfig.darkColor(context),
                      width: 0.25,
                    ),
                  )
                : null,
          ),
          height: controller.horizontalAxisSpaceHeight(),
          width: controller.itemStaticDimension(),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              basicStrings![i],
              textAlign: TextAlign.center,
              style: TextStyle(color: ThemeConfig.upperNavText(context)),
            ),
          ),
        ),
      );
    });

    // 3) Return a list with the placeholder first, then the real columns:
    return [placeholder, ...columns];
  }

  List<Widget> timeList(BuildContext context) {
    return List<Widget>.generate(hourCount + 1, (i) {
      var hour = startTime.hour + i;
      if (hour > 23) {
        hour -= 24;
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(
            i == 0
                ? 0
                : i * controller.pixelsInHour() - controller.pixelsInHour() / 2,
            0,
            0,
            0),
        child: Container(
          color: ThemeConfig.timetableHorizontalLineColor(context),
          height: controller.horizontalAxisSpaceHeight(),
          width: (i == hourCount || i == 0)
              ? controller.pixelsInHour() / 2
              : controller.pixelsInHour(),
          alignment: i == 0
              ? Alignment.centerLeft
              : i == hourCount
                  ? Alignment.centerRight
                  : Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              "$hour:00",
              style: TextStyle(color: ThemeConfig.upperNavText(context)),
            ),
          ),
        ),
      );
    });
  }
}
