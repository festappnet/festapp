import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/components/timetable/timetable_event_widget.dart';
import 'package:fstapp/theme_config.dart';

import 'timetable_controller.dart';

class TimetableItemsWidget extends StatefulWidget {
  final List<TimeBlockItem> usedItems;
  final List<TimeBlockPlace> usedPlaces;
  final double height;
  final double width;
  final TimetableController controller;
  final Future<void> Function(TimeBlockItem)? addToMyProgram;
  final Future<void> Function(TimeBlockItem)? removeFromMyProgram;
  final DateTime startTime;
  final DateTime endTime;
  final int xyHelpingColumnsCount;

  const TimetableItemsWidget({
    super.key,
    required this.usedItems,
    required this.usedPlaces,
    required this.height,
    required this.width,
    required this.controller,
    this.addToMyProgram,
    this.removeFromMyProgram,
    required this.startTime,
    required this.endTime,
    required this.xyHelpingColumnsCount,
  });

  @override
  _TimetableItemsWidgetState createState() => _TimetableItemsWidgetState();
}

class _TimetableItemsWidgetState extends State<TimetableItemsWidget> {
  @override
  void initState() {
    super.initState();
  }

  List<Widget> buildTimeline() {
    List<Widget> allItems = [];
    if (widget.controller.isTimeHorizontal) {
      allItems.add(Row(
        children: List<Widget>.generate(
          widget.xyHelpingColumnsCount,
          (i) => Container(
            width: widget.controller.pixelsInHour(),
            height: widget.height,
            decoration: BoxDecoration(
              border: const Border(
                left: BorderSide(width: 0.25, color: Colors.grey),
                right: BorderSide(width: 0.25, color: Colors.grey),
              ),
              color: i % 2 == 0
                  ? ThemeConfig.timetableBackground1(context)
                  : ThemeConfig.timetableBackground2(context),
            ),
          ),
        ),
      ));
    } else {
      allItems.add(Column(
        children: [
          Container(
            width: widget.width,
            height: widget.controller.horizontalAxisSpaceHeight(),
            color: Colors.transparent,
          ),
          ...List<Widget>.generate(
            widget.xyHelpingColumnsCount,
            (i) => Container(
              width: widget.width,
              height: widget.controller.pixelsInHour(),
              decoration: BoxDecoration(
                color: i % 2 == 0
                    ? ThemeConfig.timetableBackground1(context)
                    : ThemeConfig.timetableBackground2(context),
              ),
            ),
          ),
        ],
      ));
    }

    for (var p = 0; p < widget.usedPlaces.length; p++) {
      var pItems = widget.usedItems
          .where((element) =>
              element.timeBlockPlace?.id == widget.usedPlaces[p].id)
          .toList();
      for (var i = 0; i < pItems.length; i++) {
        var item = pItems[i];
        var left = widget.controller
                .timeRangeLength(widget.startTime, item.startTime) +
            widget.controller.minimalPadding();
        var top = (widget.controller.verticalAxisTitleHeight() +
                    widget.controller.itemStaticDimension()) *
                p +
            widget.controller.verticalAxisTitleHeight() +
            widget.controller.horizontalAxisSpaceHeight();
        var verticalLeft = widget.controller.verticalAxisSpace() +
            (widget.controller.itemStaticDimension() * p) +
            widget.controller.minimalPadding();
        var verticalTop = widget.controller.horizontalAxisSpaceHeight() +
            widget.controller
                .timeRangeLength(widget.startTime, item.startTime) +
            widget.controller.minimalPadding();
        var timeBlock = Positioned(
          left: widget.controller.isTimeHorizontal ? left : verticalLeft,
          top: widget.controller.isTimeHorizontal ? top : verticalTop,
          child: TimetableEventWidget(
            item: item,
            controller: widget.controller,
          ),
        );
        allItems.add(timeBlock);
      }
    }

    return allItems;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: buildTimeline(),
    );
  }
}
