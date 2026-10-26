import 'package:material_ui/material_ui.dart';

class ActivityConstants {
  // Constants
  static const double kTimelineLabelWidth =
      160.0; // Increased slightly for more space
  static const Duration kMinTimeLength = Duration(minutes: 5);
  static const Duration kSnapStepCoarse = Duration(minutes: 15);
  static const Duration kSnapStepFine = Duration(minutes: 5);
  // New: Default duration for user assignments
  static const Duration kDefaultUserAssignmentDuration = Duration(hours: 4);

  // Constants for timeline
  static const double kInitialScale = 0.2;
  static const double kMinScale = 0.05;
  static const double kMaxScale = 2.0;
  static const double kScaleFactor = 1.25;
  static const double kInitialPanOffset = 0.0;
  static const double kBasePixelsPerSecond = 0.05;

  static const double kDateHeaderHeightConstant = 30.0;
  static const double kTimeTickAreaHeightConstant = 28.0;
  static const double kTotalTimelineRulerHeightConstant =
      kDateHeaderHeightConstant + kTimeTickAreaHeightConstant;

  static const double realHeightAddition = 240;

  // New: Darker color variants for user assignments and avatars
  static final List<Color> darkUserColors = [
    Colors.red.shade700,
    Colors.pink.shade700,
    Colors.purple.shade700,
    Colors.deepPurple.shade700,
    Colors.indigo.shade700,
    Colors.blue.shade700,
    Colors.lightBlue.shade800,
    Colors.cyan.shade800,
    Colors.teal.shade700,
    Colors.green.shade700,
    Colors.lightGreen.shade800,
    Colors.lime.shade900,
    Colors.amber.shade800,
    Colors.orange.shade800,
    Colors.deepOrange.shade700,
    Colors.brown.shade600,
    Colors.blueGrey.shade600,
    Colors.red.shade900,
    Colors.pink.shade900,
    Colors.purple.shade900,
    Colors.deepPurple.shade900,
    Colors.indigo.shade900,
    Colors.blue.shade900,
    Colors.teal.shade900,
    Colors.green.shade900,
    Colors.brown.shade800,
    Colors.blueGrey.shade800
  ];

  // Helper for dark mode detection
  static bool isDarkMode(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// The interval at which the editor will automatically save a draft.
  static const Duration autosaveInterval = Duration(seconds: 3);

  /// The maximum age for history items. Records older than this will be
  /// cleaned up on the next save operation.
  static const Duration historyMaxAge = Duration(days: 30);

}
