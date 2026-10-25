import 'package:material_ui/material_ui.dart';
import 'package:fstapp/theme_config.dart';

/// Base typography shared by displayed HTML and its editors.
TextStyle htmlTextStyle(BuildContext context,
        {double fontSize = 18, Color? color}) =>
    TextStyle(
      fontSize: fontSize,
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily ??
          ThemeConfig.fontFamily,
      color: color ?? ThemeConfig.defaultHtmlViewColor(context),
      inherit: false,
    );
