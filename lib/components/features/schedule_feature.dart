import 'package:material_ui/material_ui.dart';
import 'package:fstapp/theme_config.dart';

import 'feature.dart'; // Assuming this is your base Feature class
import 'feature_constants.dart';

class _InternalThemeConfig {
  static Color get seed1 => ThemeConfig.seed1;
  static Color get seed2 => ThemeConfig.seed2;
  static Color get seed3 => ThemeConfig.seed3;
  static Color get seed4 => ThemeConfig.seed4;

  static Color? getSeedColorByName(String seedName) {
    switch (seedName.toLowerCase()) {
      case "seed1":
        return seed1;
      case "seed2":
        return seed2;
      case "seed3":
        return seed3;
      case "seed4":
        return seed4;
      default:
        return null;
    }
  }
}

/// Represents a configurable event type.
class EventType {
  String code;
  String title;
  String
      colorDefinition; // Can be a seed color name (e.g., "seed1") or a hex string (e.g., "#FF0000")

  EventType({
    required this.code,
    required this.title,
    required this.colorDefinition,
  });

  factory EventType.fromJson(Map<String, dynamic> json) {
    return EventType(
      code: json['code'] as String? ?? 'default_code',
      title: json['title'] as String? ?? 'Default Title',
      colorDefinition: json['colorDefinition'] as String? ?? 'seed1',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'title': title,
      'colorDefinition': colorDefinition,
    };
  }

  /// Gets the actual Color based on the colorDefinition.
  Color getColor() {
    final seedColor = _InternalThemeConfig.getSeedColorByName(colorDefinition);
    if (seedColor != null) {
      return seedColor;
    }
    try {
      String hex = colorDefinition.toUpperCase().replaceAll("#", "");
      if (hex.length == 6) {
        hex = "FF$hex"; // Add alpha if missing
      }
      if (hex.length == 8) {
        return Color(int.parse("0x$hex"));
      }
    } catch (e) {
      // Fallback for invalid hex
    }
    return Colors.transparent; // Default or error color
  }
}

/// Feature for schedule with a type of "basic" or "advanced".
class ScheduleFeature extends Feature {
  static const String metaScheduleType = "schedule_type";
  static const String metaSchedule = "schedule";
  static const String scheduleTypeBasic = "basic";
  static const String scheduleTypeAdvanced = "advanced";
  static const String scheduleTypeLight = "light";

  static const String metaBreakDefinition = "break_definition";
  static const String metaAfternoonBreak = "afternoon_break_time";
  static const String metaEveningBreak = "evening_break_time";
  static const String breakDefinitionTime = "time";
  static const String breakDefinitionPlace = "place";

  static const String metaEventTypes = "event_types";
  static const String metaEnableChildren = "enable_children"; // New constant

  String? scheduleType;
  bool enableChildren; // New property
  String breakDefinition;
  TimeOfDay afternoonBreakTime;
  TimeOfDay eveningBreakTime;
  List<EventType> eventTypes;

  ScheduleFeature({
    super.code = metaSchedule,
    super.isEnabled = true,
    super.title,
    super.description,
    this.scheduleType,
    this.enableChildren = true,
    this.breakDefinition = breakDefinitionTime,
    TimeOfDay? afternoonBreakTime,
    TimeOfDay? eveningBreakTime,
    List<EventType>? eventTypes,
  })  : afternoonBreakTime =
            afternoonBreakTime ?? const TimeOfDay(hour: 12, minute: 0),
        eveningBreakTime =
            eveningBreakTime ?? const TimeOfDay(hour: 18, minute: 0),
        eventTypes = eventTypes ?? [];

  factory ScheduleFeature.fromJson(Map<String, dynamic> json) {
    TimeOfDay timeFromString(String? timeString, TimeOfDay defaultTime) {
      if (timeString == null) return defaultTime;
      try {
        final parts = timeString.split(':');
        return TimeOfDay(
            hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (e) {
        return defaultTime;
      }
    }

    var eventTypesData = json[metaEventTypes] as List<dynamic>?;
    List<EventType> parsedEventTypes = eventTypesData
            ?.map((typeJson) =>
                EventType.fromJson(typeJson as Map<String, dynamic>))
            .toList() ??
        [];

    return ScheduleFeature(
      code: json[FeatureConstants.metaCode] ?? metaSchedule,
      isEnabled: json[FeatureConstants.metaIsEnabled] ?? true,
      title: json[FeatureConstants.metaTitle],
      description: json[FeatureConstants.metaDescription],
      scheduleType: json[metaScheduleType] ?? scheduleTypeAdvanced,
      enableChildren: json[metaEnableChildren] ?? true,
      breakDefinition: json[metaBreakDefinition] ?? breakDefinitionTime,
      afternoonBreakTime: timeFromString(
          json[metaAfternoonBreak], const TimeOfDay(hour: 12, minute: 0)),
      eveningBreakTime: timeFromString(
          json[metaEveningBreak], const TimeOfDay(hour: 18, minute: 0)),
      eventTypes: parsedEventTypes,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    String timeToString(TimeOfDay time) {
      final hour = time.hour.toString().padLeft(2, '0');
      final minute = time.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    final data = {
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
      metaEnableChildren: enableChildren, // Serializing new property
      metaBreakDefinition: breakDefinition,
      metaEventTypes: eventTypes.map((type) => type.toJson()).toList(),
    };

    if (scheduleType != null) {
      data[metaScheduleType] = scheduleType!;
    }
    if (breakDefinition == breakDefinitionTime) {
      data[metaAfternoonBreak] = timeToString(afternoonBreakTime);
      data[metaEveningBreak] = timeToString(eveningBreakTime);
    }
    return data;
  }
}

/// A stateful widget to manage the form's UI state.
