import 'package:material_ui/material_ui.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/info_tooltip_button.dart';

class HelpWidget extends StatelessWidget {
  final String title;
  final String content;
  final double targetSize;

  const HelpWidget({
    super.key,
    required this.title,
    required this.content,
    this.targetSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    return InfoTooltipButton(
      message: content,
      targetSize: targetSize,
      semanticLabel: '$title: $content',
      color: ThemeConfig.blackColor(context),
    );
  }
}
