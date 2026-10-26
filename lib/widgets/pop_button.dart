import 'package:material_ui/material_ui.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/theme_config.dart';

class PopButton extends StatelessWidget {
  final Color? color;
  final double iconSize;
  final VoidCallback? onPressed;

  const PopButton({
    super.key,
    this.color,
    this.iconSize = 24.0,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? ThemeConfig.appBarColorNegative();
    if (RouterService.canPop(context)) {
      return IconButton(
        icon: Icon(Icons.arrow_back, color: resolvedColor, size: iconSize),
        onPressed: onPressed ?? () => RouterService.popOrHome(context),
      );
    }
    return SizedBox.shrink();
  }
}
