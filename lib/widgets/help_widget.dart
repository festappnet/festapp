import 'package:flutter/material.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/info_tooltip_button.dart';

class HelpWidget extends StatelessWidget {
  final String title;
  final String content;

  const HelpWidget({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return InfoTooltipButton(
      message: content,
      semanticLabel: '$title: $content',
      color: ThemeConfig.blackColor(context),
    );
  }
}
