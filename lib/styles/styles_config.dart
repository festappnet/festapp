import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/theme_config.dart';

class StylesConfig {
  // Text styles
  static const TextStyle timeLineTabNameTextStyle = TextStyle(fontSize: 15);
  static const TextStyle timeLineSmallTextStyle = TextStyle(fontSize: 15);

  static TextStyle timeLineSplitTextStyle(BuildContext context) => TextStyle(
        color: ThemeConfig.timelineSplitLabelColor(context),
        fontWeight: FontWeight.bold,
        fontSize: 15,
      );

  static const TextStyle normalTextStyle = TextStyle(fontSize: 18);

  // Font size
  static const double normalClickableFontSize = 18;

  // Dimensions
  static const double gridMaxWidth = 1200;
  static const double appMaxWidth = 720;
  static const double formMaxWidth = 680;
  static const double formMaxWidthMid = 580;

  static const double kToolbarHeight = 80.0;
  static const double kHorizontalPadding = 16.0;

  static const double signInSignOutRoundness = 16; //16
  static const double indicatorRoundness = 12; //0
  static const double eventItemRoundness = 12; //4
  static const double newsItemRoundness = 10; //2
  static const double imageRoundness = 100;

  static const double commonRoundness = 10;

  static const EdgeInsets tabHeaderPadding =
      EdgeInsets.symmetric(vertical: 4); //4
  static Border? indicatorBorder() => null;
  static Border? headerBorder() =>
      null; //Theme.of(context).scaffoldBackgroundColor

  static TextStyle textStyleBig =
      TextStyle(fontWeight: FontWeight.w900, fontSize: 16);

  static const double scheduleTimelineNodePosition = 0.35;

  // Button styles
  static ButtonStyle mainPageButtonStyle(BuildContext context) =>
      OutlinedButton.styleFrom(
        minimumSize: const Size(70, 50),
        maximumSize: const Size(80, 60),
        tapTargetSize: MaterialTapTargetSize.padded,
        backgroundColor: ThemeConfig.seed2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  static String formatDateTimeForTab(BuildContext context, DateTime time) {
    return time.weekdayToString(context);
  }

  static String formatTimelineSplit(String string) {
    return string;
  }

  static String formatTimelineRightText(String string) {
    return string;
  }
}
