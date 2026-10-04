import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/schedule_feature.dart';

class ThemeConfig {
  static bool isDarkMode(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
  static const bool isDarkModeEnabled = true;
  static const AdaptiveThemeMode defaultThemeMode = AdaptiveThemeMode.light;

  static final fontFamily = "Gill Sans";

  /// The single shared Material 3 factory for application and local themes.
  static ThemeData theme({Brightness brightness = Brightness.light}) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? dddPrimary : lllPrimary;
    final scheme =
        colorSchemeForBrand(primary: primary, brightness: brightness);
    final chrome = appBarColor();
    final onChrome = textColorForBackground(chrome);
    final selected = seed2;
    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      primaryColor: primary,
      scaffoldBackgroundColor: dark ? dddBackground : lllBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: chrome,
        foregroundColor: onChrome,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: systemUiOverlayStyle(statusBarColor: chrome),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) => states
                  .contains(WidgetState.disabled)
              ? null
              : Color.alphaBlend(
                  primary.withValues(alpha: dark ? .18 : .10), scheme.surface)),
          side: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? BorderSide.none
                  : BorderSide(color: primary.withValues(alpha: .35))),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: chrome,
        surfaceTintColor: Colors.transparent,
        height: kBottomNavigationBarHeight,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? selected
                  : Colors.grey,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: fontFamily,
              fontSize: states.contains(WidgetState.selected) ? 14 : 12,
              fontWeight: FontWeight.w400,
              height: 1,
              letterSpacing: 0,
              overflow: TextOverflow.ellipsis,
              color: states.contains(WidgetState.selected)
                  ? selected
                  : Colors.grey,
            )),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: primary, width: 2)),
        labelStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height:
                0, // Use the font metrics without inheriting M3 line height.
            letterSpacing: 0),
        unselectedLabelStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height:
                0, // Use the font metrics without inheriting M3 line height.
            letterSpacing: 0),
        labelColor: primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
      ),
    );
  }

  /// Preserve configured brand colors while generating the complete M3 roles.
  static ColorScheme colorSchemeForBrand({
    required Color primary,
    required Brightness brightness,
    Color? secondary,
  }) {
    return ColorScheme.fromSeed(seedColor: primary, brightness: brightness)
        .copyWith(
      primary: primary,
      onPrimary: textColorForBackground(primary),
      secondary: secondary,
      onSecondary: secondary == null ? null : textColorForBackground(secondary),
    );
  }

  static SystemUiOverlayStyle systemUiOverlayStyle({Color? statusBarColor}) {
    final status = statusBarColor ?? appBarColor();
    final navigation = appBarColor();
    final darkStatus = textColorForBackground(status) == Colors.white;
    final darkNavigation = textColorForBackground(navigation) == Colors.white;
    return SystemUiOverlayStyle(
      statusBarColor: status,
      statusBarIconBrightness: darkStatus ? Brightness.light : Brightness.dark,
      statusBarBrightness: darkStatus ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: navigation,
      systemNavigationBarIconBrightness:
          darkNavigation ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: navigation,
      systemNavigationBarContrastEnforced: false,
    );
  }

  // Dynamic color methods with BuildContext for theme-based color adaptation
  static Color backgroundColor(BuildContext context) =>
      isDarkMode(context) ? dddBackground : lllBackground;
  static Color logoBackgroundColor(BuildContext context) =>
      backgroundColor(context);

  static Color surfaceColor(BuildContext context) => grey200(context);
  static Color seed1 = const Color(0xFF0000f4);
  static Color seed2 = const Color(0xFFfd6206);
  static Color seed3 = const Color(0xFF6785b7);
  static Color seed4 = const Color(0xFFffffff);

  static Color attentionColor(BuildContext context) => const Color(0xFF8B0000);

  static Color dddPrimary = seed2;
  static Color lllPrimary = seed1;

  static Color dddBackground =
      seed3.changeColorSaturation(0.08).changeColorLightness(0.14);
  static Color lllBackground = Color(0xFFe3e2d3);
  static Color dddText =
      seed3.changeColorSaturation(0.1).changeColorLightness(0.82);

  static Color dddBackgroundDarker = const Color(0xFF191a1e);

  static Color darkGreen =
      Colors.green.changeColorLightness(0.3).changeColorSaturation(0.5);
  static Color lightGreen =
      Colors.green.changeColorLightness(0.7).changeColorSaturation(0.5);

  static Color greenColor(BuildContext context) =>
      isDarkMode(context) ? lightGreen : darkGreen;
  static Color blueColor() =>
      Colors.deepPurple.changeColorLightness(0.3).changeColorSaturation(0.5);
  static Color redColor(BuildContext context) =>
      isDarkMode(context) ? Color(0xFFff5252) : Color(0xFFd32f2f);
  static Color warningColor(BuildContext context) =>
      isDarkMode(context) ? Colors.orangeAccent : Colors.orange;
  static Color darkColor(BuildContext context) =>
      isDarkMode(context) ? dddText : seed1;
  static Color blackColor(BuildContext context) =>
      isDarkMode(context) ? dddText : Colors.black;
  static Color whiteColor(BuildContext context) =>
      isDarkMode(context) ? dddBackground : Colors.white;
  static Color whiteTextColor(BuildContext context) =>
      isDarkMode(context) ? dddText : Colors.white;

  static Color whiteColorDarker(BuildContext context) => isDarkMode(context)
      ? dddBackgroundDarker
      : whiteColor(context).changeColorLightness(0.95);

  static Color timelineAll(BuildContext context) => isDarkMode(context)
      ? seed2.changeColorSaturation(0.6)
      : seed1.changeColorSaturation(0.4).changeColorLightness(0.4);
  static Color timelineSplitLabelColor(BuildContext context) =>
      timelineAll(context);
  static Color timelineTabLabelColor(BuildContext context) =>
      timelineAll(context);
  static Color timelineTabIndicatorColor(BuildContext context) =>
      timelineAll(context);
  static Color timelineColor(BuildContext context) => timelineAll(context);
  static Color timelineTextColor(BuildContext context) => blackColor(context);
  static Color timelineAddNewEventColor(BuildContext context) =>
      timelineAll(context);

  static Color mapPinColor(BuildContext context) => appBarColor();
  static Color newsPageColor(BuildContext context) => backgroundColor(context);
  static Color infoPageColor(BuildContext context) => backgroundColor(context);
  static Color profileButtonColor(BuildContext context) => appBarColor();
  static Color profileButtonTextColor(BuildContext context) =>
      textColorForBackground(appBarColor());

  static Color indicatorColor(BuildContext context) =>
      isDarkMode(context) ? dddPrimary : seed3;
  static Color tabTextColor(BuildContext context) =>
      blackColor(context).withOpacityUniversal(context, 0.7); //indicator color
  static Color indicatorTextColor(BuildContext context) =>
      whiteColorDarker(context); //header color

  static Color appBarColor() =>
      seed3.changeColorSaturation(0.5).changeColorLightness(0.10);
  static Color appBarColorNegative() => Colors.grey.changeColorLightness(0.8);

  static Color get brandAccentColor => seed2;

  static Color tabHeaderColor(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color upperNavText(BuildContext context) => isDarkMode(context)
      ? Theme.of(context).colorScheme.onSurface
      : Theme.of(context).colorScheme.surface;

  static Color timetableHorizontalLineColor(BuildContext context) =>
      appBarColor();
  static Color timetableSelectedColor(BuildContext context, Color color) =>
      isDarkMode(context)
          ? color.changeColorSaturation(0.7).changeColorLightness(0.8)
          : color.changeColorSaturation(0.5).changeColorLightness(0.6);
  static Color timetableUnselectedColor(BuildContext context, Color color) =>
      isDarkMode(context)
          ? color.changeColorSaturation(0.1).changeColorLightness(0.3)
          : color.changeColorSaturation(0.2).changeColorLightness(0.6);
  static Color timetableTimeSplitColor(BuildContext context) => Colors.red;
  static Color timetableBackground1(BuildContext context) =>
      whiteColor(context);
  static Color timetableBackground2(BuildContext context) =>
      whiteColorDarker(context);
  static Color timetableBackgroundOutside(BuildContext context) =>
      backgroundColor(context);
  static double get timetableTimeSplitOpacity => 0.15;

  static Color bigButtonColor(BuildContext context) =>
      isDarkMode(context) ? Color(0xFF5A5F6B) : Color(0xFFDCE2ED);
  static Color qrButtonColor(BuildContext context) =>
      isDarkMode(context) ? grey380(context) : bigButtonColor(context);
  static Color songButtonColor(BuildContext context) => isDarkMode(context)
      ? seed3.changeColorSaturation(0.2)
      : seed3.changeColorSaturation(0.2);

  static Color grey900(BuildContext context) =>
      isDarkMode(context) ? Colors.grey[200]! : Colors.grey[900]!;
  static Color grey850(BuildContext context) =>
      isDarkMode(context) ? Colors.grey[200]! : Colors.grey[850]!;
  static Color grey800(BuildContext context) =>
      isDarkMode(context) ? Colors.grey[200]! : Colors.grey[800]!;
  static Color grey700(BuildContext context) =>
      isDarkMode(context) ? Colors.grey[300]! : Colors.grey[700]!;
  static Color grey600(BuildContext context) =>
      isDarkMode(context) ? Colors.grey[400]! : Colors.grey[600]!;
  static Color grey500(BuildContext context) =>
      isDarkMode(context) ? Colors.grey[600]! : Colors.grey[500]!;
  static Color grey380(BuildContext context) => Colors.black38;
  static Color grey300(BuildContext context) =>
      isDarkMode(context) ? Colors.grey[800]! : Colors.grey[300]!;
  static Color grey200(BuildContext context) =>
      isDarkMode(context) ? Colors.grey[800]! : Colors.grey[200]!;
  static Color grey150(BuildContext context) =>
      isDarkMode(context) ? Colors.grey[850]! : Colors.grey[200]!;

  static Color defaultHtmlViewColor(BuildContext context) =>
      blackColor(context);
  static Color htmlLinkColor(BuildContext context) =>
      isDarkMode(context) ? seed2 : seed1;
  static Color correctGuessColor(BuildContext context) =>
      isDarkMode(context) ? seed3 : seed4;

  static Color textColorForBackground(Color background) {
    return background.computeLuminance() > 0.179 ? Colors.black : Colors.white;
  }

  // Function for eventTypeColor
  static Color eventTypeToColor(BuildContext context, String? typeCode) {
    if (typeCode == null) {
      return appBarColor();
    }

    final feature = FeatureService.getFeatureDetails(FeatureConstants.schedule);

    if (feature is ScheduleFeature) {
      final scheduleFeature = feature;
      // Find the event type by its code
      final eventType = scheduleFeature.eventTypes
          .firstWhereOrNull((et) => et.code == typeCode);

      if (eventType != null) {
        return eventType.getColor();
      }
    }

    return appBarColor();
  }

  static Color eventTypeToColorNegative(BuildContext context, String? type) {
    final Color backgroundColor = eventTypeToColor(context, type);
    return textColorForBackground(backgroundColor);
  }

  static Color eventTypeToColorTimetable(BuildContext context, String? type) {
    return eventTypeToColor(context, type);
  }
}

