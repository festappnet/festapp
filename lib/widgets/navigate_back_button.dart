import 'package:material_ui/material_ui.dart';
import 'package:fstapp/router_service.dart';

class ScheduleBackButton extends StatelessWidget {
  final Color? color;
  final double iconSize;

  const ScheduleBackButton({
    super.key,
    this.color,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    // if (!RouterService.canPop(context)) {
    //   return const SizedBox.shrink();
    // }

    // Use the passed-in color if given, otherwise fall back to your theme
    final iconColor =
        color ?? Theme.of(context).navigationBarTheme.indicatorColor;

    return IconButton(
      icon: Icon(
        Icons.arrow_back,
        color: iconColor,
        size: iconSize,
      ),
      // Switch from an async arrow to a plain block so we return void, not Future
      onPressed: () {
        RouterService.scheduleBack(context);
      },
    );
  }
}
