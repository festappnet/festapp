// spot_management_constants.dart

import 'package:material_ui/material_ui.dart';

class SpotManagementConstants {
  // Base background colors for cells.
  static final Color lightModeCellBackground = Colors.grey.shade50;
  static final Color darkModeCellBackground = Colors.grey.shade900;
  static final Color lightModeCellHover = Colors.grey.shade200;
  static final Color darkModeCellHover = Colors.grey.shade800;

  // Column Field Names
  static const String rowIdentifier = 'row_identifier';
  static const String resourceTitle = 'resource_title';
  static const String rowReference =
      'row_reference'; // New unified reference column
  static const String contextColumnPrefix = 'context_';

  // Value Separators
  static const String cellValueSeparator = ';';

  // UI Text
  static const String assignActionText = 'Assign';

  /// Colors for the accent borders in light mode. Slightly more saturated for visibility.
  static List<Color> lightModeResourceColors = [
    Colors.blueGrey.shade200,
    Colors.teal.shade200,
    Colors.amber.shade300,
    Colors.deepOrange.shade200,
    Colors.lightGreen.shade300,
    Colors.purple.shade200,
    Colors.brown.shade200,
    Colors.indigo.shade200,
    Colors.cyan.shade200,
    Colors.pink.shade200,
  ];

  /// Colors for the accent borders in dark mode.
  static List<Color> darkModeResourceColors = [
    Colors.blueGrey.shade700,
    Colors.teal.shade700,
    Colors.amber.shade700,
    Colors.deepOrange.shade700,
    Colors.lightGreen.shade700,
    Colors.purple.shade700,
    Colors.brown.shade700,
    Colors.indigo.shade700,
    Colors.cyan.shade700,
    Colors.pink.shade700,
  ];

  /// Determines if the text on a given background color should be black or white for best contrast.
  /// This is less critical now as our main background is consistent, but still good to have.
  static Color getTextColorForBackground(Color backgroundColor) {
    return backgroundColor.computeLuminance() > 0.5
        ? Colors.black87
        : Colors.white;
  }
}