extension ColorExtensions on Color {
  Color withOpacityBlack(double factor) {
    assert(factor >= 0 && factor <= 1, 'Factor must be between 0 and 1');
    // Multiply factor by 1.4 and clamp between 0 and 1.
    final adjustedFactor = (factor * 1.4).clamp(0.0, 1.0);

    // Since r, g, b are doubles between 0 and 1, apply the adjusted factor and scale to 255.
    final int newR = (r * adjustedFactor * 255).round();
    final int newG = (g * adjustedFactor * 255).round();
    final int newB = (b * adjustedFactor * 255).round();

    // Convert the alpha (a) from normalized value to 0-255.
    return Color.fromARGB((a * 255).round(), newR, newG, newB);
  }

  Color withOpacityWhite(double factor) {
    assert(factor >= 0 && factor <= 1, 'Factor must be between 0 and 1');
    // Here, factor controls the blend with white: factor==0 gives pure white, factor==1 gives no change.
    // Compute the new normalized color by blending with white (1.0).
    final double newR = r + (1 - r) * (1 - factor);
    final double newG = g + (1 - g) * (1 - factor);
    final double newB = b + (1 - b) * (1 - factor);

    // Scale the blended normalized values to 0-255 and convert alpha similarly.
    return Color.fromARGB((a * 255).round(), (newR * 255).round(),
        (newG * 255).round(), (newB * 255).round());
  }

  Color withOpacityUniversal(BuildContext context, double factor) {
    return ThemeConfig.isDarkMode(context)
        ? withOpacityBlack(factor)
        : withOpacityWhite(factor);
  }

  Color changeColorSaturation(double newSaturationValue) =>
      HSLColor.fromColor(this).withSaturation(newSaturationValue).toColor();
  Color changeColorLightness(double newLightnessValue) =>
      HSLColor.fromColor(this).withLightness(newLightnessValue).toColor();
}
