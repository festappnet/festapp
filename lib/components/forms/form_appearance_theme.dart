import 'package:festapp_core/forms.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/theme_config.dart';

/// Theme mode has the same meaning in public forms and draft previews.
ThemeData formAppearanceBaseTheme(
  BuildContext context,
  FormDefinition definition,
) {
  final brightness = switch (definition.themeMode) {
    'light' => Brightness.light,
    'dark' => Brightness.dark,
    _ => Theme.of(context).brightness,
  };
  return ThemeConfig.theme(brightness: brightness);
}

/// Public forms and draft previews share accent, control and background styling.
ThemeData formAppearanceTheme(ThemeData theme, FormDefinition definition) {
  int? primaryInt = definition.primaryColor;
  int? secondaryInt = definition.secondaryColor;

  Color? primary = primaryInt != null ? Color(primaryInt) : null;
  Color? secondary = secondaryInt != null ? Color(secondaryInt) : null;

  bool isDark = theme.brightness == Brightness.dark;

  if (primary != null) {
    final hsl = HSLColor.fromColor(primary);
    if (isDark && hsl.lightness < 0.75) {
      primary = hsl.withLightness(0.75).toColor();
      if (hsl.saturation < 0.3) {
        primary = HSLColor.fromColor(primary).withSaturation(0.4).toColor();
      }
    }

    secondary ??= HSLColor.fromColor(primary)
        .withLightness((isDark ? 0.85 : 0.9).clamp(0.0, 1.0))
        .toColor();

    theme = theme.copyWith(
      primaryColor: primary,
      scaffoldBackgroundColor: Color.alphaBlend(
        primary.withValues(alpha: isDark ? 0.05 : 0.07),
        isDark ? Colors.grey.shade900 : Colors.white,
      ),
      colorScheme: ThemeConfig.colorSchemeForBrand(
        primary: primary,
        secondary: secondary,
        brightness: theme.brightness,
      ).copyWith(surface: isDark ? null : Colors.white),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return primary!;
          }
          return isDark ? Colors.grey.shade400 : Colors.grey.shade600;
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(
          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
          width: 2,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return primary!;
          }
          return isDark ? Colors.grey.shade400 : Colors.grey.shade600;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return primary!;
          }
          return isDark ? Colors.grey.shade400 : Colors.grey.shade200;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return primary!.withValues(alpha: 0.5);
          }
          return isDark ? Colors.grey.shade700 : Colors.grey.shade400;
        }),
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: isDark ? Colors.grey.shade800 : Colors.white,
        labelStyle: TextStyle(
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: ThemeConfig.textColorForBackground(primary),
        ),
      ),
    );
  }
  return theme;
}

BoxDecoration? formAppearanceBackground(
  ThemeData theme,
  FormDefinition definition,
) {
  final mode = (definition.data?['design'] as Map?)?['background_mode'];
  if (!['solid', 'gradient'].contains(mode) ||
      definition.primaryColor == null) {
    return null;
  }
  final primary = theme.scaffoldBackgroundColor;
  final isDark = theme.brightness == Brightness.dark;
  final secondary = definition.secondaryColor == null
      ? primary
      : Color.alphaBlend(
          Color(definition.secondaryColor!)
              .withValues(alpha: isDark ? .05 : .07),
          isDark ? Colors.grey.shade900 : Colors.white,
        );
  return BoxDecoration(
    color: primary,
    gradient: mode == 'gradient' && definition.secondaryColor != null
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, secondary],
          )
        : null,
  );
}
